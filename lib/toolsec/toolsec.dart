import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';

import '../services/crypto_vault.dart';

/// Excepción cuando no se puede escribir sobre el archivo original.
/// Lleva los bytes ya cifrados para ofrecer guardar una copia.
class ToolSecCantWriteException implements Exception {
  final Uint8List encrypted;
  final String reason;
  ToolSecCantWriteException(this.encrypted, this.reason);

  @override
  String toString() => reason;
}

/// Cifrado/descifrado XOR por semilla — algoritmo idéntico a ToolSec (Godot/Rust).
///
/// XOR es simétrico: cifrar y descifrar es la misma operación.
/// Distinta semilla = distinta secuencia de XOR = distinto resultado.
///
/// Uso:
///   final ts = ToolSec('mi_secreto');
///   ts.encodeFile('script.gd');        // archivos chicos (todo en RAM)
///   ts.encodeFileLarge('model.pt');    // archivos grandes (streaming 1MB chunks)
///   await ts.encodeFileWithFallback('script.gd'); // fallback Android
class ToolSec {
  final int _seed;
  final String _seedString;

  ToolSec(String seed)
      : _seed = _djb2(seed),
        _seedString = seed;

  /// djb2 hash — mismo que Godot String.hash_u32().
  static int _djb2(String s) {
    int hash = 5381;
    for (var i = 0; i < s.length; i++) {
      hash = ((hash << 5) + hash + s.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash;
  }

  /// Siguiente estado del PRNG xorshift64* + byte aleatorio (0-255).
  /// Retorna (randByte, newState) para encadenar sin mutable.
  static (int, int) _nextRand(int state) {
    state ^= state >> 12;
    state ^= state << 25;
    state ^= state >> 27;
    final rand =
        ((state.toUnsigned(64) * 2685821657736338717).toUnsigned(64) >> 32) &
            0xFF;
    return (rand, state);
  }

  /// Procesa bytes en memoria (XOR byte a byte). Archivos chicos.
  Uint8List processBytes(Uint8List data) {
    final result = Uint8List(data.length);
    int state = _seed.toUnsigned(64);
    for (var i = 0; i < data.length; i++) {
      final (rand, next) = _nextRand(state);
      result[i] = data[i] ^ rand;
      state = next;
    }
    return result;
  }

  // =========================================================================
  // V2 fuerte: AES-256-GCM + PBKDF2 (ver CryptoVault). El XOR queda para
  // compatibilidad con Godot/Rust y archivos viejos; los datos nuevos en
  // reposo deberían usar estos métodos.
  // =========================================================================

  /// ¿Son bytes de un envelope fuerte (PRBX)?
  static bool isStrong(Uint8List data) => CryptoVault.isEnvelope(data);

  /// Cifra con AES-256-GCM derivando la clave de la semilla vía PBKDF2
  /// (salt aleatorio por archivo + tag de autenticación).
  Future<Uint8List> processBytesStrong(Uint8List plain) {
    return CryptoVault.encrypt(plain, _seedString);
  }

  /// Descifra fuerte. null = passphrase incorrecta o datos alterados.
  Future<Uint8List?> processBytesStrongDecrypt(Uint8List enc) {
    return CryptoVault.decrypt(enc, _seedString);
  }

  /// Auto-detecta: envelope PRBX -> descifra fuerte; si no, XOR legado.
  /// null solo si era PRBX y falló la autenticación.
  Future<Uint8List?> processBytesAuto(Uint8List data) async {
    if (isStrong(data)) {
      return processBytesStrongDecrypt(data);
    }
    return processBytes(data);
  }

  // =========================================================================
  // Android SAF: cifrado sobre el archivo REAL (Descargas, Documents, etc.)
  // =========================================================================

  /// Elige un archivo real con el picker del sistema (SAF).
  static Future<SafDocumentFile?> pickSafFile() =>
      SafUtil().pickFile(mimeTypes: ['*/*']);

  /// Elige una carpeta destino con permiso de escritura (SAF).
  static Future<SafDocumentFile?> pickSafDirectory() =>
      SafUtil().pickDirectory(writePermission: true);

  /// Cifra/descifra in-place sobre el archivo SAF elegido (como Godot:
  /// sobrescribe el original). Si no puede escribir, lanza
  /// [ToolSecCantWriteException] con los bytes ya cifrados incluidos.
  Future<String> encodeSafInPlace(SafDocumentFile doc) async {
    final saf = SafStream();
    final bytes = await saf.readFileBytes(doc.uri);
    if (bytes.isEmpty) {
      throw Exception('El archivo está vacío');
    }
    final data = processBytes(bytes);
    try {
      await saf.writeFileUriBytes(doc.uri, data);
    } catch (e) {
      throw ToolSecCantWriteException(data, '$e');
    }

    // Verificación post-escritura (tamaño).
    try {
      final stat = await SafUtil().stat(doc.uri, false);
      final size = stat?.length ?? -1;
      if (size >= 0 && size != data.length) {
        throw ToolSecCantWriteException(
            data,
            'Escritura incompleta: esperaba ${data.length} bytes, '
            'quedaron $size');
      }
    } on ToolSecCantWriteException {
      rethrow;
    } catch (_) {
      // stat falló (algunos proveedores no lo soportan): no es fatal.
    }
    return doc.name;
  }

  /// Guarda una copia cifrada en la carpeta que elija el usuario.
  /// Retorna el nombre real del archivo creado (SAF puede cambiarlo).
  static Future<String> saveSafCopy(
      Uint8List encrypted, String fileName) async {
    final dir = await pickSafDirectory();
    if (dir == null) throw Exception('Carpeta destino cancelada');
    final res = await SafStream().writeFileBytes(
      dir.uri,
      fileName,
      'application/octet-stream',
      encrypted,
      overwrite: true,
    );
    return res.fileName ?? fileName;
  }

  /// Cifra/descifra un archivo chico (todo en RAM).
  /// Retorna la ruta donde quedó el resultado.
  String encodeFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Archivo no encontrado', path);
    }
    file.writeAsBytesSync(processBytes(file.readAsBytesSync()));
    return path;
  }

