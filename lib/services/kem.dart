import 'dart:typed_data';

import '../src/rust/api/kem.dart' as rust;

/// KEM post-cuántico (libcrux): X25519, P256, ML-KEM 512/768/1024
/// e híbridos X25519+ML-KEM768 / X-Wing.
///
/// Flujo: A genera par → B encapsula contra la pública de A → B manda el
/// ciphertext → A desencapsula → ambos tienen el MISMO shared secret.
class Kem {
  Future<List<String>> listAlgorithms() async => rust.kemListAlgorithms();

  Future<KemKeyPair> keyGen(String algorithm) async {
    final kp = await rust.kemKeyGen(algorithm: algorithm);
    return KemKeyPair(
      privateKey: Uint8List.fromList(kp.privateKey),
      publicKey: Uint8List.fromList(kp.publicKey),
    );
  }

  Future<KemEncapsulation> encapsulate({
    required String algorithm,
    required Uint8List publicKey,
  }) async {
    final e = await rust.kemEncapsulate(
        algorithm: algorithm, publicKey: publicKey);
    return KemEncapsulation(
      sharedSecret: Uint8List.fromList(e.sharedSecret),
      ciphertext: Uint8List.fromList(e.ciphertext),
    );
  }

  Future<Uint8List> decapsulate({
    required String algorithm,
    required Uint8List ciphertext,
    required Uint8List privateKey,
  }) async {
    return Uint8List.fromList(await rust.kemDecapsulate(
      algorithm: algorithm,
      ciphertext: ciphertext,
      privateKey: privateKey,
    ));
  }
}

class KemKeyPair {
  final Uint8List privateKey;
  final Uint8List publicKey;
  KemKeyPair({required this.privateKey, required this.publicKey});
}

class KemEncapsulation {
  final Uint8List sharedSecret;
  final Uint8List ciphertext;
  KemEncapsulation({required this.sharedSecret, required this.ciphertext});
}
