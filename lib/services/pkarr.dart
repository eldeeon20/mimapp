import 'dart:typed_data';

import '../src/rust/api/pkarr.dart' as rust;
import 'settings.dart';

/// PKARR: DNS descentralizado sobre DHT/relays.
///
/// Claves ed25519 de 32 bytes + paquetes firmados con registros TXT.
/// Porte del `Gpkarr` de Gtool a Dart vía flutter_rust_bridge.
class Pkarr {
  static const defaultRelays = <String>[
    'https://relay.pkarr.org',
    'https://pkarr.pubky.org',
  ];

  /// Secreto aleatorio (32 bytes).
  Uint8List keyRand() => Uint8List.fromList(rust.pkarrKeyRand());

  /// Secreto determinístico desde una semilla textual.
  Uint8List seedToKey(String seed) =>
      Uint8List.fromList(rust.pkarrSeedToKey(seed: seed));

  /// Clave pública zbase32 desde el secreto (vacío si inválido).
  String publicKey(Uint8List secret) {
    _checkSecret(secret);
    return rust.pkarrPublicKey(secret: secret);
  }

  /// Publica un registro TXT `name = value` firmado con el secreto.
  /// [mode]: 'dht' | 'relays' | 'both'.
  Future<bool> publish({
    required Uint8List secret,
    required String name,
    required String value,
    String mode = 'relays',
    List<String> relays = defaultRelays,
    int ttl = 30,
  }) async {
    _checkSecret(secret);
    return rust.pkarrPublish(
      secret: secret,
      name: name,
      value: value,
      mode: mode,
      relays: relays,
      ttl: ttl,
    );
  }

  /// Resuelve una clave pública zbase32 → paquete como texto ('' si falla).
  Future<String> resolve({
    required String publicKeyZbase32,
    String mode = 'relays',
    List<String> relays = defaultRelays,
  }) {
    return rust.pkarrResolve(
      pubkeyZbase32: publicKeyZbase32,
      mode: mode,
      relays: relays,
    );
  }

  // ---------------- Guardar / listar / borrar (cifrado en config.pr) ----

  /// Guarda un secreto con un nombre; retorna su clave pública.
  Future<String> saveKey(String nombre, Uint8List secret) async {
    final pub = publicKey(secret);
    final s = Settings.instance;
    s.pkarrKeys.removeWhere((k) => k['nombre'] == nombre);
    s.pkarrKeys.add({
      'nombre': nombre,
      'secretHex': _toHex(secret),
      'publicKey': pub,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await s.save();
    return pub;
  }

  List<Map<String, dynamic>> listKeys() => Settings.instance.pkarrKeys;

  /// Recupera el secreto guardado por nombre (null si no existe).
  Uint8List? loadSecret(String nombre) {
    for (final k in listKeys()) {
      if (k['nombre'] == nombre) {
        final hex = '${k['secretHex']}';
        if (hex.isEmpty) return null;
        return _fromHex(hex);
      }
    }
    return null;
  }

  String? publicKeyOf(String nombre) {
    for (final k in listKeys()) {
      if (k['nombre'] == nombre) return '${k['publicKey']}';
    }
    return null;
  }

  Future<bool> deleteKey(String nombre) async {
    final s = Settings.instance;
    final before = s.pkarrKeys.length;
    s.pkarrKeys.removeWhere((k) => k['nombre'] == nombre);
    await s.save();
    return s.pkarrKeys.length != before;
  }

  /// Publica usando una clave guardada por nombre.
  Future<bool> publishAs(
    String nombre, {
    required String name,
    required String value,
    String mode = 'relays',
    List<String> relays = defaultRelays,
    int ttl = 30,
  }) async {
    final secret = loadSecret(nombre);
    if (secret == null) return false;
    return publish(
      secret: secret,
      name: name,
      value: value,
      mode: mode,
      relays: relays,
      ttl: ttl,
    );
  }
}

void _checkSecret(Uint8List secret) {
  if (secret.length != 32) {
    throw ArgumentError('La clave debe tener exactamente 32 bytes');
  }
}

String _toHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
