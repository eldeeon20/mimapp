/// Un conector del puente JS→Dart (uno por archivo en puentes/).
///
/// Cada página/función tiene SU conector con SUS comandos: la pantalla
/// solo registra ([RegistroPuentes.registrar]) y deriva. 1000 páginas =
/// 1000 archivos chicos; la pantalla no crece.
abstract class WebkConector {
  /// Comandos que atiende este conector (ej: {'agenda_abrir', ...}).
  Set<String> get comandos;

  /// Atiende un comando. Respuesta: String/Map/List (serializable al JS).
  Future<dynamic> atender(Map<String, dynamic> cmd);
}

/// Los conectores que guardan algo abierto implementan esto para que la
/// pantalla los cierre al detener/salir.
abstract class WebkCerrable {
  void cerrar();
}

/// ¿La llave del comando coincide con la sesión de la app?
bool llaveOk(String llaveSesion, Map<String, dynamic> cmd) =>
    llaveSesion.isNotEmpty && cmd['llave']?.toString() == llaveSesion;
