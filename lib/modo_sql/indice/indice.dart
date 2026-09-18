import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../media_server/media_server.dart';

/// ÍNDICE en SQL de verdad (`indice.db` en Download) con SU PROPIA
/// CLAVE: en reposo el archivo va cifrado entero
/// (sal+nonce+AES-256-GCM); se descifra a un temporal privado solo
/// para operar y se vuelve a cifrar. Clave mala = no autentica.
///
/// Liviana: por molde solo QUÉ sql + SU pass + dónde está el .mld.
class Indice {
  static const archivo = 'indice.db';
  static const _viejoDb = 'catalogo.db';
  static const _viejoMlc = 'catalogo.mlc';

  static Future<File> _file() async {
    final carpeta = await MediaBase.carpetaMoldes();
    return File('${carpeta.path}/$archivo');
  }

  /// Si existe la vieja `catalogo.db` y la nueva no, se adopta
  /// (se lee de ahí; el primer guardado ya escribe `indice.db`).
  static Future<File> _origen() async {
    final nuevo = await _file();
    if (await nuevo.exists()) return nuevo;
    final carpeta = await MediaBase.carpetaMoldes();
    final viejo = File('${carpeta.path}/$_viejoDb');
    if (await viejo.exists()) return viejo;
    return nuevo;
  }

  static Future<File> _tmp() async {
    final t = await getTemporaryDirectory();
    return File('${t.path}/catalogo_tmp.db');
  }

