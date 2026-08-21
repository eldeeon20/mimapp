import 'dart:convert';

import 'package:http/http.dart' as http;

import 'colab_auth.dart';
import 'colab_config.dart';

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

  /// Lista sesiones activas del usuario.
  Future<List<ColabSession>> list() async {
    final token = await _auth.getToken();
    final url = Uri.parse(
      'https://${ColabConfig.colabHost}/tun/m/sessions',
    );

    final response = await http.get(url, headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode != 200) {
      throw Exception('Error listando sesiones: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
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
    final token = await _auth.getToken();
    final url = Uri.parse(
      'https://${ColabConfig.colabHost}/tun/m/$sessionId/assign',
    );

    final response = await http.post(url, headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode != 200) {
      throw Exception('Error asignando sesión: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['endpoint'] ?? data['tunnel'] ?? '';
  }

  /// Desasigna un runtime de Colab.
  Future<void> unassign(String sessionId) async {
    final token = await _auth.getToken();
    final url = Uri.parse(
      'https://${ColabConfig.colabHost}/tun/m/$sessionId/unassign',
    );

    final response = await http.post(url, headers: {
      'Authorization': 'Bearer $token',
    });

    if (response.statusCode != 200) {
      throw Exception('Error desasignando: ${response.statusCode} ${response.body}');
    }
  }

  /// Keep-alive manual (un solo ping).
  Future<bool> keepAlivePing(String endpoint) async {
    try {
      final token = await _auth.getToken();
      final url = Uri.parse(
        'https://${ColabConfig.colabHost}/tun/m/$endpoint/keep-alive/',
      );

      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'X-Colab-Tunnel': 'Google',
      }).timeout(ColabConfig.keepAliveTimeout);

      return response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }
}
