import 'dart:typed_data';

import '../src/rust/api/kem.dart' as rust;

/// KEM post-cuántico (libcrux): X25519, P256, ML-KEM 512/768/1024
/// e híbridos X25519+ML-KEM768 / X-Wing.
///
/// Flujo: A genera par → le pasa la pública a B → B encapsula (obtiene
/// shared secret + ciphertext) → B manda ciphertext a A → A desencapsula
/// con su privada → ambos terminan con el MISMO shared secret.
class Kem {
  List<String> listAlgorithms() => rust.kemListAlgorithms();

  KemKeyPair keyGen(String algorithm) {
    final kp = rust.kemKeyGen(algorithm: algorithm);
    return KemKeyPair(
      privateKey: Uint8List.fromList(kp.privateKey),
      publicKey: Uint8List.fromList(kp.publicKey),
    );
  }

  KemEncapsulation encapsulate({
    required String algorithm,
    required Uint8List publicKey,
  }) {
    final e = rust.kemEncapsulate(algorithm: algorithm, publicKey: publicKey);
    return KemEncapsulation(
      sharedSecret: Uint8List.fromList(e.sharedSecret),
      ciphertext: Uint8List.fromList(e.ciphertext),
    );
  }

  Uint8List decapsulate({
    required String algorithm,
    required Uint8List ciphertext,
    required Uint8List privateKey,
  }) {
    return Uint8List.fromList(rust.kemDecapsulate(
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
