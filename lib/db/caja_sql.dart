import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Caja SQL cifrada con ChaCha20 (sqlite3mc vía hook de sqlite3 v3).
///
/// Uso:
/// ```dart
/// final caja = CajaSql();
/// await caja.abrir('contactos', clave: 'secreto');
/// caja.crearTabla('gente', {'nombre': 'TEXT', 'telefono': 'TEXT'});
/// final id = caja.agregar('gente', {'nombre': 'Ana', 'telefono': '123'});
/// final filas = caja.listar('gente', por: 'nombre');
/// final n = caja.contar('gente');
/// caja.quitar('gente', id);
/// await caja.cambiar('notas', clave: 'secreto'); // otra db
/// caja.cerrar();
/// ```
///
/// Todo SQL pasa por acá: tablas, campos, filas y archivos .db.
/// Los identificadores (tabla/campo/orden) se validan con regex; los
/// valores siempre van por `?` (sin concatenar).
class CajaSql {
  Database? _db;
  String? _nombre;
  String? _ruta;

  /// true si hay una db abierta.
  bool get abierta => _db != null;

  /// Nombre de la db abierta (sin .db) o null.
  String? get nombreActual => _nombre;

  /// Ruta del archivo abierto o null.
  String? get rutaActual => _ruta;

  static final _validoId = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  static final _validoNombre = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  static void _exigirId(String que, String v) {
    if (!_validoId.hasMatch(v)) {
      throw ArgumentError('CajaSql: $que inválido "$v" (solo letras, dígitos y _)');
    }
  }

