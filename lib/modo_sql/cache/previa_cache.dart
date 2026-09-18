import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'sesion_cache.dart';

/// Caché de PREVIAS decodificadas (jpeg chicos del .mld, no re-abrir
/// originales). Vive en `cache_previas.db` (sqlite3mc, misma pass).
/// LRU por `ultimo`, libre por defecto (8MB: miles de previas).
class PreviaCache {
  static const tabla = 'cache_previas';

  final SesionCache sesion;
  final String molde;
  int limiteBytes;

  PreviaCache({
    required this.sesion,
    required this.molde,
    this.limiteBytes = 8 * 1024 * 1024,
  });

  static Uint8List _bytes(Object? v) {
    if (v is Uint8List) return v;
    if (v is List) return Uint8List.fromList(v.cast<int>());
    throw StateError('previas: blob inválido');
  }

  /// Previa guardada o null = miss.
  Future<Uint8List?> leer({required String archivo}) async {
    final db = sesion.basePrevias;
    final rs = db.select(
      'SELECT rowid AS id, datos FROM "$tabla" '
      'WHERE molde = ? AND archivo = ?;',
      [molde, archivo],
    );
    if (rs.isEmpty) return null;
    try {
      final ahora = DateTime.now().microsecondsSinceEpoch;
      db.execute(
        'UPDATE "$tabla" SET ultimo = ? WHERE rowid = ?;',
        [ahora, rs.first['id'] as int],
      );
      return _bytes(rs.first['datos']);
    } catch (_) {
      return null;
    }
  }

  /// Guarda una previa y evicta lo más viejo si pasa el límite.
  Future<void> guardar({
    required String archivo,
    required Uint8List previa,
  }) async {
    final db = sesion.basePrevias;
    final ahora = DateTime.now().microsecondsSinceEpoch;
    db.execute(
      'INSERT OR REPLACE INTO "$tabla"'
      '(molde, archivo, tamano, ultimo, datos) '
      'VALUES (?, ?, ?, ?, ?);',
      [molde, archivo, previa.length, ahora, previa],
    );
    await _evictar(db);
  }

  Future<int> _total(Database db) async {
    final rs = db.select(
      'SELECT COALESCE(SUM(tamano), 0) AS t FROM "$tabla" '
      'WHERE molde = ?;',
      [molde],
    );
    return (rs.first['t'] as int?) ?? 0;
  }

  Future<void> _evictar(Database db) async {
    var total = await _total(db);
    while (total > limiteBytes) {
      final vict = db.select(
        'SELECT rowid AS id, tamano FROM "$tabla" WHERE molde = ? '
        'ORDER BY ultimo ASC LIMIT 16;',
        [molde],
      );
      if (vict.isEmpty) break;
      for (final v in vict) {
        db.execute('DELETE FROM "$tabla" WHERE rowid = ?;',
            [v['id'] as int]);
        total -= (v['tamano'] as int?) ?? 0;
      }
    }
  }

  Future<int> bytesEnCache() async => _total(sesion.basePrevias);

  Future<void> limpiarMolde() async {
    sesion.basePrevias.execute(
        'DELETE FROM "$tabla" WHERE molde = ?;', [molde]);
  }

  static Future<void> limpiarTodo(SesionCache sesion) async {
    sesion.basePrevias.execute('DELETE FROM "$tabla";');
  }

  static Future<int> bytesTotales(SesionCache sesion) async {
    final rs = sesion.basePrevias.select(
      'SELECT COALESCE(SUM(tamano), 0) AS t FROM "$tabla";',
    );
    return (rs.first['t'] as int?) ?? 0;
  }
}
