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

  /// Inicializar: carga tokens guardados al arrancar la app.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await auth.loadTokens();
  }
}
