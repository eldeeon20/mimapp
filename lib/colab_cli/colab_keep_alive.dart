import 'dart:async';

import 'package:http/http.dart' as http;

import 'colab_auth.dart';
import 'colab_config.dart';

/// Daemon keep-alive para mantener la sesión de Colab activa sin pestaña.
///
/// Puro Dart (anda en app y en web): GET a /tun/m/<endpoint>/keep-alive/
/// cada 60s. Doble modo por ciclo para diagnosticar:
///   nuestro: Bearer + X-Colab-Tunnel (+ Accept/agent + ?authuser=0)
///   cli:     Bearer + X-Colab-Tunnel + Accept + X-Colab-Client-Agent
///            + ?authuser=0 (igual que google-colab-cli)
/// Reporta el error de CADA modo (okNuestro/okCli/errNuestro/errCli).
/// Ningún error detiene: solo paran el usuario o el límite de 24h.
/// [proxyUrl]: proxy web opcional (`https://host/prefijo/` se antepone,
/// `http://host:puerto` va por HttpClient en nativo).
class ColabKeepAlive {
  final ColabAuth _auth;
  Timer? _timer;
  int _consecutive4xx = 0;
  String? _endpoint;
  DateTime? _startTime;

  /// Proxy web opcional (vacío = directo).
  String proxyUrl = '';

  /// Cantidad de pings OK desde el inicio (para el contador de la UI).
  int pingOk = 0;

  /// Duelo de modos.
  int okNuestro = 0;
  int okCli = 0;
  String errNuestro = '';
  String errCli = '';

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

  /// Un ciclo: pingeo en los dos modos y reporto cada error.
  /// Nunca detiene: los errores solo se anotan.
  Future<void> _ping() async {
    final ep = _endpoint;
    if (ep == null) return;

    // Verificar límite de 24h
    if (_startTime != null &&
        DateTime.now().difference(_startTime!) >=
            ColabConfig.keepAliveMaxDuration) {
      stop(avisar: true, motivo: 'límite 24h alcanzado');
      return;
    }

    String token;
    try {
      token = await _auth.getToken();
    } catch (e) {
      errNuestro = 'token: $e';
      errCli = 'token: $e';
      try {
        onTick?.call();
      } catch (_) {}
      return;
    }

    final rN = await _pingModo(ep, token, cli: false);
    final rC = await _pingModo(ep, token, cli: true);
    if (rN.ok) {
      okNuestro++;
      errNuestro = '';
    } else {
      errNuestro = rN.error;
    }
    if (rC.ok) {
      okCli++;
      errCli = '';
    } else {
      errCli = rC.error;
    }
    if (rN.ok || rC.ok) {
      _consecutive4xx = 0;
      pingOk++;
      ultimoPing = DateTime.now();
    } else {
      _consecutive4xx++;
    }
    try {
      onTick?.call();
    } catch (_) {}
  }

  /// Un ping en un modo. ok=true con 2xx o timeout de lectura
  /// (el TFE anota y la VM no contesta: éxito CLI).
  Future<({bool ok, String error})> _pingModo(
    String ep,
    String token, {
    required bool cli,
  }) async {
    try {
      final path = '/tun/m/$ep/keep-alive/';
      final url = proxyUrl.isEmpty
          ? Uri.https(ColabConfig.colabHost, path, {'authuser': '0'})
          : Uri.parse(
              '${proxyUrl.endsWith('/') ? proxyUrl.substring(0, proxyUrl.length - 1) : proxyUrl}'
              'https://${ColabConfig.colabHost}$path?authuser=0');
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'X-Colab-Tunnel': 'Google',
        'Accept': 'application/json',
        if (cli) 'X-Colab-Client-Agent': 'colab-cli',
      };
      final response = await http
          .get(url, headers: headers)
          .timeout(ColabConfig.keepAliveTimeout);
      final code = response.statusCode;
      if (code >= 200 && code < 300) return (ok: true, error: '');
      var body = '';
      try {
        body = response.body.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (body.length > 120) body = body.substring(0, 120);
      } catch (_) {}
      return (
        ok: false,
        error: 'http $code${body.isEmpty ? '' : ' · $body'}'
      );
    } on TimeoutException {
      // Timeout de lectura = éxito (TFE anotó, la VM no contesta).
      return (ok: true, error: '');
    } catch (e) {
      // Red: neutro, reintenta en el próximo ciclo.
      return (ok: false, error: 'red: $e');
    }
  }
}
