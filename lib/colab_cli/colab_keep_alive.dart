import 'dart:async';

import 'package:http/http.dart' as http;

import 'colab_auth.dart';
import 'colab_config.dart';

/// Daemon keep-alive para mantener la sesión de Colab activa sin pestaña.
///
/// Envía GET a /tun/m/<endpoint>/keep-alive/ cada 60s con X-Colab-Tunnel: Google.
/// Corta tras 2 errores 4xx consecutivos o 24 horas.
class ColabKeepAlive {
  final ColabAuth _auth;
  Timer? _timer;
  int _consecutive4xx = 0;
  String? _endpoint;
  DateTime? _startTime;

  bool get isRunning => _timer != null;
  String? get currentEndpoint => _endpoint;

  Duration get elapsed =>
      _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;

  ColabKeepAlive(this._auth);

  /// Inicia el daemon de keep-alive para el endpoint dado.
  void start(String endpoint) {
    stop();
    _endpoint = endpoint;
    _consecutive4xx = 0;
    _startTime = DateTime.now();

    // Primer ping inmediato
    _ping();

    // Luego cada 60s
    _timer = Timer.periodic(ColabConfig.keepAliveInterval, (_) => _ping());
  }

  /// Detiene el daemon.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _endpoint = null;
    _startTime = null;
    _consecutive4xx = 0;
  }

  Future<void> _ping() async {
    if (_endpoint == null) return;

    // Verificar límite de 24h
    if (_startTime != null &&
        DateTime.now().difference(_startTime!) >= ColabConfig.keepAliveMaxDuration) {
      stop();
      return;
    }

    try {
      final headers = await _auth.authHeaders();
      headers['X-Colab-Tunnel'] = 'Google';
      final params = {'authuser': '0'};
      final url = Uri.https(
        ColabConfig.colabHost,
        '/tun/m/$_endpoint/keep-alive/',
        params,
      );

      final response =
          await http.get(url, headers: headers).timeout(ColabConfig.keepAliveTimeout);

      if (response.statusCode >= 400 && response.statusCode < 500) {
        _consecutive4xx++;
        if (_consecutive4xx >= 2) {
          stop(); // Asignación borrada
        }
      } else {
        _consecutive4xx = 0;
      }
    } catch (_) {
      // Timeout/red: reintenta, no cuenta como error
      _consecutive4xx = 0;
    }
  }
}
