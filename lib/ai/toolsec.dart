import 'dart:io';
import 'dart:typed_data';

/// Cifrado/descifrado XOR por semilla — algoritmo idéntico a ToolSec (Godot/Rust).
///
/// XOR es simétrico: cifrar y descifrar es la misma operación.
/// Distinta semilla = distinta secuencia de XOR = distinto resultado.
///
/// Uso:
///   final ts = ToolSec('mi_secreto');
///   ts.encodeFile('script.gd');        // archivos chicos (todo en RAM)
///   ts.encodeFileLarge('model.pt');    // archivos grandes (streaming 1MB chunks)
class ToolSec {
  final int _seed;

  ToolSec(String seed) : _seed = _djb2(seed);

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

  /// Cifra/descifra un archivo chico (todo en RAM).
  void encodeFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Archivo no encontrado', path);
    }
    file.writeAsBytesSync(processBytes(file.readAsBytesSync()));
  }

  /// Cifra/descifra bytes sin tocar disco.
  Uint8List encodeBytes(Uint8List data) => processBytes(data);

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
    // Sobreescribe el original con el resultado
    file.writeAsBytesSync(temp.readAsBytesSync());
    temp.deleteSync();
  }
}
