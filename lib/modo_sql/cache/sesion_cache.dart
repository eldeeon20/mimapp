import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../media_server/media_server.dart';

/// Sesión de la caché: `media_cache.db` cifrada en reposo con la MISMA
/// pass del índice (comparten pass, se pide al iniciar, no se guarda).
///
/// Se descifra a un temporal privado al desbloquear, queda abierta en
/// sesión y se cifra de vuelta tras cada escritura (+ al cerrar).
class SesionCache {
  static const archivo = 'media_cache.db';

  Database? _db;
  File? _tmp;
  String _pass = '';

  bool get abierta => _db != null;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$archivo');
  }

  static Future<File> _tmpNuevo() async {
    final t = await getTemporaryDirectory();
    return File('${t.path}/cache_tmp.db');
  }

  static String _salHex(Uint8List sal) {
    return sal.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<Uint8List> _clave(String pass, String salHex) {
    return Duro.claveArchivoHilo(
      clave: pass,
      molde: 'cache',
      nombre: 'sesion',
      salHex: salHex,
    );
  }

  /// Desbloquea con la pass del índice (la pide la app al iniciar).
  Future<void> abrir(String pass) async {
    if (pass.isEmpty) {
      throw ArgumentError('caché: sin pass del índice');
    }
    await cerrar();
    final f = await _file();
    final tmp = await _tmpNuevo();
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    if (!await f.exists()) {
      final db = sqlite3.open(tmp.path);
      db.execute('CREATE TABLE cache_trozos('
          'molde TEXT, archivo TEXT, indice INTEGER, tamano INTEGER, '
          'ultimo INTEGER, datos BLOB, '
          'PRIMARY KEY(molde, archivo, indice));');
      db.dispose();
    } else {
      final raw = await f.readAsBytes();
      if (raw.length < 16 + 12 + 16) {
        throw StateError('caché: archivo corrupto');
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
      } catch (_) {
        throw StateError('caché: clave mal (no autentica)');
      }
    }
    _db = sqlite3.open(tmp.path);
    _tmp = tmp;
    _pass = pass;
  }

  /// Cifra de vuelta al archivo (tras cada lote + al cerrar).
  /// El AES corre en HILO (el archivo llega a 512KB+ y en el UI
  /// trancaba el scroll en cada trozo).
  Future<void> persistir() async {
    final db = _db;
    final tmp = _tmp;
    if (db == null || tmp == null || _pass.isEmpty) return;
    final claros = await tmp.readAsBytes();
    final r = Random.secure();
    final sal = Uint8List.fromList(
        List<int>.generate(16, (_) => r.nextInt(256)));
    final nonce = Uint8List.fromList(
        List<int>.generate(12, (_) => r.nextInt(256)));
    final key = await _clave(_pass, _salHex(sal));
    final concat = await Isolate.run(() => _cifrarCache({
          'clave': key,
          'nonce': nonce,
          'datos': claros,
        }));
    final f = await _file();
    await f.writeAsBytes(
        [...sal, ...nonce, ...concat],
        flush: true);
  }

  Database get base {
    final db = _db;
    if (db == null) {
      throw StateError('caché: bloqueada (abrí el índice primero)');
    }
    return db;
  }

  Future<void> cerrar() async {
    try {
      await persistir();
    } catch (_) {}
    try {
      _db?.dispose();
    } catch (_) {}
    _db = null;
    try {
      if (_tmp != null && await _tmp!.exists()) {
        await _tmp!.delete();
      }
    } catch (_) {}
    _tmp = null;
    _pass = '';
  }
}

/// Corre en el hilo aparte: cifra el archivo de caché ahí.
/// OJO: va a NIVEL ARCHIVO (fuera de la clase): como método
/// capturaría `this` (la DB no viaja entre hilos) y reventaba
/// cada guardado (ese era todo el rojo).
Future<Uint8List> _cifrarCache(Map<String, Object?> m) async {
  final box = await AesGcm.with256bits().encrypt(
    m['datos'] as Uint8List,
    secretKey: SecretKey(m['clave'] as Uint8List),
    nonce: m['nonce'] as Uint8List,
  );
  return Uint8List.fromList(box.concatenation());
}