  /// Abre (o crea) la db `<nombre>.db` cifrada con ChaCha20.
  /// Si la clave es incorrecta para una db existente, lanza.
  Future<void> abrir(String nombre, {required String clave}) async {
    if (!_validoNombre.hasMatch(nombre)) {
      throw ArgumentError(
          'CajaSql: nombre de db inválido "$nombre" (solo letras, dígitos, - y _)');
    }
    if (clave.isEmpty) {
      throw ArgumentError('CajaSql: la clave no puede estar vacía');
    }
    cerrar();
    final dir = await getApplicationSupportDirectory();
    final carpeta = Directory('${dir.path}/db');
    await carpeta.create(recursive: true);
    final ruta = '${carpeta.path}/$nombre.db';
    try {
      final db = sqlite3.open(ruta);
      // Orden sqlite3mc: primero el cifrador, después la clave.
      db.execute("PRAGMA cipher = 'chacha20';");
      db.execute("PRAGMA key = '${clave.replaceAll("'", "''")}';");
      // Verificar clave: con clave mala esto lanza.
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
      throw StateError('CajaSql: no abre "$nombre.db" (¿clave mal?): $e');
    }
  }

  /// Cierra la db abierta (olvida todo en memoria; el .db queda en disco).
  void cerrar() {
    try {
      _db?.dispose();
    } catch (_) {}
    _db = null;
    _nombre = null;
    _ruta = null;
  }

  /// Cierra la actual y abre otra (la crea si no existe).
  Future<void> cambiar(String nombre, {required String clave}) =>
      abrir(nombre, clave: clave);

  Database get _base {
    final db = _db;
    if (db == null) throw StateError('CajaSql: no hay db abierta (abrir primero)');
    return db;
  }

  // ---------------------------------------------------------- tablas

  /// Crea la tabla si no existe. [campos] ej: {'nombre': 'TEXT'}.
  /// La `key id` se agrega sola si no viene: `id INTEGER PRIMARY KEY
  /// AUTOINCREMENT` (cada fila queda con id único).
  void crearTabla(String tabla, Map<String, String> campos) {
    _exigirId('tabla', tabla);
    if (campos.isEmpty) {
      throw ArgumentError('CajaSql: crearTabla "$tabla" sin campos');
    }
    final cols = <String>[];
    if (!campos.keys.any((c) => c.toLowerCase() == 'id')) {
      cols.add('"id" INTEGER PRIMARY KEY AUTOINCREMENT');
    }
    campos.forEach((campo, tipo) {
      _exigirId('campo', campo);
      cols.add('"$campo" $tipo');
    });
    try {
      _base.execute('CREATE TABLE IF NOT EXISTS "$tabla" (${cols.join(', ')});');
    } catch (e) {
      throw StateError('CajaSql: no crea tabla "$tabla": $e');
    }
  }

  /// Borra la tabla entera (con sus filas).
  void borrarTabla(String tabla) {
    _exigirId('tabla', tabla);
    try {
      _base.execute('DROP TABLE IF EXISTS "$tabla";');
    } catch (e) {
      throw StateError('CajaSql: no borra tabla "$tabla": $e');
    }
  }

  /// Agrega un campo a una tabla existente.
  void agregarCampo(String tabla, String campo, String tipo) {
    _exigirId('tabla', tabla);
    _exigirId('campo', campo);
    try {
      _base.execute('ALTER TABLE "$tabla" ADD COLUMN "$campo" $tipo;');
    } catch (e) {
      throw StateError('CajaSql: no agrega campo "$campo" a "$tabla": $e');
    }
  }

  /// Quita un campo de una tabla existente (SQLite 3.35+).
  void quitarCampo(String tabla, String campo) {
    _exigirId('tabla', tabla);
    _exigirId('campo', campo);
    try {
      _base.execute('ALTER TABLE "$tabla" DROP COLUMN "$campo";');
    } catch (e) {
      throw StateError('CajaSql: no quita campo "$campo" de "$tabla": $e');
    }
  }

  /// Tablas de la db abierta (sin las internas sqlite_).
  List<String> tablas() {
    final filas = _base.select(
        "SELECT name AS n FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;");
    return [for (final f in filas) '${f['n']}'];
  }

  /// Campos de una tabla (nombres, en orden).
  List<String> campos(String tabla) {
    _exigirId('tabla', tabla);
    final filas = _base.select('PRAGMA table_info("$tabla");');
    return [for (final f in filas) '${f['name']}'];
  }

  // ------------------------------------------------------------ filas

  /// Agrega una fila y devuelve su id.
  int agregar(String tabla, Map<String, Object?> valores) {
    _exigirId('tabla', tabla);
    if (valores.isEmpty) {
      throw ArgumentError('CajaSql: agregar a "$tabla" sin valores');
    }
    for (final c in valores.keys) {
      _exigirId('campo', c);
    }
    final cols = valores.keys.map((c) => '"$c"').join(', ');
    final marcas = List.filled(valores.length, '?').join(', ');
    try {
      _base.execute(
          'INSERT INTO "$tabla" ($cols) VALUES ($marcas);', [...valores.values]);
      return _base.lastInsertRowId;
    } catch (e) {
      throw StateError('CajaSql: no agrega fila en "$tabla": $e');
    }
  }

  /// Agrega una LISTA de filas en una sola transacción (rápido).
  /// Devuelve los ids en orden.
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
      throw StateError('CajaSql: no agrega lote en "$tabla": $e');
    }
  }

  /// Lista filas ordenadas. [por] es campo, [asc] dirección.
  List<Map<String, Object?>> listar(
    String tabla, {
    String por = 'id',
    bool asc = true,
    int? limite,
    int? desde,
  }) {
    _exigirId('tabla', tabla);
    _exigirId('orden', por);
    var sql = 'SELECT * FROM "$tabla" ORDER BY "$por" ${asc ? 'ASC' : 'DESC'}';
    if (limite != null) sql += ' LIMIT ${limite < 0 ? 0 : limite}';
    if (desde != null) sql += ' OFFSET ${desde < 0 ? 0 : desde}';
    sql += ';';
    try {
      final rs = _base.select(sql);
      return [
        for (final f in rs)
          {for (final c in rs.columnNames) c: f[c]}
      ];
    } catch (e) {
      throw StateError('CajaSql: no lista "$tabla": $e');
    }
  }

  /// Primera fila que cumple [donde] (donde='nombre = ?', args=[...]).
  /// null si no hay. Para traer UN dato grande sin listar toda la tabla.
  Map<String, Object?>? uno(
      String tabla, String donde, [List<Object?> args = const []]) {
    _exigirId('tabla', tabla);
    try {
      final rs =
          _base.select('SELECT * FROM "$tabla" WHERE $donde LIMIT 1;', args);
      if (rs.isEmpty) return null;
      final f = rs.first;
      return {for (final c in rs.columnNames) c: f[c]};
    } catch (e) {
      throw StateError('CajaSql: no lee en "$tabla": $e');
    }
  }

  /// Cuenta filas (con filtro opcional: donde='nombre = ?', args=[...]).
  int contar(String tabla, {String? donde, List<Object?> args = const []}) {
    _exigirId('tabla', tabla);
    var sql = 'SELECT COUNT(*) AS n FROM "$tabla"';
    if (donde != null && donde.isNotEmpty) sql += ' WHERE $donde';
    sql += ';';
    try {
      final rs = _base.select(sql, args);
      return (rs.first['n'] as int?) ?? 0;
    } catch (e) {
      throw StateError('CajaSql: no cuenta "$tabla": $e');
    }
  }

  /// Cambia campos de la fila [id].
  int actualizar(String tabla, int id, Map<String, Object?> valores) {
    _exigirId('tabla', tabla);
    if (valores.isEmpty) {
      throw ArgumentError('CajaSql: actualizar "$tabla" sin valores');
    }
    for (final c in valores.keys) {
      _exigirId('campo', c);
    }
    final set = valores.keys.map((c) => '"$c" = ?').join(', ');
    try {
      _base.execute(
          'UPDATE "$tabla" SET $set WHERE "id" = ?;', [...valores.values, id]);
      return _base.getUpdatedRows();
    } catch (e) {
      throw StateError('CajaSql: no actualiza id $id en "$tabla": $e');
    }
  }

  /// Quita la fila con [id]. Devuelve 1 si existía, 0 si no.
  int quitar(String tabla, int id) {
    _exigirId('tabla', tabla);
    try {
      _base.execute('DELETE FROM "$tabla" WHERE "id" = ?;', [id]);
      return _base.getUpdatedRows();
    } catch (e) {
      throw StateError('CajaSql: no quita id $id de "$tabla": $e');
    }
  }

  /// Quita filas por filtro (donde='nombre = ?', args=[...]).
  int quitarDonde(String tabla, String donde, [List<Object?> args = const []]) {
    _exigirId('tabla', tabla);
    try {
      _base.execute('DELETE FROM "$tabla" WHERE $donde;', args);
      return _base.getUpdatedRows();
    } catch (e) {
      throw StateError('CajaSql: no quita filas de "$tabla": $e');
    }
  }

  // -------------------------------------------------------- archivos

  static Future<Directory> _carpeta() async {
    final dir = await getApplicationSupportDirectory();
    final carpeta = Directory('${dir.path}/db');
    await carpeta.create(recursive: true);
    return carpeta;
  }

  /// Nombres de todas las db guardadas (sin .db).
  static Future<List<String>> listarBases() async {
    final carpeta = await _carpeta();
    final out = <String>[];
    await for (final e in carpeta.list()) {
      if (e is File && e.path.endsWith('.db')) {
        out.add(e.uri.pathSegments.last.replaceAll('.db', ''));
      }
    }
    out.sort();
    return out;
  }

  /// Borra el archivo `<nombre>.db` (cierra primero si es la abierta).
  Future<void> borrarBase(String nombre) async {
    if (!_validoNombre.hasMatch(nombre)) {
      throw ArgumentError('CajaSql: nombre de db inválido "$nombre"');
    }
    if (_nombre == nombre) cerrar();
    final carpeta = await _carpeta();
    final f = File('${carpeta.path}/$nombre.db');
    try {
      if (await f.exists()) await f.delete();
    } catch (e) {
      throw StateError('CajaSql: no borra "$nombre.db": $e');
    }
  }
}