  /// Cifra/descifra bytes sin tocar disco.
  Uint8List encodeBytes(Uint8List data) => processBytes(data);

  /// Cifra/descifra un archivo: siempre guarda en appSupportDir/toolsec/.
  /// Verifica que el archivo se escribió correctamente.
  /// Retorna la ruta final del archivo cifrado/descifrado.
  Future<String> encodeFileSecure(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Archivo no encontrado', path);
    }

    final originalBytes = file.readAsBytesSync();
    if (originalBytes.isEmpty) {
      throw Exception('El archivo está vacío: $path');
    }

    final data = processBytes(originalBytes);

    final appDir = await getApplicationSupportDirectory();
    final toolsecDir = Directory('${appDir.path}/toolsec');
    if (!toolsecDir.existsSync()) {
      toolsecDir.createSync(recursive: true);
    }
    final safeName = path.split(Platform.pathSeparator).last;
    final outPath = '${toolsecDir.path}/$safeName';
    final outFile = File(outPath);
    outFile.writeAsBytesSync(data);

    // Verificar que se escribió correctamente
    if (!outFile.existsSync()) {
      throw Exception('No se pudo crear el archivo de salida: $outPath');
    }
    final written = outFile.readAsBytesSync();
    if (written.length != data.length) {
      throw Exception(
          'Escritura incompleta: esperaba ${data.length} bytes, '
          'obtuve ${written.length} bytes');
    }
    if (outFile.lengthSync() != originalBytes.length) {
      throw Exception(
          'Tamaño inesperado: original ${originalBytes.length} bytes, '
          'resultado ${outFile.lengthSync()} bytes');
    }

    return outPath;
  }

  /// Cifra/descifra archivo grande por streaming (1MB chunks, sin OOM).
  /// Escribe el resultado en el mismo archivo (overwrite).
  void encodeFileLarge(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Archivo no encontrado', path);
    }
    final temp = File('$path._tmp_toolsec');
    final raf = file.openSync(mode: FileMode.read);
    final waf = temp.openSync(mode: FileMode.write);
    const chunkSize = 1024 * 1024; // 1MB
    int state = _seed.toUnsigned(64);
    try {
      while (true) {
        final chunk = raf.readSync(chunkSize);
        if (chunk.isEmpty) break;
        final out = Uint8List(chunk.length);
        for (var i = 0; i < chunk.length; i++) {
          final (rand, next) = _nextRand(state);
          out[i] = chunk[i] ^ rand;
          state = next;
        }
        waf.writeFromSync(out);
      }
    } finally {
      raf.closeSync();
      waf.closeSync();
    }
    file.writeAsBytesSync(temp.readAsBytesSync());
    temp.deleteSync();
  }
}
