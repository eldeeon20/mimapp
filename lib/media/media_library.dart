import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../toolsec/toolsec.dart';

/// Biblioteca del reproductor: historial de reproducción + favoritos.
///
/// Persistencia cifrada en ARCHIVO PROPIO (`appSupport/media_library.pr`),
/// esquema fuerte V2 (AES-256-GCM + PBKDF2) vía ToolSec.processBytesStrong.
class MediaLibraryStore {
  static final MediaLibraryStore instance = MediaLibraryStore._();

  MediaLibraryStore._();

  static const int maxHistory = 200;
  static const _fileName = 'media_library.pr';

  final List<Map<String, String>> _history = [];
  final List<Map<String, String>> _favorites = [];
  bool _loaded = false;

  /// Historial más reciente primero (copia inmutable para la UI).
  List<Map<String, String>> get history => List.unmodifiable(_history);

  /// Favoritos en orden de agregado (copia inmutable para la UI).
  List<Map<String, String>> get favorites => List.unmodifiable(_favorites);

  bool isFavorite(String path) =>
      _favorites.any((e) => e['uri'] == path);

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final enc = await file.readAsBytes();
      final plain = await ToolSec('media_library').processBytesAuto(enc);
      if (plain == null) return;
      final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      final h = (map['history'] as List?) ?? const [];
      final f = (map['favorites'] as List?) ?? const [];
      _history
        ..clear()
        ..addAll(h
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry('$k', '$v'))));
      _favorites
        ..clear()
        ..addAll(f
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry('$k', '$v'))));
    } catch (e) {
      print('MediaLibraryStore.load error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final plain = utf8.encode(jsonEncode({
        'history': _history,
        'favorites': _favorites,
      }));
      final enc = await ToolSec('media_library')
          .processBytesStrong(Uint8List.fromList(plain));
      final file = await _file();
      await file.writeAsBytes(enc);
    } catch (e) {
      print('MediaLibraryStore.persist error: $e');
    }
  }

  String _titleOf(String path) =>
      path.split('/').last.split('\\').last.split('?').first;

  /// Registra una reproducción (dedupe por uri, más reciente primero).
  Future<void> addHistory(String path, {String? title}) async {
    if (path.isEmpty) return;
    await load();
    _history.removeWhere((e) => e['uri'] == path);
    _history.insert(0, {
      'uri': path,
      'title': (title == null || title.isEmpty) ? _titleOf(path) : title,
      'ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    while (_history.length > maxHistory) {
      _history.removeLast();
    }
    await _persist();
  }

  /// Agrega/quita de favoritos. Retorna true si quedó como favorito.
  Future<bool> toggleFavorite(String path, {String? title}) async {
    if (path.isEmpty) return false;
    await load();
    final idx = _favorites.indexWhere((e) => e['uri'] == path);
    if (idx >= 0) {
      _favorites.removeAt(idx);
      await _persist();
      return false;
    }
    _favorites.insert(0, {
      'uri': path,
      'title': (title == null || title.isEmpty) ? _titleOf(path) : title,
      'ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    await _persist();
    return true;
  }

  Future<void> removeHistory(String path) async {
    _history.removeWhere((e) => e['uri'] == path);
    await _persist();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _persist();
  }

  Future<void> clearFavorites() async {
    _favorites.clear();
    await _persist();
  }
}
