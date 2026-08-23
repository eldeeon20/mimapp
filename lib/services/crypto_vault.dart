import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Cifrado fuerte de archivos (AES-256-GCM + PBKDF2-HMAC-SHA256).
///
/// Reemplaza al XOR de ToolSec para datos en reposo: clave derivada con
/// salt aleatorio por archivo, nonce único y tag de autenticación que
/// detecta cualquier manipulación del ciphertext.
///
/// Formato del envelope v1:
///   MAGIC "PRBX" | version u8 | salt 16B | nonce 12B | ciphertext | tag 16B
class CryptoVault {
  static const List<int> _magic = [0x50, 0x52, 0x42, 0x58]; // "PRBX"
  static const int _version = 1;
  static const int _saltLen = 16;
  static const int _kdfIterations = 200000;

  static final AesGcm _algo = AesGcm.with256bits();
  static final Pbkdf2 _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _kdfIterations,
    bits: 256,
  );

  /// ¿Parece un envelope CryptoVault?
  static bool isEnvelope(Uint8List data) {
    if (data.length < _magic.length + 1 + _saltLen + 12 + 16) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }

  /// Cifra [plain] con [passphrase]. El salt y el nonce son aleatorios,
  /// así que dos llamadas idénticas producen ciphertexts distintos.
  static Future<Uint8List> encrypt(
      Uint8List plain, String passphrase) async {
    final salt = _random(_saltLen);
    final nonce = _algo.newNonce();
    final key = await _deriveKey(passphrase, salt);

    final box = await _algo.encrypt(plain, secretKey: key, nonce: nonce);

    final out = BytesBuilder()
      ..add(_magic)
      ..addByte(_version)
      ..add(salt)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  /// Descifra un envelope. null = passphrase incorrecta o datos alterados.
  /// Si no es un envelope válido retorna null también (el caller decide
  /// probar el legado).
  static Future<Uint8List?> decrypt(Uint8List data, String passphrase) async {
    if (!isEnvelope(data)) return null;
    try {
      var off = _magic.length;
      final version = data[off];
      if (version != _version) return null;
      off += 1;

      final salt = Uint8List.sublistView(data, off, off + _saltLen);
      off += _saltLen;

      final nonceLen = _algo.newNonce().length; // 12 para AES-GCM
      final nonce = Uint8List.sublistView(data, off, off + nonceLen);
      off += nonceLen;

      final cipherText =
          Uint8List.sublistView(data, off, data.length - 16);
      final mac = Mac(Uint8List.sublistView(data, data.length - 16));

      final key = await _deriveKey(passphrase, salt);
      final clear = await _algo.decrypt(
        SecretBox(cipherText, mac: mac, nonce: nonce),
        secretKey: key,
      );
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  static Future<SecretKey> _deriveKey(String passphrase, List<int> salt) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  static Uint8List _random(int len) {
    final r = Random.secure();
    return Uint8List.fromList(
        List.generate(len, (_) => r.nextInt(256)));
  }
}