  static String _salHex(Uint8List sal) {
    return sal.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<Uint8List> _clave(String pass, String salHex) {
    return Duro.claveArchivoHilo(
      clave: pass,
      molde: 'catalogo',
      nombre: 'indice',
      salHex: salHex,
    );
  }

  static void _tabla(Database db) {
    db.execute('CREATE TABLE IF NOT EXISTS indice('
        'nombre TEXT PRIMARY KEY, sql TEXT, pass TEXT, mld TEXT, '
        'n INTEGER, total INTEGER, fecha INTEGER, sal TEXT, '
        'hf_repo TEXT, hf_token TEXT, version INTEGER);');
    // Migración: índices viejos sin columnas HF.
    final cols = {
      for (final r in db.select('PRAGMA table_info(indice);'))
        '${r['name']}': true
    };
    if (!cols.containsKey('hf_repo')) {
      db.execute('ALTER TABLE indice ADD COLUMN hf_repo TEXT;');
    }
    if (!cols.containsKey('hf_token')) {
      db.execute('ALTER TABLE indice ADD COLUMN hf_token TEXT;');
    }
    if (!cols.containsKey('version')) {
      db.execute('ALTER TABLE indice ADD COLUMN version INTEGER;');
    }
  }

  /// Descifra el índice a un temporal privado (lo crea vacío si no hay).
  static Future<File> _materializar(String pass) async {
    if (pass.isEmpty) {
      throw ArgumentError('índice: poné su propia clave');
    }
    final f = await _origen();
    final tmp = await _tmp();
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    if (!await f.exists()) {
      final db = sqlite3.open(tmp.path);
      try {
        _tabla(db);
      } finally {
        db.dispose();
      }
      return tmp;
    }
    final raw = await f.readAsBytes();
    if (raw.length < 16 + 12 + 16) {
      throw StateError('índice: archivo corrupto o truncado');
    }
    final sal = raw.sublist(0, 16);
    final nonce = raw.sublist(16, 28);
    final resto = raw.sublist(28);
    final key = await _clave(pass, _salHex(sal));
    try {
      final mac = Mac(resto.sublist(resto.length - 16));
      final cipher = resto.sublist(12, resto.length - 16);
      final claro = await AesGcm.with256bits().decrypt(
        SecretBox(cipher, nonce: nonce, mac: mac),
        secretKey: SecretKey(key),
      );
      await tmp.writeAsBytes(claro, flush: true);
      return tmp;
    } catch (_) {
      throw StateError('índice: clave mal (no autentica)');
    }
  }

  /// Cifra el temporal de vuelta al archivo y lo borra.
  static Future<void> _persistir(String pass, File tmp) async {
    final claros = await tmp.readAsBytes();
    final r = Random.secure();
    final sal = Uint8List.fromList(
        List<int>.generate(16, (_) => r.nextInt(256)));
    final nonce = Uint8List.fromList(
        List<int>.generate(12, (_) => r.nextInt(256)));
    final key = await _clave(pass, _salHex(sal));
    final box = await AesGcm.with256bits().encrypt(
      claros,
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    final f = await _file();
    await f.writeAsBytes(
        [...sal, ...nonce, ...box.concatenation()],
        flush: true);
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    // Migrado a `indice.db`: la vieja ya no se usa.
    try {
      final carpeta = await MediaBase.carpetaMoldes();
      final viejo = File('${carpeta.path}/$_viejoDb');
      if (await viejo.exists() && viejo.path != f.path) {
        await viejo.delete();
      }
    } catch (_) {}
  }

  /// Asegura que el índice propio existe (vacío cifrado si es nuevo).
  /// Borra el `.mlc` viejo si quedó (la `catalogo.db` vieja se adopta,
  /// no se borra: el primer guardado ya escribe `indice.db`).
  static Future<void> asegurar(String pass) async {
    if (pass.isEmpty) return;
    try {
      final carpeta = await MediaBase.carpetaMoldes();
      final mlc = File('${carpeta.path}/$_viejoMlc');
      if (await mlc.exists()) await mlc.delete();
    } catch (_) {}
    final f = await _file();
    if (!await f.exists()) {
      final tmp = await _materializar(pass);
      await _persistir(pass, tmp);
    }
  }

  /// Índice liviano: solo QUÉ sql + SU pass (+ .mld y números).
  static Future<List<Map<String, Object?>>> listarRaw(
      String pass) async {
    final tmp = await _materializar(pass);
    try {
      final db = sqlite3.open(tmp.path);
      try {
        _tabla(db);
        final rs =
            db.select('SELECT * FROM indice ORDER BY nombre;');
        return [
          for (final r in rs)
            {
              'nombre': '${r['nombre'] ?? ''}',
              'db': '${r['sql'] ?? ''}',
              'db_ruta': '${r['sql'] ?? ''}',
              'pass': '${r['pass'] ?? ''}',
              'mld_ruta': '${r['mld'] ?? ''}',
              'n': (r['n'] as int?) ?? 0,
              'total': (r['total'] as int?) ?? 0,
              'fecha': (r['fecha'] as int?) ?? 0,
              'sal': '${r['sal'] ?? ''}',
              'cifrado': 'gcm-c',
              // HF: dónde vive remoto (repo_id = dir/user), con qué
              // token entrar y qué versión se subió por última vez.
              'hf_repo': '${r['hf_repo'] ?? ''}',
              'hf_token': '${r['hf_token'] ?? ''}',
              'version': (r['version'] as int?) ?? 0,
            }
        ];
      } finally {
        db.dispose();
      }
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Una entrada del índice (relación: qué sql + su pass + rutas).
  static Future<Map<String, Object?>?> entrada({
    required String pass,
    required String nombre,
  }) async {
    final lista = await listarRaw(pass);
    for (final m in lista) {
      if ('${m['nombre']}' == nombre) return m;
    }
    return null;
  }

  /// Historial rápido (MoldeInfo listos para abrir).
  static Future<List<MoldeInfo>> listar(String pass) async {
    final lista = await listarRaw(pass);
    return [
      for (final m in lista)
        MoldeInfo(
          nombre: '${m['nombre'] ?? ''}',
          ruta: '${m['mld_ruta'] ?? ''}',
          fecha: (m['fecha'] as int?) ?? 0,
          total: (m['total'] as int?) ?? 0,
          sal: '${m['sal'] ?? ''}',
          cifrado: '${m['cifrado'] ?? ''}',
        )
    ];
  }

  static Future<void> registrar({
    required String pass,
    required String nombre,
    required String dbRuta,
    required String mldRuta,
    required int n,
    required int total,
    required String sal,
    String passMolde = '',
    String hfRepo = '',
    String hfToken = '',
    int version = 0,
  }) async {
    final tmp = await _materializar(pass);
    final db = sqlite3.open(tmp.path);
    try {
      _tabla(db);
      // Preserva HF si esta llamada no trae (registros viejos).
      var repo = hfRepo;
      var tok = hfToken;
      var ver = version;
      try {
        final prev = db.select(
            'SELECT hf_repo, hf_token, version FROM indice WHERE nombre = ?;',
            [nombre]);
        if (prev.isNotEmpty && hfRepo.isEmpty && hfToken.isEmpty) {
          repo = '${prev.first['hf_repo'] ?? ''}';
          tok = '${prev.first['hf_token'] ?? ''}';
          ver = (prev.first['version'] as int?) ?? 0;
        }
      } catch (_) {}
      db.execute(
        'INSERT OR REPLACE INTO indice'
        '(nombre, sql, pass, mld, n, total, fecha, sal, '
        'hf_repo, hf_token, version) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
        [
          nombre,
          dbRuta,
          passMolde,
          mldRuta,
          n,
          total,
          DateTime.now().millisecondsSinceEpoch,
          sal,
          repo,
          tok,
          ver,
        ],
      );
    } finally {
      db.dispose();
    }
    await _persistir(pass, tmp);
  }

  /// Guarda/actualiza los datos HF de un molde (dir/user = repo_id,
  /// pass del molde y token de acceso). No toca lo demás.
  static Future<void> guardarHf({
    required String pass,
    required String nombre,
    required String hfRepo,
    required String hfToken,
  }) async {
    final ent = await entrada(pass: pass, nombre: nombre);
    if (ent == null) {
      throw StateError('índice: "$nombre" no existe');
    }
    await registrar(
      pass: pass,
      nombre: nombre,
      dbRuta: '${ent['db_ruta'] ?? ''}',
      mldRuta: '${ent['mld_ruta'] ?? ''}',
      n: (ent['n'] as int?) ?? 0,
      total: (ent['total'] as int?) ?? 0,
      sal: '${ent['sal'] ?? ''}',
      passMolde: '${ent['pass'] ?? ''}',
      hfRepo: hfRepo,
      hfToken: hfToken,
      version: (ent['version'] as int?) ?? 0,
    );
  }

  /// Marca la versión remota recién subida de un molde.
  static Future<void> marcarVersion({
    required String pass,
    required String nombre,
    required int version,
  }) async {
    final ent = await entrada(pass: pass, nombre: nombre);
    if (ent == null) return;
    await registrar(
      pass: pass,
      nombre: nombre,
      dbRuta: '${ent['db_ruta'] ?? ''}',
      mldRuta: '${ent['mld_ruta'] ?? ''}',
      n: (ent['n'] as int?) ?? 0,
      total: (ent['total'] as int?) ?? 0,
      sal: '${ent['sal'] ?? ''}',
      passMolde: '${ent['pass'] ?? ''}',
      hfRepo: '${ent['hf_repo'] ?? ''}',
      hfToken: '${ent['hf_token'] ?? ''}',
      version: version,
    );
  }

  /// Edita a mano las rutas de una entrada (por si el archivo está
  /// en un lugar no físico: URL, IP, etc.). No valida nada: si la
  /// ruta no abre, el error sale al abrir el molde.
  static Future<void> actualizarRutas({
    required String pass,
    required String nombre,
    required String dbRuta,
    required String mldRuta,
  }) async {
    final ent = await entrada(pass: pass, nombre: nombre);
    if (ent == null) {
      throw StateError('índice: "$nombre" no existe');
    }
    await registrar(
      pass: pass,
      nombre: nombre,
      dbRuta: dbRuta.isEmpty ? '${ent['db_ruta'] ?? ''}' : dbRuta,
      mldRuta:
          mldRuta.isEmpty ? '${ent['mld_ruta'] ?? ''}' : mldRuta,
      n: (ent['n'] as int?) ?? 0,
      total: (ent['total'] as int?) ?? 0,
      sal: '${ent['sal'] ?? ''}',
      passMolde: '${ent['pass'] ?? ''}',
      hfRepo: '${ent['hf_repo'] ?? ''}',
      hfToken: '${ent['hf_token'] ?? ''}',
      version: (ent['version'] as int?) ?? 0,
    );
  }

  static Future<void> quitar({
    required String pass,
    required String nombre,
  }) async {
    final tmp = await _materializar(pass);
    final db = sqlite3.open(tmp.path);
    try {
      _tabla(db);
      db.execute(
          'DELETE FROM indice WHERE nombre = ?;', [nombre]);
    } finally {
      db.dispose();
    }
    await _persistir(pass, tmp);
  }
}
