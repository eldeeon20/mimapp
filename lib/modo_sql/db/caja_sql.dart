import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Caja SQL plana (sin cifrado: abre el .db directo).
/// Valores siempre por `?`.
class CajaSql {
  Database? _db;
  String? _nombre;
  String? _ruta;

  bool get abierta => _db != null;

  static final _validoId = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  static final _validoNombre = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  static void _exigirId(String que, String v) {
    if (!_validoId.hasMatch(v)) {
      throw ArgumentError('caja: $que inválido "$v"');
    }
  }

  /// [carpeta]: dir explícita (ej. Download/test_sql); null = soporte.
  Future<void> abrir(String nombre, {String? carpeta}) async {
    if (!_validoNombre.hasMatch(nombre)) {
      throw ArgumentError('caja: nombre inválido "$nombre"');
    }
    cerrar();
    late final String ruta;
    if (carpeta != null) {
      final d = Directory(carpeta);
      await d.create(recursive: true);
      ruta = '${d.path}/$nombre.db';
    } else {
      final dir = await getApplicationSupportDirectory();
      final sup = Directory('${dir.path}/db');
      await sup.create(recursive: true);
      ruta = '${sup.path}/$nombre.db';
    }
    try {
      final db = sqlite3.open(ruta);
      db.select('SELECT count(*) AS n FROM sqlite_master;');
      _db = db;
      _nombre = nombre;
      _ruta = ruta;
    } catch (e) {
      try {
        _db?.dispose();
      } catch (_) {}
      _db = null;
      _nombre = null;
      _ruta = null;
      throw StateError('caja: no abre "$nombre.db": $e');
    }
  }

  void cerrar() {
    try {
      _db?.dispose();
    } catch (_) {}
    _db = null;
    _nombre = null;
    _ruta = null;
  }

  /// Abre una ruta explícita (para rastrear moldes en cualquier carpeta).
  Future<void> abrirRuta(String ruta) async {
    if (!ruta.endsWith('.db')) {
      throw ArgumentError('caja: no es .db "$ruta"');
    }
    cerrar();
    final f = File(ruta);
    if (!await f.exists()) {
      throw StateError('caja: no existe "$ruta"');
    }
    try {
      final db = sqlite3.open(ruta);
      db.select('SELECT count(*) AS n FROM sqlite_master;');
      _db = db;
      _nombre = 'ruta';
      _ruta = ruta;
    } catch (e) {
      try {
        _db?.dispose();
      } catch (_) {}
      _db = null;
      _nombre = null;
      _ruta = null;
      throw StateError('caja: no abre "$ruta": $e');
    }
  }

  Database get _base {
    final db = _db;
    if (db == null) throw StateError('caja: no hay db abierta');
    return db;
  }

  void crearTabla(String tabla, Map<String, String> campos) {
    _exigirId('tabla', tabla);
    if (campos.isEmpty) {
      throw ArgumentError('caja: crearTabla "$tabla" sin campos');
    }
    final cols = <String>[];
    if (!campos.keys.any((c) => c.toLowerCase() == 'id')) {
      cols.add('"id" INTEGER PRIMARY KEY AUTOINCREMENT');
    }
    campos.forEach((campo, tipo) {
      _exigirId('campo', campo);
      cols.add('"$campo" $tipo');
    });
    _base.execute(
        'CREATE TABLE IF NOT EXISTS "$tabla" (${cols.join(', ')});');
  }

  void crearIndice(String tabla, String campo) {
    _exigirId('tabla', tabla);
    _exigirId('campo', campo);
    _base.execute('CREATE INDEX IF NOT EXISTS "idx_${tabla}_${campo}" '
        'ON "$tabla" ("$campo");');
  }

  void agregarCampo(String tabla, String campo, String tipo) {
    _exigirId('tabla', tabla);
    _exigirId('campo', campo);
    _base.execute('ALTER TABLE "$tabla" ADD COLUMN "$campo" $tipo;');
  }

