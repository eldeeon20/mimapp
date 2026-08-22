import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'colab_auth.dart';
import 'colab_config.dart';

/// Prefijo XSSI que Google antepone a las respuestas JSON.
const _xssiPrefix = ")]}'\n";

/// Acelerador elegible al crear una sesión.
enum ColabAccelerator {
  cpu('CPU', {}),
  t4('GPU T4', {'variant': 'GPU', 'accelerator': 'T4'}),
  l4('GPU L4', {'variant': 'GPU', 'accelerator': 'L4'}),
  a100('GPU A100', {'variant': 'GPU', 'accelerator': 'A100'}),
  tpu('TPU', {'variant': 'TPU'});

  const ColabAccelerator(this.label, this.params);
  final String label;
  final Map<String, String> params;
}

/// Sesión (assignment) activa de Colab.
class ColabSession {
  final String endpoint;
  final String accelerator;
  final String variant;
  final int machineShape;

  /// URL del proxy del runtime (para WebSocket / ejecutar Python).
  final String proxyUrl;

  /// Token del proxy del runtime.
  final String proxyToken;

  ColabSession({
    required this.endpoint,
    this.accelerator = 'NONE',
    this.variant = 'DEFAULT',
    this.machineShape = 0,
    this.proxyUrl = '',
    this.proxyToken = '',
  });

  factory ColabSession.fromJson(Map<String, dynamic> j) {
    final proxy = j['runtimeProxyInfo'] as Map<String, dynamic>? ?? {};
    return ColabSession(
      endpoint: j['endpoint'] ?? '',
      accelerator: j['accelerator']?.toString() ?? 'NONE',
      variant: j['variant']?.toString() ?? 'DEFAULT',
      machineShape: j['machineShape'] is int
          ? j['machineShape']
          : int.tryParse('${j['machineShape']}') ?? 0,
      proxyUrl: proxy['url'] ?? '',
      proxyToken: proxy['token'] ?? '',
    );
  }
}

/// Gestión de sesiones de Colab — endpoints idénticos a google-colab-cli:
///   listar   → GET  /tun/m/assignments
///   asignar  → GET  /tun/m/assign?nbh=... → POST mismo URL (+XSRF)
///   soltar   → GET  /tun/m/unassign/$endpoint → POST mismo URL (+XSRF)
///   ping     → GET  /tun/m/$endpoint/keep-alive/ (+X-Colab-Tunnel)
class ColabSessions {
  final ColabAuth _auth;

  ColabSessions(this._auth);

