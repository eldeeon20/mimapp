import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../toolsec/toolsec.dart';

/// Historial de páginas/búsquedas Lua en ARCHIVO PROPIO cifrado
/// (`appSupport/lua_history.pr`), separado del config.pr global.
///
/// Usa el esquema fuerte V2 (AES-256-GCM + PBKDF2, salt por archivo) vía
/// ToolSec.processBytesStrong — no XOR.
class HistoryStore {
  static final HistoryStore instance = HistoryStore._();

  HistoryStore._();

  static const int maxEntries = 200;
  static const _fileName = 'lua_history.pr';

  final List<Map<String, String>> _entries = [];
  bool _loaded = false;

  /// Copia inmutable para la UI (más recientes primero).
  List<Map<String, String>> get entries =>
      List.unmodifiable(_entries);

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
      // Siempre V2; un legado aquí no debería existir, pero por si acaso.
      final plain = await ToolSec('lua_history').processBytesAuto(enc);
      if (plain == null) return;
      final list = jsonDecode(utf8.decode(plain)) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(list
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry('$k', '$v'))));
    } catch (e) {
      print('HistoryStore.load error: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final plain = utf8.encode(jsonEncode(_entries));
      final enc = await ToolSec('lua_history')
          .processBytesStrong(Uint8List.fromList(plain));
      final file = await _file();
      await file.writeAsBytes(enc);
    } catch (e) {
      print('HistoryStore.persist error: $e');
    }
  }

  /// Agrega/actualiza una entrada (dedupe por uri, más reciente primero).
  Future<void> add(String uri, {String? title}) async {
    if (uri.isEmpty) return;
    _entries.removeWhere((e) => e['uri'] == uri);
    _entries.insert(0, {
      'uri': uri,
      'title': title ?? uri,
      'ts': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    await _persist();
  }

  Future<void> remove(String uri) async {
    _entries.removeWhere((e) => e['uri'] == uri);
    await _persist();
  }

  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }
}
