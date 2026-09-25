import 'dart:convert';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../services/crypto_vault.dart';
import '../services/settings.dart';

/// Cuenta de Colab en SQL (`app.db`), cifrada con la pass global ("1234").
///
/// Una sola fila: el JSON con llaves + acceso, en un envelope PRBX. Cada
/// escritura se VERIFICA releyendo: si lo releído no coincide, tira
/// excepción en voz alta (nunca se pierde en silencio). Así, si cerrás la
/// app, lo nuevo está en disco seguro.
abstract final class CuentasColab {
  static const _id = 'default';

  static Future<Database> _abrir() async {
    final dir = await getApplicationSupportDirectory();
    final db = sqlite3.open('${dir.path}/app.db');
    db.execute('CREATE TABLE IF NOT EXISTS cuenta_colab('
        'id TEXT PRIMARY KEY, datos BLOB);');
    return db;
  }

  static Uint8List _bytes(Object? v) {
    if (v is Uint8List) return v;
    if (v is List) return Uint8List.fromList(v.cast<int>());
    throw StateError('cuenta_colab: blob inválido');
  }

  static String _pass() => Settings.instance.masterKey;

  /// Lee el acceso guardado. null = no hay fila. Tira si la fila existe
  /// pero no descifra (corrupto: mejor saberlo que seguir con llaves
  /// viejas en memoria).
  static Future<Map<String, dynamic>?> leer() async {
    final db = await _abrir();
    try {
      final r =
          db.select('SELECT datos FROM cuenta_colab WHERE id = ?;', [_id]);
      if (r.isEmpty) return null;
      final claro = await CryptoVault.decrypt(_bytes(r.first['datos']), _pass());
      if (claro == null) {
        throw StateError('cuenta_colab: no descifra con la pass global');
      }
      return jsonDecode(utf8.decode(claro)) as Map<String, dynamic>;
    } finally {
      db.dispose();
    }
  }

  /// Escribe el mapa completo y lo verifica releyendo. Si no coincide, tira.
  static Future<void> _escribir(Map<String, dynamic> nuevo) async {
    final env = await CryptoVault.encrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(nuevo))), _pass());
    final db = await _abrir();
    try {
      db.execute(
          'INSERT OR REPLACE INTO cuenta_colab(id, datos) VALUES (?, ?);',
          [_id, env]);
    } finally {
      db.dispose();
    }
    // Verificación: lo que quedó en disco tiene que ser lo que se quiso
    // guardar. Si cerrás la app acá, lo nuevo está.
    final check = await leer();
    if (check == null ||
        '${check['access'] ?? ''}' != '${nuevo['access'] ?? ''}' ||
        '${check['refresh'] ?? ''}' != '${nuevo['refresh'] ?? ''}') {
      throw StateError('cuenta_colab: la escritura no quedó en disco');
    }
  }

  /// Guarda las llaves (client_id + client_secret), conservando el acceso.
  static Future<void> guardarLlaves(String clientId, String clientSecret) async {
    final viejo = await leer() ?? <String, dynamic>{};
    final nuevo = Map<String, dynamic>.from(viejo)
      ..['client_id'] = clientId
      ..['client_secret'] = clientSecret;
    await _escribir(nuevo);
  }

  /// Guarda el acceso (tokens). Se llama ENSEGUIDA después de cada login y
  /// de cada refresh, antes de usar el token para nada más. Conserva llaves.
  static Future<void> guardarTokens({
    required String access,
    required String refresh,
    required String expiry,
  }) async {
    final viejo = await leer() ?? <String, dynamic>{};
    final nuevo = Map<String, dynamic>.from(viejo)
      ..['access'] = access
      ..['refresh'] = refresh
      ..['expiry'] = expiry;
    await _escribir(nuevo);
  }

  /// Compat: guarda lo que se le pase (llaves y/o acceso), conservando resto.
  static Future<void> guardar({
    String? clientId,
    String? clientSecret,
    String? access,
    String? refresh,
    String? expiry,
    String? email,
  }) async {
    final viejo = await leer() ?? <String, dynamic>{};
    final nuevo = Map<String, dynamic>.from(viejo);
    if (clientId != null) nuevo['client_id'] = clientId;
    if (clientSecret != null) nuevo['client_secret'] = clientSecret;
    if (access != null) nuevo['access'] = access;
    if (refresh != null) nuevo['refresh'] = refresh;
    if (expiry != null) nuevo['expiry'] = expiry;
    if (email != null) nuevo['email'] = email;
    await _escribir(nuevo);
  }

  /// Pone las llaves guardadas en Settings (en memoria) si están vacías.
  /// true = había llaves y quedaron listas para usar.
  static Future<bool> restaurarLlaves() async {
    if (Settings.instance.colabClientId.trim().isNotEmpty &&
        Settings.instance.colabClientSecret.trim().isNotEmpty) {
      return true;
    }
    Map<String, dynamic>? m;
    try {
      m = await leer();
    } catch (_) {
      return false;
    }
    if (m == null) return false;
    final id = '${m['client_id'] ?? ''}'.trim();
    final sec = '${m['client_secret'] ?? ''}'.trim();
    if (id.isEmpty || sec.isEmpty) return false;
    Settings.instance.colabClientId = id;
    Settings.instance.colabClientSecret = sec;
    return true;
  }

  /// Borra solo los tokens (la sesión). Las llaves quedan para entrar
  /// de un toque.
  static Future<void> olvidarTokens() async {
    Map<String, dynamic>? m;
    try {
      m = await leer();
    } catch (_) {
      return;
    }
    if (m == null) return;
    m.remove('access');
    m.remove('refresh');
    m.remove('expiry');
    await _escribir(m);
  }

  /// Borra el acceso guardado (olvidar).
  static Future<void> olvidar() async {
    try {
      final db = await _abrir();
      try {
        db.execute('DELETE FROM cuenta_colab WHERE id = ?;', [_id]);
      } finally {
        db.dispose();
      }
    } catch (_) {}
  }
}
