import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pr_app/src/rust/api/laurelia.dart';

import '../services/notification_service.dart';

/// Chat LLM Laurelia: descarga el modelo desde HuggingFace por HTTP
/// (mismo flujo que `laurelia_example.gd` de Godot) y delega la inferencia
/// en Rust (Candle) vía flutter_rust_bridge.
///
///   const ckpt = 'checkpoint.pt'; // o 'fine-checkpoint.pt'
///   final chat = LaureliaChat();
///   await chat.download();   // descarga lo que falte
///   await chat.load();       // carga tokenizer + checkpoint
///   final out = await chat.generate('Hola!', maxNewTokens: 100);
class LaureliaChat {
  static const baseUrl = 'https://huggingface.co/ScortexIA/laurelia/resolve/laurelia-llm/';
  static const ckpt = 'checkpoint.pt';
  static const ckptFine = 'fine-checkpoint.pt';
  static const tok = 'tokenizer.json';
  static const dirName = 'hf_models/laurelia';

  /// Modelos disponibles (cada uno vive en su propia carpeta).
  static const List<String> models = ['base', 'fine'];

  /// Modelo seleccionado: 'base' o 'fine'.
  String model = 'base';

  bool _loaded = false;
  int _downloadedBytes = 0;
  String? _status;
  String? _dirPath;

  /// Historial del chat: [{'role': 'user'|'assistant', 'content': '...'}].
  /// Se persiste en appSupport/laurelia/history.json.
  final List<Map<String, String>> history = [];

  String get status => _status ?? '';
  bool get loaded => _loaded;
  int get downloadedBytes => _downloadedBytes;
  String? get dirPath => _dirPath;
  String get modelName => model;

  /// Nombre remoto del checkpoint en HF (fine usa 'fine-checkpoint.pt').
  String get _remoteCkpt => model == 'fine' ? ckptFine : ckpt;

  /// Nombre local del checkpoint (siempre 'checkpoint.pt' en su carpeta).
  String get _localCkpt => ckpt;

