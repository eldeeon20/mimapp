import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../src/rust/api/needle.dart' as rust;

/// Needle v2 on-device: descarga del .cact (13.7 MB), carga del motor
/// y tool-calling local (query + tools JSON → llamada JSON).
class NeedleOut {
  final String text;
  final String? toolCall;
  final String? thinking;
  final String stop;
  final int promptTokens;
  NeedleOut({
    required this.text,
    required this.toolCall,
    required this.thinking,
    required this.stop,
    required this.promptTokens,
  });

  static NeedleOut _fromRust(rust.NeedleOut o) => NeedleOut(
        text: o.text,
        toolCall: o.toolCall,
        thinking: o.thinking,
        stop: o.stop,
        promptTokens: o.promptTokens,
      );
}

class NeedleService extends ChangeNotifier {
  NeedleService._();
  static final NeedleService instance = NeedleService._();

  static const modelUrl =
      'https://huggingface.co/Cactus-Compute/needle2/resolve/main/needle2.cact';
  static const modelBytes = 13.7 * 1024 * 1024;
  // v1: encoder-decoder 26M, safetensors + vocabulario separado
  static const modelUrlV1 =
      'https://huggingface.co/Abdalrahman/needle-rs-safetensors/resolve/main/needle.safetensors';
  static const vocabUrlV1 =
      'https://huggingface.co/Abdalrahman/needle-rs-safetensors/resolve/main/vocab.txt';
  static const modelBytesV1 = 22 * 1024 * 1024;

  String? _modelPath;
  String? _weightsV1;
  String? _vocabV1;
  bool _busy = false;
  bool _loadedV2 = false;
  bool _loadedV1Flag = false;
  double _progress = 0;

  bool get busy => _busy;
  double get progress => _progress;
  bool get downloaded => _modelPath != null;
  bool get downloadedV1 => _weightsV1 != null && _vocabV1 != null;

  /// El motor Rust arranca sin modelo tras cada reinicio de la app,
  /// así que el estado real vive acá y se actualiza con load/unload.
  bool get loaded => _loadedV2;
  bool get loadedV1 => _loadedV1Flag;
  String? get modelPath => _modelPath;

  Future<String> get dirPath async {
    final d = await getApplicationSupportDirectory();
    final dir = Directory('${d.path}/needle');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<void> refresh() async {
    final dir = await dirPath;
    final f = File('$dir/needle2.cact');
    _modelPath = f.existsSync() ? f.path : null;
    final w = File('$dir/needle.safetensors');
    final v = File('$dir/vocab.txt');
    _weightsV1 = w.existsSync() ? w.path : null;
    _vocabV1 = v.existsSync() ? v.path : null;
    notifyListeners();
  }

  /// Baja un archivo remoto a [dest] reportando progreso (0..1).
  Future<void> _fetch(String url, String dest, int approxBytes) async {
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode} en $url';
      final total = res.contentLength ?? approxBytes;
      final sink = File(dest).openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        got += chunk.length;
        sink.add(chunk);
        _progress = total > 0 ? got / total : 0;
        notifyListeners();
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// Descarga el .cact de v2 desde HuggingFace.
  Future<String> downloadModel() async {
    if (_busy) throw 'ya hay una descarga en curso';
    _busy = true;
    _progress = 0;
    notifyListeners();
    try {
      final dir = await dirPath;
      final tmp = '$dir/needle2.cact.tmp';
      await _fetch(modelUrl, tmp, modelBytes.toInt());
      final finalPath = '$dir/needle2.cact';
      File(tmp).renameSync(finalPath);
      _modelPath = finalPath;
      return finalPath;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Descarga safetensors + vocab de v1 (dos archivos).
  Future<String> downloadModelV1() async {
    if (_busy) throw 'ya hay una descarga en curso';
    _busy = true;
    _progress = 0;
    notifyListeners();
    try {
      final dir = await dirPath;
      await _fetch(modelUrlV1, '$dir/needle.safetensors', modelBytesV1.toInt());
      await _fetch(vocabUrlV1, '$dir/vocab.txt', 122 * 1024);
      _weightsV1 = '$dir/needle.safetensors';
      _vocabV1 = '$dir/vocab.txt';
      return _weightsV1!;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Carga el modelo ya descargado en el motor Rust.
  Future<String> load() async {
    await refresh();
    final p = _modelPath;
    if (p == null) throw 'primero descargá el modelo (13.7 MB)';
    final r = await rust.needleLoad(path: p);
    _loadedV2 = true;
    notifyListeners();
    return r;
  }

  /// Carga v1 (safetensors + vocab).
  Future<String> loadV1() async {
    await refresh();
    if (_weightsV1 == null || _vocabV1 == null) {
      throw 'primero descargá el modelo v1 (22 MB + vocab)';
    }
    final r = await rust.needleLoadV1(
        weightsPath: _weightsV1!, vocabPath: _vocabV1!);
    _loadedV1Flag = true;
    notifyListeners();
    return r;
  }

  Future<NeedleOut> run({
    required String query,
    required String toolsJson,
    bool constrain = true,
    int maxNewTokens = 128,
    double temperature = 0.0,
    int seed = 0,
  }) async {
    final r = await rust.needleRun(
      query: query,
      toolsJson: toolsJson,
      constrain: constrain,
      maxNewTokens: maxNewTokens,
      temperature: temperature,
      seed: BigInt.from(seed),
    );
    return NeedleOut._fromRust(r);
  }

  /// Confianza del head propio para la última respuesta.
  Future<double> confidence({
    required String query,
    required String toolsJson,
    required String completion,
  }) =>
      rust.needleConfidence(
          query: query, toolsJson: toolsJson, completion: completion);

  /// Corre el motor v1: greedy, siempre restringido; devuelve el JSON.
  Future<NeedleOut> runV1({
    required String query,
    required String toolsJson,
  }) async {
    final r = await rust.needleRunV1(query: query, toolsJson: toolsJson);
    return NeedleOut._fromRust(r);
  }

  void unload() {
    rust.needleUnload();
    _loadedV2 = false;
    notifyListeners();
  }

  void unloadV1() {
    rust.needleUnloadV1();
    _loadedV1Flag = false;
    notifyListeners();
  }

  /// Pretty-print defensivo del payload JSON de la tool call.
  static String pretty(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }
}
