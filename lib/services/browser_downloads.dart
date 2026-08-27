import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Item de descarga del browser (o de quien llame al gestor).
class DownloadItem {
  DownloadItem({
    required this.url,
    required this.fileName,
    required this.path,
    this.total,
  });

  final String url;
  final String fileName;
  final String path;
  int? total;
  int received = 0;
  String status = 'en curso'; // en curso | ok | error: <motivo>

  double? get progress =>
      (total != null && total! > 0) ? received / total! : null;
}

/// Gestor de descargas global del browser: streaming a archivo bajo
/// <appSupport>/browser_downloads con progreso por item.
///
/// Hoy sale directo; la clase Proxy queda pendiente — cuando exista, acá
/// se enchufa el túnel (Tor) sin cambiar a los que llaman.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final List<DownloadItem> items = [];
  bool _busy = false;

  List<DownloadItem> get itemsUnmodifiable => List.unmodifiable(items);
  bool get busy => _busy;

  Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final d = Directory('${support.path}/browser_downloads');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  String _fileName(String url, String? suggested) {
    var n = (suggested ?? '').trim();
    if (n.isEmpty) {
      n = url.split('/').last.split('?').first;
    }
    if (n.isEmpty || n == '/') n = 'descarga';
    n = n.replaceAll(RegExp(r'[^\w.\-() ]'), '_');
    return '${DateTime.now().millisecondsSinceEpoch}_$n';
  }

  /// Descarga [url] en segundo plano y notifica progreso por item.
  Future<void> start(String url, {String? suggestedName}) async {
    final dir = await _dir();
    final name = _fileName(url, suggestedName);
    final path = '${dir.path}/$name';
    final item = DownloadItem(url: url, fileName: name, path: path);
    items.insert(0, item);
    notifyListeners();

    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw 'HTTP ${res.statusCode}';
      }
      item.total = res.contentLength;
      final sink = File(path).openWrite();
      await for (final chunk in res) {
        item.received += chunk.length;
        sink.add(chunk);
        notifyListeners();
      }
      await sink.flush();
      await sink.close();
      item.status = 'ok';
    } catch (e) {
      item.status = 'error: $e';
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    } finally {
      client.close();
      notifyListeners();
    }
    _busy = items.any((i) => i.status == 'en curso');
  }

  /// Limpia la lista (no borra archivos ya guardados).
  void clearList() {
    items.clear();
    notifyListeners();
  }
}
