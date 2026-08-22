import 'dart:async';

import '../colab_cli/colab_auth.dart';
import '../colab_cli/colab_config.dart';
import '../colab_cli/colab_keep_alive.dart';
import '../colab_cli/colab_sessions.dart';

/// Servicio Colab: singleton que vive toda la vida de la app.
/// Auth + keep-alive + sesiones. La UI solo lee de acá.
class ColabService {
  static final ColabService _instance = ColabService._();
  factory ColabService() => _instance;
  ColabService._();

  final ColabAuth auth = ColabAuth();
  late final ColabKeepAlive keepAlive = ColabKeepAlive(auth);
  late final ColabSessions sessions = ColabSessions(auth);

  bool _initialized = false;

  /// Cantidad de sesiones de Colab activas (para el panel de estado).
  int activeSessionCount = 0;

  /// Endpoint del keep-alive actualmente activo (null = inactivo).
  String? activeEndpoint;

  /// Mantiene Colab vivo en SEGUNDO PLANO aunque se cierre el menú.
  /// No se detiene al salir del diálogo: vive con el singleton.
  void startKeepAlive(String endpoint) {
    activeEndpoint = endpoint;
    keepAlive.start(endpoint);
  }

  /// Detiene el keep-alive (solo por acción explícita del usuario).
  void stopKeepAlive() {
    keepAlive.stop();
    activeEndpoint = null;
  }

  /// Inicializar: carga tokens guardados al arrancar la app.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await auth.loadTokens();
  }
}
