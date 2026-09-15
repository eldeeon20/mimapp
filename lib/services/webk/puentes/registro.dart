import 'puente.dart';

/// Registro de conectores: rutea cada comando a SU conector por nombre.
///
/// La pantalla solo hace `atender(cmd)`. Agregar un conector nuevo es
/// crear su archivo en puentes/ + una línea de `registrar`.
class RegistroPuentes {
  final _porCmd = <String, WebkConector>{};
  final _todos = <WebkConector>[];

  void registrar(WebkConector c) {
    _todos.add(c);
    for (final k in c.comandos) {
      _porCmd[k] = c;
    }
  }

  /// Manda el comando a su conector. Sin conector → 'CMD?'.
  /// Si el conector lanza → 'ERROR: ...' (el JS siempre recibe algo).
  Future<dynamic> atender(Map<String, dynamic> cmd) async {
    final c = _porCmd[cmd['cmd']?.toString() ?? ''];
    if (c == null) return 'CMD?';
    try {
      return await c.atender(cmd);
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  /// Cierra los conectores que guardan algo (al detener/salir).
  void cerrarTodos() {
    for (final c in _todos) {
      if (c is! WebkCerrable) continue;
      try {
        (c as WebkCerrable).cerrar();
      } catch (_) {}
    }
  }
}
