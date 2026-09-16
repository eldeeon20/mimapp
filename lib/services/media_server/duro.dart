import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../toolsec/toolsec.dart';

/// Cifrado DURO por trozos (AES-256-GCM autenticado) para los moldes.
///
/// GCM no permite descifrar rangos de un stream corrido, así que cada
/// archivo se parte en trozos fijos ([trozoClaro] en claro) y cada trozo
/// es un envelope independiente: `nonce(12) + cifrado + tag(16)`.
///
/// - Clave de archivo: PBKDF2-HMAC-SHA256 una vez por archivo
///   (`semilla|nombre` + sal del molde). Cara una sola vez (se cachea
///   por molde abierto).
/// - Clave de trozo: HMAC-SHA256(claveArchivo, 'molde-chunk|i').
/// - Nonce: 4 ceros + índice uint64 BE (único por clave de archivo).
/// - Overhead por trozo: 28 bytes fijos → matemática O(1):
///   `offset(trozo N) = inicio + N * (trozoClaro + 28)`.
class Duro {
  Duro._();

  /// Trozo en claro por defecto (64 KB).
  static const trozoClaro = 64 * 1024;

  /// Overhead por trozo: nonce 12 + tag GCM 16.
  static const overhead = 12 + 16;

  static const _pbkdf2Vueltas = 20000;

  /// Sal aleatoria del molde (hex, 16 bytes). Se guarda en la SQL.
  static String nuevaSal() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _salBytes(String salHex) {
    final s = salHex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = <int>[];
    for (var i = 0; i + 1 < s.length; i += 2) {
      out.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    if (out.isEmpty) {
      throw StateError('media_server: sal del molde vacía o inválida');
    }
    return out;
  }

  /// Clave de 32 bytes del archivo (se cachea por molde abierto).
  /// [clave] = LA MISMA clave que abre la SQL (sql+molde, una sola).
  static Future<Uint8List> claveArchivo({
    required String clave,
    required String molde,
    required String nombre,
    required String salHex,
  }) async {
    if (clave.isEmpty) {
      throw ArgumentError('media_server: clave vacía');
    }
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Vueltas,
      bits: 256,
    );
    final derivada = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode('$clave|$molde|$nombre')),
      nonce: _salBytes(salHex),
    );
    return Uint8List.fromList(await derivada.extractBytes());
  }

  /// Nonce de 12 bytes para el trozo i (único por clave de archivo).
  static Uint8List _nonce(int i) {
    final b = Uint8List(12);
    final v = ByteData.sublistView(b);
    v.setUint64(4, i.toUnsigned(64), Endian.big);
    return b;
  }

  static Future<Uint8List> _claveTrozo(
      Uint8List claveArchivo, int i) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode('molde-chunk|$i'),
      secretKey: SecretKey(claveArchivo),
    );
    return Uint8List.fromList(mac.bytes);
  }

  /// Cifra UN trozo en claro → `nonce + cifrado + tag`.
  static Future<Uint8List> cifrarTrozo({
    required Uint8List claveArchivo,
    required int indice,
    required Uint8List claro,
  }) async {
    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(
      claro,
      secretKey: SecretKey(await _claveTrozo(claveArchivo, indice)),
      nonce: _nonce(indice),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Descifra UN trozo (`nonce + cifrado + tag`) → claro.
  /// Tag inválido (semilla mal o bloque alterado) → lanza.
  static Future<Uint8List> descifrarTrozo({
    required Uint8List claveArchivo,
    required int indice,
    required Uint8List paquete,
  }) async {
    if (paquete.length < overhead) {
      throw StateError(
          'media_server: trozo $indice truncado (${paquete.length} bytes)');
    }
    final aes = AesGcm.with256bits();
    try {
      final claro = await aes.decrypt(
        SecretBox.fromConcatenation(
          paquete,
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: SecretKey(await _claveTrozo(claveArchivo, indice)),
      );
      return Uint8List.fromList(claro);
    } catch (e) {
      throw StateError(
          'media_server: trozo $indice no autentica (¿semilla mal o '
          'bloque alterado?): $e');
    }
  }

  /// Largo en claro del trozo i (el último puede ser más corto).
  static int claroDe(int indice, int tamano, int trozo) {
    final ini = indice * trozo;
    final resto = tamano - ini;
    if (resto <= 0) return 0;
    return resto < trozo ? resto : trozo;
  }

  /// Offset ABSOLUTO en el .mld donde empieza el trozo i.
  static int offsetDe(int inicio, int indice, int trozo) {
    return inicio + indice * (trozo + overhead);
  }

  /// Largo guardado del trozo i (claro + overhead).
  static int largoDe(int indice, int tamano, int trozo) {
    return claroDe(indice, tamano, trozo) + overhead;
  }

  /// Descifra del lado USER un rango crudo del server: cada paquete con
  /// su clave de archivo + recorte exacto a [desde, hasta).
  /// El user puede porque abrió la SQL (clave+sal+nombre → clave).
  /// [semillaXor] solo para moldes xor viejos (su semilla ToolSec).
  static Future<Uint8List> descifrarRango({
    required Uint8List claveArchivo,
    required RangoCrudo rango,
    String semillaXor = '',
  }) async {
    if (rango.modo == 'xor') {
      // Moldes xor viejos: keystream ToolSec real con su semilla.
      if (semillaXor.isEmpty) {
        throw StateError('media_server: rango xor sin semilla '
            '(pedilo al server con `pedir`)');
      }
      if (rango.paquetes.length != 1) {
        throw StateError('media_server: rango xor con '
            '${rango.paquetes.length} paquetes (esperaba 1)');
      }
      return ToolSec(semillaXor)
          .processBytesDesde(rango.paquetes.first.bytes, rango.desde);
    }
    final fuera = <int>[];
    for (final p in rango.paquetes) {
      final claro = await descifrarTrozo(
        claveArchivo: claveArchivo,
        indice: p.indice,
        paquete: p.bytes,
      );
      final iniTrozo = p.indice * rango.trozo;
      final d = (rango.desde - iniTrozo).clamp(0, claro.length);
      var h = (rango.hasta - iniTrozo).clamp(0, claro.length);
      if (h < d) h = d;
      fuera.addAll(claro.sublist(d, h));
    }
    final want = rango.hasta - rango.desde;
    if (fuera.length != want) {
      throw StateError('media_server: rango descifrado con '
          '${fuera.length} bytes (esperaba $want)');
    }
    return Uint8List.fromList(fuera);
  }
}

/// Paquete crudo del server: bytes cifrados tal cual están en el .mld
/// + índice (trozo GCM, o posición en claro para xor).
class PaqueteCrudo {
  final int indice;
  final Uint8List bytes;
  PaqueteCrudo(this.indice, this.bytes);
}

/// Rango crudo: lo que el server devuelve; el user lo descifra con
/// [Duro.descifrarRango] porque tiene la SQL (semilla+sal+nombre).
class RangoCrudo {
  /// 'gcm-c' o 'xor'.
  final String modo;
  final String archivo;
  final int desde;
  final int hasta;
  final int trozo;
  final int tamano;
  final List<PaqueteCrudo> paquetes;
  RangoCrudo({
    required this.modo,
    required this.archivo,
    required this.desde,
    required this.hasta,
    required this.trozo,
    required this.tamano,
    required this.paquetes,
  });
}