  List<String> campos(String tabla) {
    _exigirId('tabla', tabla);
    final filas = _base.select('PRAGMA table_info("$tabla");');
    return [for (final f in filas) '${f['name']}'];
  }

  int agregar(String tabla, Map<String, Object?> valores) {
    _exigirId('tabla', tabla);
    for (final c in valores.keys) {
      _exigirId('campo', c);
    }
    final cols = valores.keys.map((c) => '"$c"').join(', ');
    final marcas = List.filled(valores.length, '?').join(', ');
    _base.execute(
        'INSERT INTO "$tabla" ($cols) VALUES ($marcas);',
        [...valores.values]);
    return _base.lastInsertRowId;
  }

  List<int> agregarLote(String tabla, List<Map<String, Object?>> filas) {
    if (filas.isEmpty) return [];
    final db = _base;
    final ids = <int>[];
    db.execute('BEGIN;');
    try {
      for (final f in filas) {
        ids.add(agregar(tabla, f));
      }
      db.execute('COMMIT;');
      return ids;
    } catch (e) {
      try {
        db.execute('ROLLBACK;');
      } catch (_) {}
      rethrow;
    }
  }

  List<Map<String, Object?>> listar(String tabla,
      {String por = 'id', bool asc = true}) {
    _exigirId('tabla', tabla);
    _exigirId('orden', por);
    final rs = _base.select(
        'SELECT * FROM "$tabla" ORDER BY "$por" ${asc ? 'ASC' : 'DESC'};');
    return [
      for (final f in rs) {for (final c in rs.columnNames) c: f[c]}
    ];
  }

  List<Map<String, Object?>> listarDonde(
    String tabla,
    String donde,
    List<Object?> args, {
    String por = 'id',
    bool asc = true,
  }) {
    _exigirId('tabla', tabla);
    _exigirId('orden', por);
    final rs = _base.select(
        'SELECT * FROM "$tabla" WHERE $donde ORDER BY "$por" '
        '${asc ? 'ASC' : 'DESC'};',
        args);
    return [
      for (final f in rs) {for (final c in rs.columnNames) c: f[c]}
    ];
  }

  Map<String, Object?>? uno(
      String tabla, String donde, [List<Object?> args = const []]) {
    _exigirId('tabla', tabla);
    final rs =
        _base.select('SELECT * FROM "$tabla" WHERE $donde LIMIT 1;', args);
    if (rs.isEmpty) return null;
    final f = rs.first;
    return {for (final c in rs.columnNames) c: f[c]};
  }

  int actualizar(String tabla, int id, Map<String, Object?> valores) {
    _exigirId('tabla', tabla);
    for (final c in valores.keys) {
      _exigirId('campo', c);
    }
    final set = valores.keys.map((c) => '"$c" = ?').join(', ');
    _base.execute(
        'UPDATE "$tabla" SET $set WHERE "id" = ?;', [...valores.values, id]);
    return _base.getUpdatedRows();
  }

  int quitar(String tabla, int id) {
    _exigirId('tabla', tabla);
    _base.execute('DELETE FROM "$tabla" WHERE "id" = ?;', [id]);
    return _base.getUpdatedRows();
  }

  int quitarDonde(String tabla, String donde,
      [List<Object?> args = const []]) {
    _exigirId('tabla', tabla);
    _base.execute('DELETE FROM "$tabla" WHERE $donde;', args);
    return _base.getUpdatedRows();
  }

  /// SELECT libre (solo lectura, para SUM/ORDER BY/LIMIT).
  List<Map<String, Object?>> crudo(String sql, [List<Object?> args = const []]) {
    final rs = _base.select(sql, args);
    return [
      for (final f in rs) {for (final c in rs.columnNames) c: f[c]}
    ];
  }

  /// Sentencia libre de escritura (CREATE/DELETE con ORDER BY…).
  void corre(String sql, [List<Object?> args = const []]) {
    _base.execute(sql, args);
  }
}
