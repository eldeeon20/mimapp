import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'colab_config.dart';

/// Datos de sesión OAuth2 persistidos.
class ColabTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiry;
  final List<String> scopes;

  ColabTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiry,
    required this.scopes,
  });

  bool get isExpired =>
      DateTime.now().isAfter(expiry.subtract(ColabConfig.tokenRefreshMargin));

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expiry': expiry.toIso8601String(),
        'scopes': scopes,
      };

  factory ColabTokens.fromJson(Map<String, dynamic> j) => ColabTokens(
        accessToken: j['access_token'] ?? '',
        refreshToken: j['refresh_token'] ?? '',
        expiry: DateTime.parse(j['expiry']),
        scopes: List<String>.from(j['scopes'] ?? []),
      );
}

/// Autenticación OAuth2 copy-paste (mismo flow que gcloud / google-colab-cli).
///
/// Flujo:
/// 1. Genera URL de autorización con redirect al landing page de Google
/// 2. Abre navegador → usuario copia el code de la landing page
/// 3. Usuario pega el code en el diálogo
/// 4. Canjea por access_token + refresh_token
/// 5. Refresca automáticamente
class ColabAuth {
  ColabTokens? _tokens;

  ColabTokens? get tokens => _tokens;
  bool get isAuthenticated => _tokens != null;

  /// Genera la URL de autorización para abrir en el navegador.
  String buildAuthUrl() {
    return '${ColabConfig.authUri}'
        '?response_type=code'
        '&client_id=${ColabConfig.clientId}'
        '&redirect_uri=${Uri.encodeComponent(ColabConfig.remoteRedirect)}'
        '&scope=${Uri.encodeComponent(ColabConfig.scopes)}'
        '&access_type=offline'
        '&prompt=consent'
        '&token_usage=remote';
  }

  /// Abre el navegador con la URL de autorización.
  /// Si no puede abrir, lanza excepción con la URL para copiar a mano.
  Future<void> openBrowser() async {
    final url = Uri.parse(buildAuthUrl());
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      throw Exception(
          'No se pudo abrir el navegador. Copiá esta URL en tu navegador:\n$url');
    }
  }

  /// Canjea el código de autorización (copiado del landing page) por tokens.
  Future<ColabTokens> exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse(ColabConfig.tokenUri),
      body: {
        'code': code.trim(),
        'client_id': ColabConfig.clientId,
        'client_secret': ColabConfig.clientSecret,
        'redirect_uri': ColabConfig.remoteRedirect,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Error canjeando código: ${response.body}');
    }

    final data = jsonDecode(response.body);
    if (data['refresh_token'] == null) {
      throw Exception('No se recibió refresh_token');
    }

    _tokens = ColabTokens(
      accessToken: data['access_token'],
      refreshToken: data['refresh_token'],
      expiry: DateTime.now()
          .add(Duration(seconds: data['expires_in'] ?? 3600)),
      scopes: (data['scope'] as String?)?.split(' ') ?? [],
    );
    await _saveTokens();
    return _tokens!;
  }

  /// Refresca el access_token usando el refresh_token.
  Future<ColabTokens> refreshToken() async {
    if (_tokens == null) throw StateError('No hay tokens para refrescar');

    final response = await http.post(
      Uri.parse(ColabConfig.tokenUri),
      body: {
        'refresh_token': _tokens!.refreshToken,
        'client_id': ColabConfig.clientId,
        'client_secret': ColabConfig.clientSecret,
        'grant_type': 'refresh_token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Error refrescando token: ${response.body}');
    }

    final data = jsonDecode(response.body);
    _tokens = ColabTokens(
      accessToken: data['access_token'],
      refreshToken: _tokens!.refreshToken,
      expiry: DateTime.now()
          .add(Duration(seconds: data['expires_in'] ?? 3600)),
      scopes: _tokens!.scopes,
    );
    await _saveTokens();
    return _tokens!;
  }

  /// Retorna access_token vigente; refresca si expiró.
  Future<String> getToken() async {
    if (_tokens == null) throw StateError('No autenticado');
    if (_tokens!.isExpired) {
      await refreshToken();
    }
    return _tokens!.accessToken;
  }

  /// Headers estándar para llamadas a Colab.
  Future<Map<String, String>> authHeaders() async {
    final token = await getToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'X-Colab-Client-Agent': 'colab-cli',
    };
  }

  /// Carga tokens desde disco (si existen).
  Future<bool> loadTokens() async {
    try {
      final file = File('${await _configDir}/colab_tokens.json');
      if (!await file.exists()) return false;
      final data = jsonDecode(await file.readAsString());
      _tokens = ColabTokens.fromJson(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Guarda tokens en disco.
  Future<void> _saveTokens() async {
    if (_tokens == null) return;
    final dir = Directory(await _configDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/colab_tokens.json');
    await file.writeAsString(jsonEncode(_tokens!.toJson()));
  }

  /// Borra tokens (logout).
  Future<void> logout() async {
    _tokens = null;
    final file = File('${await _configDir}/colab_tokens.json');
    if (await file.exists()) await file.delete();
  }

  Future<String> get _configDir async {
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/colab';
  }
}
