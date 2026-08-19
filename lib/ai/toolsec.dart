import 'dart:io';
import 'dart:typed_data';

/// Cifrado/descifrado XOR por semilla — algoritmo idéntico a ToolSec (Godot/Rust).
///
/// XOR es simétrico: cifrar y descifrar es la misma operación.
/// Distinta semilla = distinta secuencia de XOR = distinto resultado.
///
/// Uso:
///   final ts = ToolSec('mi_secreto');
///   ts.encodeFile('script.gd');   // cifra
///   ts.encodeFile('script.gd');   // descifra (mismo XOR)
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

  /// Procesa bytes en memoria (XOR byte a byte con PRNG xorshift64*).
  /// Mismo algoritmo que ToolSec.encode() en Godot.
  Uint8List processBytes(Uint8List data) {
    final result = Uint8List(data.length);
    int state = _seed.toUnsigned(64);
    for (var i = 0; i < data.length; i++) {
      // xorshift64* (Godot RandomNumberGenerator)
      state ^= state >> 12;
      state ^= state << 25;
      state ^= state >> 27;
      // randi() = (state * 2685821657736338717) >> 32, luego & 0xFF
      final rand =
          ((state.toUnsigned(64) * 2685821657736338717).toUnsigned(64) >> 32) &
              0xFF;
      result[i] = data[i] ^ rand;
    }
    return result;
  }

  /// Cifra/descifra un archivo en disco (sobreescribe).
  void encodeFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Archivo no encontrado', path);
    }
    final data = file.readAsBytesSync();
    file.writeAsBytesSync(processBytes(data));
  }

  /// Cifra/descifra bytes sin tocar disco.
  Uint8List encodeBytes(Uint8List data) => processBytes(data);
}
