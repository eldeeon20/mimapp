import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../services/notification_service.dart';

/// Estado de una descarga.
enum DlStatus { activa, ok, error, cancelada }

class DownloadTask {
  final int id;
  final String url;
  final String path;
  int received = 0;
  int total = 0;
  DlStatus status = DlStatus.activa;
  String error = '';
  DownloadTask({required this.id, required this.url, required this.path});

  double get progress => total > 0 ? (received / total).clamp(0, 1) : 0;
  String get mb =>
      '${(received / 1048576).toStringAsFixed(1)}'
      '${total > 0 ? ' / ${(total / 1048576).toStringAsFixed(1)}' : ''} MB';
}

/// Descargas HTTP reales en Dart puro: streaming a disco con progreso
/// por bytes, notificación del sistema con MB reales y cancelación.
///
/// Lua solo engancha con la clase (ver lua_downloads.dart): dl_start,
/// dl_cancel, dl_tasks; el % vivo llega vía engine_set("dl_<id>", "42%").
class DownloadManager with ChangeNotifier {
  DownloadManager._();

  static final DownloadManager instance = DownloadManager._();

  final List<DownloadTask> _tasks = [];
  final Map<int, http.Client> _clients = {};

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// Callback opcional para reportar % vivo a la GUI/Lua:
  /// (taskId, pctString, task)
  void Function(int id, String pct, DownloadTask task)? onProgress;

  String _fileNameFromUrl(String url) {
    final clean = url.split('?').first;
    final last = clean.split('/').where((s) => s.isNotEmpty).last;
    return last.isEmpty ? 'descarga.bin' : last;
  }

  /// Lanza una descarga. Si [askWhere] pide carpeta destino al usuario.
  /// Retorna el id de tarea inmediatamente; el progreso es observable.
  Future<int> start(String url,
      {String? fileName, bool askWhere = false}) async {
    final name = (fileName == null || fileName.trim().isEmpty)
        ? _fileNameFromUrl(url)
        : fileName.trim();

    Directory dir;
    if (askWhere) {
      try {
        final picked = await _pickDirectory();
        dir = Directory(picked ?? await _defaultDir());
      } catch (_) {
        dir = Directory(await _defaultDir());
      }
    } else {
      dir = Directory(await _defaultDir());
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final task = DownloadTask(
      id: NotificationService.nextDownloadId(),
      url: url,
      path: '${dir.path}/$name',
    );
    _tasks.insert(0, task);
    notifyListeners();
    unawaited(_run(task, name));
    return task.id;
  }

  Future<String> _pickDirectory() async {
    try {
      return await FilePicker.platform.getDirectoryPath() ??
          await _defaultDir();
    } catch (_) {
      return _defaultDir();
    }
  }

  Future<String> _defaultDir() async {
    final app = await getApplicationSupportDirectory();
    return '${app.path}/downloads';
  }

  void cancel(int id) {
    _clients[id]?.close();
    final t = _tasks.firstWhere((t) => t.id == id,
        orElse: () => throw StateError('no task'));
    if (t.status == DlStatus.activa) {
      t.status = DlStatus.cancelada;
      NotificationService.cancelDownload(id);
      notifyListeners();
    }
  }

  Future<void> _run(DownloadTask task, String name) async {
    final client = http.Client();
    _clients[task.id] = client;
    IOSink? sink;
    var lastNotify = DateTime.now().subtract(const Duration(seconds: 1));
    try {
      final req = http.Request('GET', Uri.parse(task.url))
        ..followRedirects = true
        ..maxRedirects = 8
        // Sin compresión: si el server manda gzip, el SDK descomprime el
        // stream pero Content-Length queda en tamaño COMPRIMIDO → los MB
        // mostrados no coincidían con lo bajado (y % > 100).
        ..headers['accept-encoding'] = 'identity';
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      // contentLength puede ser -1 (chunked/sin header) → tratar como 0.
      final cl = res.contentLength ?? -1;
      task.total = cl > 0 ? cl : 0;
      sink = File(task.path).openWrite();
      await NotificationService.showDownloadProgress(
        id: task.id,
        title: 'Descargando $name',
        body: '0 / ${task.total > 0 ? _mb(task.total) : '?'}',
        progress: null,
      );

      await for (final chunk in res.stream) {
        if (task.status != DlStatus.activa) break;
        sink.add(chunk);
        task.received += chunk.length;

        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds >= 600) {
          lastNotify = now;
          onProgress?.call(task.id, pct(task), task);
          await NotificationService.showDownloadProgress(
            id: task.id,
            title: 'Descargando $name',
            body: '${_mb(task.received)}'
                '${task.total > 0 ? ' / ${_mb(task.total)}' : ''}',
            progress: task.total > 0 ? task.progress : null,
          );
          notifyListeners();
        }
      }
      await sink.flush();

      if (task.status == DlStatus.activa) {
        // Con total desconocido (0) el fin normal del stream = OK.
        task.status =
            (task.total <= 0 || task.received >= task.total)
                ? DlStatus.ok
                : DlStatus.error;
        task.error = task.status == DlStatus.error
            ? 'incompleta (${task.received}/${task.total})'
            : '';
        onProgress?.call(task.id, pct(task), task);
        await NotificationService.showDownloadProgress(
          id: task.id,
          title: task.status == DlStatus.ok
              ? 'Descarga completa · $name'
              : 'Descarga incompleta · $name',
          body: '${_mb(task.received)} → ${task.path}',
          progress: 1,
          finished: true,
        );
      }
    } catch (e) {
      task.status = DlStatus.error;
      task.error = '$e';
      await sink?.close();
      sink = null;
      await NotificationService.showDownloadProgress(
        id: task.id,
        title: 'Error de descarga · $name',
        body: '$e',
        finished: true,
      );
    } finally {
      await sink?.close();
      _clients.remove(task.id);
      client.close();
      notifyListeners();
    }
  }

  static String pct(DownloadTask t) =>
      t.total > 0 ? '${(t.progress * 100).toStringAsFixed(1)}%' : '${t.received}B';

  static String _mb(int b) => '${(b / 1048576).toStringAsFixed(1)} MB';
}
