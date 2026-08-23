import 'dart:typed_data';

import '../src/rust/api/shamir.dart' as rust;

/// Shamir Secret Sharing — porte del `Shamir` de Gtool.
/// Divide un secreto/mensaje en N partes; con `threshold` se reconstruye.
/// Útil p/ej. repartir una clave en 5 partes de las que 3 bastan.
class Shamir {
  /// Divide [data] en [count] partes (se necesitan [threshold] para unir).
  /// Lanza excepción con parámetros inválidos (1..255).
  List<Uint8List> split(Uint8List data, int count, int threshold) {
    final parts = rust.shamirSplit(data: data, count: count, threshold: threshold);
    return parts.map(Uint8List.fromList).toList();
  }

  /// Reconstruye los datos desde >= threshold partes.
  /// null = secreto perdido (partes insuficientes o corruptas).
  Uint8List? combine(List<Uint8List> shares) {
    final out = rust.shamirCombine(shares: shares);
    return out == null ? null : Uint8List.fromList(out);
  }
}
