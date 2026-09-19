import 'dart:async';

import 'package:http/http.dart' as http;

import 'colab_auth.dart';
import 'colab_config.dart';

/// Daemon keep-alive para mantener la sesión de Colab activa sin pestaña.
///
/// Envía GET a /tun/m/<endpoint>/keep-alive/ cada 60s con X-Colab-Tunnel: Google.
/// Corta tras 2 errores 4xx consecutivos o 24 horas.
///
/// El ping vive en el singleton [ColabService]: sigue corriendo aunque se
/// cierre el diálogo. Con el servicio en primer plano activo (888) el
/// proceso sobrevive si la UI se va a fondo y el Timer sigue disparando.
/// Cada ping refresca [StatusNotifier] (contador de tiempo activo) y ante
/// un corte avisa con notificación una sola vez ([onDesconectado]).
class ColabKeepAlive {
  final ColabAuth _auth;
  Timer? _timer;
  int _consecutive4xx = 0;
  String? _endpoint;
  DateTime? _startTime;

  /// Cantidad de pings OK desde el inicio (para el contador de la UI).
  int pingOk = 0;

  /// Último ping exitoso (null = aún ninguno).
  DateTime? ultimoPing;

  /// Se llama tras cada ping (ok o no) para repintar contador/notificación.
  void Function()? onTick;

  /// Se llama UNA vez cuando se corta (4xx x2, 24h o stop manual con
  /// [avisar]). Recibe el endpoint y el motivo legible.
  void Function(String endpoint, String motivo)? onDesconectado;

  bool get isRunning => _timer != null;
  String? get currentEndpoint => _endpoint;

  Duration get elapsed =>
      _startTime != null ? DateTime.now().difference(_startTime!) : Duration.zero;

  /// "3h 12m" / "12m 40s" para la notificación y el diálogo.
  static String fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  ColabKeepAlive(this._auth);

  /// Inicia el daemon de keep-alive para el endpoint dado.
  void start(String endpoint) {
    stop(avisar: false);
    _endpoint = endpoint;
    _consecutive4xx = 0;
    _startTime = DateTime.now();
    pingOk = 0;
    ultimoPing = null;

    // Primer ping inmediato
    _ping();

    // Luego cada 60s
    _timer = Timer.periodic(ColabConfig.keepAliveInterval, (_) => _ping());
  }

  /// Detiene el daemon. Con [avisar]=true dispara [onDesconectado]
  /// (stop manual de la UI normalmente NO avisa).
  void stop({bool avisar = false, String motivo = 'detenido'}) {
    final ep = _endpoint;
    _timer?.cancel();
    _timer = null;
    _endpoint = null;
    _startTime = null;
    _consecutive4xx = 0;
    if (avisar && ep != null) {
      try {
        onDesconectado?.call(ep, motivo);
      } catch (_) {}
    }
    try {
      onTick?.call();
    } catch (_) {}
  }

  Future<void> _ping() async {
    if (_endpoint == null) return;
    final ep = _endpoint!;

    // Verificar límite de 24h
    if (_startTime != null &&
        DateTime.now().difference(_startTime!) >= ColabConfig.keepAliveMaxDuration) {
      final motivo = 'límite 24h alcanzado';
      stop(avisar: false);
      try {
        onDesconectado?.call(ep, motivo);
      } catch (_) {}
      return;
    }

    try {
      // Formato que andaba (pre-"CLI exacto"): authHeaders completos
      // (Bearer + Accept + agent) + X-Colab-Tunnel + ?authuser=0.
      // El mínimo (solo Bearer+Tunnel) devolvía 400 y mataba la
      // celda al minuto.
      final headers = await _auth.authHeaders();
      headers['X-Colab-Tunnel'] = 'Google';
      const params = {'authuser': '0'};
      final url = Uri.https(
        ColabConfig.colabHost,
        '/tun/m/$ep/keep-alive/',
        params,
      );

      final response = await http
          .get(url, headers: headers)
          .timeout(ColabConfig.keepAliveTimeout);

      // Sin auto-stop por error de ping: se cuenta y se sigue.
      // Solo paran el usuario o el límite de 24h.
      if (response.statusCode >= 400 && response.statusCode < 500) {
        _consecutive4xx++;
      } else {
        _consecutive4xx = 0;
        pingOk++;
        ultimoPing = DateTime.now();
      }
    } catch (_) {
      // Timeout/red: reintenta, no cuenta como error
      _consecutive4xx = 0;
    }
    try {
      onTick?.call();
    } catch (_) {}
  }
}
