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

  /// Cifra un lote v2: `global(cdn_pass + cdn)` con el maestro.
  /// `PRBX(maestro, [LOTE][u32be len][pass][datos])`.
  static Future<Uint8List> encryptLote(
      Uint8List datos, String passMaestro, String passLote) async {
    final pb = utf8.encode(passLote);
    final plano = BytesBuilder()
      ..add([0x4C, 0x4F, 0x54, 0x45]) // LOTE
      ..add([
        (pb.length >> 24) & 0xFF,
        (pb.length >> 16) & 0xFF,
        (pb.length >> 8) & 0xFF,
        pb.length & 0xFF
      ])
      ..add(pb)
      ..add(datos);
    return encrypt(plano.toBytes(), passMaestro);
  }
}

/// Lote v2: pass del lote pegada al inicio + contenido, todo con
/// el maestro. El pass global descifra TODO: pass + dato origen.
class LoteAbierto {
  final int version; // 1 o 2
  final String passLote; // '' en v1
  final Uint8List contenido;
  const LoteAbierto({
    required this.version,
    required this.passLote,
    required this.contenido,
  });
}

/// Abre v1 (PRBX directo) o v2 (marca LOTE). En v2 devuelve el
/// pass del lote en texto además del contenido descifrado.
Future<LoteAbierto?> decryptLote(
    Uint8List data, String passMaestro) {
  return _decryptLote(data, passMaestro);
}

Future<LoteAbierto?> _decryptLote(
    Uint8List data, String passMaestro) async {
  try {
    final pt = await CryptoVault.decrypt(data, passMaestro);
    if (pt == null) return null;
    if (pt.length >= 8 &&
        pt[0] == 0x4C &&
        pt[1] == 0x4F &&
        pt[2] == 0x54 &&
        pt[3] == 0x45) {
      final len = ByteData.sublistView(pt, 4, 8).getUint32(0, Endian.big);
      if (len <= 0 || pt.length < 8 + len) return null;
      final passLote =
          utf8.decode(Uint8List.sublistView(pt, 8, 8 + len));
      final contenido = Uint8List.sublistView(pt, 8 + len);
      return LoteAbierto(
          version: 2, passLote: passLote, contenido: contenido);
    }
    return LoteAbierto(version: 1, passLote: '', contenido: pt);
  } catch (_) {
    return null;
  }
}
