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

/// Autenticación OAuth2 con loopback: la app abre un servidor local,
/// el navegador del mismo dispositivo redirige a 127.0.0.1 y el código
/// se captura solo (sin copiar ni pegar).
class ColabAuth {
  ColabTokens? _tokens;
  HttpServer? _loopbackServer;

  ColabTokens? get tokens => _tokens;
  bool get isAuthenticated => _tokens != null;

  /// Genera la URL de autorización para un redirect loopback dado.
  String buildAuthUrl(String redirectUri) {
    return '${ColabConfig.authUri}'
        '?response_type=code'
        '&client_id=${ColabConfig.clientId}'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&scope=${Uri.encodeComponent(ColabConfig.scopes)}'
        '&access_type=offline'
        '&prompt=consent';
  }

  /// Flujo interactivo completo:
  /// 1. Abre servidor local en puerto aleatorio
  /// 2. Abre el navegador con redirect a 127.0.0.1
  /// 3. Captura el código automáticamente y canjea por tokens
  Future<ColabTokens> signInInteractive({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    await stopInteractive();

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _loopbackServer = server;
    final redirect = 'http://${ColabConfig.redirectHost}:${server.port}';

    final url = Uri.parse(buildAuthUrl(redirect));
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Si no puede abrir el navegador, igual esperamos:
      // el usuario puede abrir la URL a mano en el mismo equipo.
    }

    try {
      final request = await server.first.timeout(timeout);
      final params = request.uri.queryParameters;

      final ok = params.containsKey('code');
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '</head><body style="font-family:sans-serif;text-align:center;'
        'padding-top:60px;background:#020617;color:#fff">'
        '<h2>${ok ? '✅ Autenticado' : '❌ Error'}</h2>'
        '<p>${ok ? 'Podés cerrar esta pestaña y volver a la app.'
                : 'Google devolvió: ${params['error'] ?? 'sin código'}'}</p>'
        '</body></html>',
      );
      await request.response.close();

      if (!ok) {
        throw Exception(
            'Google devolvió error: ${params['error'] ?? 'sin código'}');
      }
      return await exchangeCode(params['code']!, redirect);
    } finally {
      await stopInteractive();
    }
  }

  /// Cierra el servidor loopback si está abierto.
  Future<void> stopInteractive() async {
    final s = _loopbackServer;
    _loopbackServer = null;
    await s?.close(force: true);
  }

  /// Canjea el código de autorización por tokens.
  /// El [redirectUri] debe ser exactamente el mismo que en la URL de auth.
  Future<ColabTokens> exchangeCode(String code, String redirectUri) async {
    final response = await http.post(
      Uri.parse(ColabConfig.tokenUri),
      body: {
        'code': code.trim(),
        'client_id': ColabConfig.clientId,
        'client_secret': ColabConfig.clientSecret,
        'redirect_uri': redirectUri,
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
