import 'dart:typed_data';

import '../src/rust/api/pkarr.dart' as rust;

/// PKARR v8 adaptado al nuevo modelo de identidad:
/// - La secret key se genera y guarda CIFRADA lado Rust (AES-GCM con clave
///   derivada del PIN por PBKDF2) en <dir>/pkarr_key.bin. Reemplaza el
///   guardado viejo en hex plano dentro de config.pr.
/// - Lo publicado SIEMPRE es TXT público firmado (nunca cifrado).
/// - Modo de publicación default "both": DHT Kademlia Mainline + relays.
class Pkarr {
  static const defaultRelays = <String>[
    'https://relay.pkarr.org',
    'https://pkarr.pubky.org',
  ];

  /// Secreto aleatorio (32 bytes).
  Future<Uint8List> keyRand() async =>
      Uint8List.fromList(await rust.pkarrKeyRand());

  /// Secreto determinístico desde una semilla textual.
  Future<Uint8List> seedToKey(String seed) async =>
      Uint8List.fromList(await rust.pkarrSeedToKey(seed: seed));

  /// Clave pública zbase32 desde el secreto (vacío si inválido).
  Future<String> publicKey(Uint8List secret) =>
      rust.pkarrPublicKey(secret: secret);

  /// ¿Hay identidad cifrada guardada en [dir]?
  Future<bool> hasSavedKey(String dir) => rust.pkarrHasSavedKey(dir: dir);

  /// Genera identidad, la guarda cifrada con el PIN y devuelve pub+sec.
  Future<rust.PkarrIdentidad> generateEncrypted({
    required String pin,
    required String dir,
  }) =>
      rust.pkarrGenerateEncrypted(pin: pin, dir: dir);

  /// Descifra la clave con el PIN; devuelve pub+sec.
  Future<rust.PkarrIdentidad> loadEncrypted({
    required String pin,
    required String dir,
  }) =>
      rust.pkarrLoadEncrypted(pin: pin, dir: dir);

  /// Publica un TXT firmado con la identidad guardada.
  /// [mode]: 'both' (default) | 'dht' | 'relays'.
  Future<String> publish({
    required String pin,
    required String dir,
    required String name,
    required String value,
    int ttl = 300,
    String mode = 'both',
    List<String> relays = defaultRelays,
  }) =>
      rust.pkarrPublish(
        pin: pin,
        dir: dir,
        name: name,
        value: value,
        ttl: ttl,
        mode: mode,
        relays: relays,
      );

  /// Consulta una pubkey zbase32 de TERCEROS; devuelve líneas legibles
  /// (una por registro: nombre · ttl · tipo/valor).
  /// [policy]: 'network_only' | 'cache_first' | 'cache_only'.
  Future<List<String>> resolve({
    required String publicKeyZbase32,
    String mode = 'both',
    List<String> relays = defaultRelays,
    String policy = 'network_only',
  }) =>
      rust.pkarrResolve(
        pubkeyZbase32: publicKeyZbase32,
        mode: mode,
        relays: relays,
        policy: policy,
      );
}
