import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// KV único de la app (`app.db`, tabla `kv`): reemplaza los .pr
/// privados y los json sueltos (config.pr, ajustes_modo.json,
/// filosoia_*.pr, media_library.pr). Cada dueño cifra su valor como
/// quiera; acá solo se guardan bytes por clave.
///
/// Las agendas NO van acá: tienen su base propia en Download con su
/// pass (orden explícita: dejarlas quietas).
abstract final class AppDb {
  static Future<Database> _abrir() async {
    final dir = await getApplicationSupportDirectory();
    final db = sqlite3.open('${dir.path}/app.db');
    db.execute(
        'CREATE TABLE IF NOT EXISTS kv(clave TEXT PRIMARY KEY, datos BLOB);');
    return db;
  }

  static Uint8List? _bytes(Object? v) {
    if (v is Uint8List) return v;
    if (v is List) return Uint8List.fromList(v.cast<int>());
    return null;
  }

  /// Bytes guardados o null (no hay clave).
  static Future<Uint8List?> leer(String clave) async {
    final db = await _abrir();
    try {
      final r =
          db.select('SELECT datos FROM kv WHERE clave = ?;', [clave]);
      if (r.isEmpty) return null;
      return _bytes(r.first['datos']);
    } finally {
      db.dispose();
    }
  }

  /// Guarda (o pisa) los bytes de una clave.
  static Future<void> guardar(String clave, Uint8List datos) async {
    final db = await _abrir();
    try {
      db.execute(
          'INSERT OR REPLACE INTO kv(clave, datos) VALUES (?, ?);',
          [clave, datos]);
    } finally {
      db.dispose();
    }
  }

  /// Borra una clave (si no existe, nada).
  static Future<void> borrar(String clave) async {
    try {
      final db = await _abrir();
      try {
        db.execute('DELETE FROM kv WHERE clave = ?;', [clave]);
      } finally {
        db.dispose();
      }
    } catch (_) {}
  }

  /// Borra un archivo viejo de appSupport (los .pr no importan: no se
  /// migran, se tachan; app.db manda con defaults). No falla si no hay.
  static Future<void> tachar(String nombre) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$nombre');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
