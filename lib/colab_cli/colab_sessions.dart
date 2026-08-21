import 'dart:convert';

import 'package:http/http.dart' as http;

import 'colab_auth.dart';
import 'colab_config.dart';

/// Prefijo XSSI que Google antepone a las respuestas JSON.
const _xssiPrefix = ")]}'\n";

/// Sesión de Colab activa.
class ColabSession {
  final String endpoint;
  final String? name;
  final DateTime createdAt;

  ColabSession({
    required this.endpoint,
    this.name,
    required this.createdAt,
  });

  factory ColabSession.fromJson(Map<String, dynamic> j) => ColabSession(
        endpoint: j['endpoint'] ?? '',
        name: j['name'],
        createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'name': name,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Gestión de sesiones de Colab: listar, asignar, desasignar.
class ColabSessions {
  final ColabAuth _auth;

  ColabSessions(this._auth);

  /// Strips XSSI prefix y parsea JSON.
  dynamic _parseResponse(http.Response r) {
    var body = r.body;
    if (body.startsWith(_xssiPrefix)) {
      body = body.substring(_xssiPrefix.length);
    }
    return jsonDecode(body);
  }

  /// Headers estándar con authuser=0.
  Future<Map<String, String>> _headers() async {
    return _auth.authHeaders();
  }

  Uri _colabUri(String path, [Map<String, String>? extraQuery]) {
    final params = {'authuser': '0'};
    if (extraQuery != null) params.addAll(extraQuery);
    return Uri.https(ColabConfig.colabHost, path, params);
  }

  /// Lista sesiones activas del usuario.
  Future<List<ColabSession>> list() async {
    final url = _colabUri('/tun/m/sessions');
    final response = await http.get(url, headers: await _headers());

    if (response.statusCode != 200) {
      throw Exception(
          'Error listando sesiones: ${response.statusCode} ${response.body}');
    }

    final data = _parseResponse(response);
    final sessions = <ColabSession>[];

    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          sessions.add(ColabSession.fromJson(item));
        }
      }
    } else if (data is Map<String, dynamic> && data.containsKey('sessions')) {
      for (final item in data['sessions'] as List) {
        if (item is Map<String, dynamic>) {
          sessions.add(ColabSession.fromJson(item));
        }
      }
    }

    return sessions;
  }

  /// Asigna un runtime de Colab.
  Future<String> assign(String sessionId) async {
    final url = _colabUri('/tun/m/$sessionId/assign');

    // Primero GET para obtener XSRF token
    final getResp = await http.get(url, headers: await _headers());
    final getXsrf = _parseResponse(getResp);
    final xsrfToken = getXsrf is Map ? getXsrf['token'] ?? '' : '';

    // Luego POST con XSRF token
    final headers = await _headers();
    if (xsrfToken.isNotEmpty) {
      headers['X-Goog-Colab-Token'] = xsrfToken;
    }

    final postResp = await http.post(url, headers: headers);

    if (postResp.statusCode == 412) {
      throw Exception('Demasiadas asignaciones activas');
    }
    if (postResp.statusCode != 200) {
      throw Exception(
          'Error asignando sesión: ${postResp.statusCode} ${postResp.body}');
    }

    final data = _parseResponse(postResp);
    return data['endpoint'] ?? data['tunnel'] ?? '';
  }

  /// Desasigna un runtime de Colab.
  Future<void> unassign(String sessionId) async {
    final url = _colabUri('/tun/m/$sessionId/unassign');

    final getResp = await http.get(url, headers: await _headers());
    final getXsrf = _parseResponse(getResp);
    final xsrfToken = getXsrf is Map ? getXsrf['token'] ?? '' : '';

    final headers = await _headers();
    if (xsrfToken.isNotEmpty) {
      headers['X-Goog-Colab-Token'] = xsrfToken;
    }

    final postResp = await http.post(url, headers: headers);

    if (postResp.statusCode != 200) {
      throw Exception(
          'Error desasignando: ${postResp.statusCode} ${postResp.body}');
    }
  }

  /// Keep-alive manual (un solo ping).
  Future<bool> keepAlivePing(String endpoint) async {
    try {
      final headers = await _headers();
      headers['X-Colab-Tunnel'] = 'Google';

      final url = _colabUri('/tun/m/$endpoint/keep-alive/');
      final response =
          await http.get(url, headers: headers).timeout(ColabConfig.keepAliveTimeout);

      return response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }
}