  Future<Directory> _dir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$dirName/$model');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dirPath = dir.path;
    return dir;
  }

  Future<String> _path(String name) async =>
      '${(await _dir()).path}/$name';

  /// Qué archivos faltan (para descargar). Vacío si ya están todos.
  Future<List<String>> _missing() async {
    final missing = <String>[];
    for (final f in [_localCkpt, tok]) {
      if (!await File(await _path(f)).exists()) missing.add(f);
    }
    return missing;
  }

  bool _progress(String msg) {
    _status = msg;
    onProgress?.call(msg);
    return true;
  }

  /// Cambia el modelo seleccionado. Si había otro cargado en Rust, lo libera.
  Future<void> setModel(String name) async {
    if (!models.contains(name)) return;
    if (name != model) {
      if (_loaded) await unload();
      model = name;
      _progress('Modelo seleccionado: $name. Descargá o cargá.');
    }
  }

  /// Borra la carpeta del modelo indicado (libera RAM si estaba cargado).
  /// Retorna true si el modelo existía y fue eliminado.
  Future<bool> deleteModel(String name) async {
    if (!models.contains(name)) return false;
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/$dirName/$name');
    if (!dir.existsSync()) {
      _progress('Modelo $name: no existe (nada que borrar).');
      return false;
    }
    if (name == model && _loaded) await unload();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
    _progress('Modelo $name eliminado.');
    return !dir.existsSync();
  }

  /// Id fijo de la notificación de descarga del modelo.
  static const _dlNotifId = 9001;

  /// Descarga por HTTP (streaming a disco) los archivos que falten.
  /// Muestra progreso en vivo (% + MB reales) en pantalla Y en la
  /// notificación del sistema. Reusa lo ya descargado.
  Future<bool> download() async {
    _progress('Descargando…');
    final client = http.Client();
    try {
      var missing = await _missing();
      while (missing.isNotEmpty) {
        final localName = missing.first;
        final remoteName = localName == _localCkpt ? _remoteCkpt : tok;
        final target = File(await _path(localName));
        final req = http.Request('GET', Uri.parse(baseUrl + remoteName));
        final res = await client.send(req);
        if (res.statusCode != 200) {
          _progress('Error HTTP ${res.statusCode} al descargar $remoteName');
          return false;
        }
        final total = res.contentLength ?? 0;
        var written = 0;
        final sink = target.openWrite();

        Future<void> notify({bool finished = false}) {
          return NotificationService.showDownloadProgress(
            id: _dlNotifId,
            title: 'Laurelia · $remoteName',
            body: total > 0
                ? '${_fmt(written)} / ${_fmt(total)}'
                : '${_fmt(written)}…',
            progress: total > 0 ? written / total : null,
            finished: finished,
          );
        }

        await notify();
        try {
          await for (final chunk in res.stream) {
            sink.add(chunk);
            written += chunk.length;
            _downloadedBytes += chunk.length;
            String msg;
            if (total > 0) {
              final pct = (written * 100 / total).toStringAsFixed(0);
              msg = '$remoteName: ${_fmt(written)} / ${_fmt(total)} ($pct%)';
            } else {
              msg = '$remoteName: ${_fmt(written)}…';
            }
            _progress(msg);
            // notificación throttled (~600ms)
            if (written % (512 * 1024) < 64 * 1024) {
              await notify();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        await notify(finished: true);
        missing = await _missing();
      }
      _progress('Modelo descargado. Tocá Cargar.');
      return true;
    } catch (e) {
      _progress('Error al descargar: $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// Estado real en disco: tamaño de cada archivo y si falta alguno.
  Future<Map<String, Object?>> diskInfo() async {
    final dir = await _dir();
    final files = [_localCkpt, tok];
    final info = <String, Object?>{
      'model': model,
      'dir': dir.path,
      'files': <Map<String, Object?>>[],
      'total_bytes': 0,
      'complete': false,
    };
    var total = 0;
    final fileInfos = <Map<String, Object?>>[];
    for (final f in files) {
      final file = File('${dir.path}/$f');
      final size = file.existsSync() ? file.lengthSync() : -1;
      if (size > 0) total += size;
      fileInfos.add({'name': f, 'size': size});
    }
    info['files'] = fileInfos;
    info['total_bytes'] = total;
    info['complete'] = fileInfos.every((f) => (f['size'] as int) > 0);
    return info;
  }

  String _fmt(int bytes) {
    if (bytes < 0) return 'no';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Texto de estado detallado para mostrar en la GUI de Lua.
  Future<String> detailedStatus() async {
    final info = await diskInfo();
    final files = info['files'] as List;
    final parts = <String>[];
    parts.add('Modelo: ${info['model']}');
    parts.add('Dir: ${info['dir']}');
    for (final f in files.cast<Map<String, Object?>>()) {
      parts.add('${f['name']}: ${_fmt((f['size'] as int))}');
    }
    final complete = info['complete'] as bool;
    parts.add('Total: ${_fmt(info['total_bytes'] as int)}');
    parts.add('Descarga: ${complete ? 'completa' : 'INCOMPLETA'}');
    parts.add('Rust: ${_loaded ? 'modelo cargado' : 'no cargado'}');
    return parts.join('\n');
  }

  /// Carga tokenizer + checkpoint en Rust.
  Future<bool> load() async {
    if ((await _missing()).isNotEmpty) {
      _progress('Primero descargá el modelo ($model).');
      return false;
    }
    _progress('Cargando modelo…');
    final ok = await laureliaLoadModel(
      ckptPath: await _path(_localCkpt),
      tokenizerPath: await _path(tok),
    );
    _loaded = ok;
    _progress(ok ? 'Modelo cargado en Rust. Tocá Generar.' : 'Error al cargar. Mirá la consola.');
    return ok;
  }

  /// Cuenta los tokens que representaría un texto (necesita tokenizer).
  Future<int> countTokens(String text) async {
    if (!_loaded && (await _missing()).isNotEmpty) return -1;
    if (!_loaded) await laureliaLoadTokenizer(tokenizerPath: await _path(tok));
    return await laureliaCountTokens(text: text);
  }

  /// Tokens generados en total por esta app (contador global, persiste
  /// entre instancias de pantalla). Se usa en el panel de estado.
  static int generatedTokens = 0;

  /// Genera texto. Los parámetros tienen defaults iguales al ejemplo Godot.
  Future<String> generate(
    String prompt, {
    int maxNewTokens = 50,
    double temperature = 0.7,
    int topK = 40,
    double topP = 0.9,
    double repetitionPenalty = 1.2,
  }) async {
    final out = await laureliaGenerate(
      prompt: prompt,
      maxNewTokens: maxNewTokens,
      temperature: temperature,
      topK: topK,
      topP: topP,
      repetitionPenalty: repetitionPenalty,
    );
    // Estimación de tokens generados (aprox. 1 token por 4 chars).
    generatedTokens += (out.length / 4).round();
    return out;
  }

  Future<bool> isLoaded() async => _loaded && await laureliaIsLoaded();

  Future<String> modelInfo() async => laureliaModelInfo();

  Future<int> vocabSize() async => laureliaVocabSize();

  Future<void> unload() async {
    await laureliaUnloadModel();
    _loaded = false;
    _progress('Modelo liberado.');
  }

  /// Callback de progreso (para actualizar la UI desde Lua).
  void Function(String msg)? onProgress;

  // ---------- Historial persistente ----------

  Future<File> _historyFile() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/laurelia');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/history.json');
  }

  /// Carga el historial guardado en disco (llamar al iniciar la pantalla).
  Future<void> loadHistory() async {
    history.clear();
    try {
      final f = await _historyFile();
      if (!f.existsSync()) return;
      final data = jsonDecode(f.readAsStringSync());
      if (data is List) {
        for (final e in data) {
          if (e is Map &&
              e['role'] is String &&
              e['content'] is String) {
            history.add({
              'role': e['role'] as String,
              'content': e['content'] as String,
            });
          }
        }
      }
    } catch (_) {}
  }

  void addHistory(String role, String content) {
    history.add({'role': role, 'content': content});
    _saveHistory();
  }

  Future<void> _saveHistory() async {
    try {
      final f = await _historyFile();
      f.writeAsStringSync(jsonEncode(history));
    } catch (_) {}
  }

  /// Borra el historial (disco + memoria).
  Future<void> clearHistory() async {
    history.clear();
    try {
      final f = await _historyFile();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    _progress('Historial borrado.');
  }

  /// Serializa los datos de estado para mostrarlos en Lua.
  String stateJson() {
    return jsonEncode({
      'model': model,
      'loaded': _loaded,
      'downloaded_bytes': _downloadedBytes,
      'status': _status,
    });
  }
}