  /// Strips XSSI prefix y parsea JSON. Si no es JSON válido, devuelve null.
  dynamic _parseBody(http.Response r) {
    var body = r.body;
    if (body.startsWith(_xssiPrefix)) {
      body = body.substring(_xssiPrefix.length);
    }
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Mensaje de error corto, sin HTML.
  String _err(String op, http.Response r) {
    var body = r.body.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    body = body.replaceAll(RegExp(r'\s+'), ' ');
    if (body.length > 150) body = '${body.substring(0, 150)}…';
    if (body.isEmpty) body = '(sin cuerpo)';
    return '$op falló (${r.statusCode}): $body';
  }

  Uri _colabUri(String path, [Map<String, String>? extraQuery]) {
    final params = {'authuser': '0'};
    if (extraQuery != null) params.addAll(extraQuery);
    return Uri.https(ColabConfig.colabHost, path, params);
  }

  Future<Map<String, String>> _headers() => _auth.authHeaders();

  /// UUID v4 random en formato web-safe base64-like del CLI:
  /// reemplaza '-' por '_' y rellena con '.' hasta 44 chars.
  static String _webSafeUuid() {
    final rnd = Random();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // versión 4
    b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    final u =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    final transformed = u.replaceAll('-', '_');
    return transformed + ('.' * (44 - u.length));
  }

  // ===========================================================================
  // Listar assignments
  // ===========================================================================

  /// Lista las sesiones activas del usuario.
  Future<List<ColabSession>> list() async {
    final response = await http.get(
      _colabUri('/tun/m/assignments'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception(_err('listar sesiones', response));
    }

    final data = _parseBody(response);
    final sessions = <ColabSession>[];

    void addAll(List items) {
      for (final item in items) {
        if (item is Map<String, dynamic>) sessions.add(ColabSession.fromJson(item));
      }
    }

    if (data is Map && data['assignments'] is List) {
      addAll(data['assignments'] as List);
    } else if (data is List) {
      addAll(data);
    }
    return sessions;
  }

  // ===========================================================================
  // Crear assignment (como el CLI: nbh uuid random → GET token → POST)
  // ===========================================================================

  /// Crea/asigna un runtime nuevo. Retorna la sesión creada.
  /// Asigna una sesión nueva. [accel] define CPU/GPU/TPU.
  Future<ColabSession> assign(
      {ColabAccelerator accel = ColabAccelerator.cpu}) async {
    final nbh = _webSafeUuid();
    final url = _colabUri('/tun/m/assign', {'nbh': nbh, ...accel.params});

    // 1er GET: el backend responde con el XSRF token (o sesión existente).
    final getResp = await http.get(url, headers: await _headers());
    if (getResp.statusCode != 200) {
      throw Exception(_err('assign (GET)', getResp));
    }
    final getData = _parseBody(getResp);

    // Si ya venía asignado, responde {endpoint, runtimeProxyInfo}.
    if (getData is Map &&
        getData.containsKey('endpoint') &&
        !getData.containsKey('nbh')) {
      return ColabSession.fromJson(
          Map<String, dynamic>.from(getData));
    }

    // Respuesta esperada: {acc, nbh, token, variant} → POST con XSRF.
    final xsrf = getData is Map ? '${getData['token'] ?? ''}' : '';
    final headers = await _headers();
    if (xsrf.isNotEmpty) headers['X-Goog-Colab-Token'] = xsrf;

    final postResp = await http.post(url, headers: headers);
    if (postResp.statusCode == 412) {
      throw Exception('Demasiadas asignaciones activas');
    }
    if (postResp.statusCode != 200) {
      throw Exception(_err('assign (POST)', postResp));
    }
    final data = _parseBody(postResp);
    if (data is! Map) {
      throw Exception('Respuesta de assign inesperada');
    }
    return ColabSession.fromJson(Map<String, dynamic>.from(data));
  }

  // ===========================================================================
  // Soltar assignment
  // ===========================================================================

  Future<void> unassign(String sessionId) async {
    final url = _colabUri('/tun/m/unassign/$sessionId');

    final getResp = await http.get(url, headers: await _headers());
    if (getResp.statusCode != 200) {
      throw Exception(_err('unassign (GET)', getResp));
    }
    final data = _parseBody(getResp);
    final xsrf = data is Map ? '${data['token'] ?? ''}' : '';

    final headers = await _headers();
    if (xsrf.isNotEmpty) headers['X-Goog-Colab-Token'] = xsrf;

    final postResp = await http.post(url, headers: headers);
    if (postResp.statusCode != 200 && postResp.statusCode != 204) {
      throw Exception(_err('unassign (POST)', postResp));
    }
  }

  // ===========================================================================
  // Keep-alive
  // ===========================================================================

  /// Keep-alive manual (un solo ping). Igual que el CLI: timeout de lectura
  /// se considera éxito (TFE registra la actividad al llegar).
  Future<bool> keepAlivePing(String endpoint) async {
    try {
      final headers = await _headers();
      headers['X-Colab-Tunnel'] = 'Google';

      final url = _colabUri('/tun/m/$endpoint/keep-alive/');
      final response =
          await http.get(url, headers: headers).timeout(ColabConfig.keepAliveTimeout);
      return response.statusCode < 400;
    } catch (_) {
      // Timeout de lectura = keep-alive exitoso según el CLI.
      return true;
    }
  }
}
