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

/// Autenticación OAuth2 loopback (RFC 8252) contra Google Colab.
///
/// Flujo:
/// 1. Abre servidor HTTP en 127.0.0.1:8737
/// 2. Abre navegador en URL de autorización
/// 3. Captura el código de autorización
/// 4. Canjea por access_token + refresh_token
/// 5. Refresca automáticamente
class ColabAuth {
  ColabTokens? _tokens;

  ColabTokens? get tokens => _tokens;
  bool get isAuthenticated => _tokens != null;

  /// Abre navegador y completa el flujo OAuth2.
  /// Retorna los tokens si todo salió bien.
  Future<ColabTokens> authenticate() async {
    final state = _randomState();

    // Iniciar servidor local ANTES de abrir navegador
    final server = await HttpServer.bind('127.0.0.1', 8737);
    final codeFuture = _waitForCode(server, state);

    // Abrir navegador con URL de autorización
    final authUrl = Uri.parse(
      '${ColabConfig.authUri}'
      '?response_type=code'
      '&client_id=${ColabConfig.clientId}'
      '&redirect_uri=${Uri.encodeComponent(ColabConfig.redirect)}'
      '&scope=${Uri.encodeComponent(ColabConfig.scopes)}'
      '&access_type=offline'
      '&prompt=consent'
      '&state=$state',
    );

    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    }

    final code = await codeFuture;

    // Canjear código por tokens
    final tokenData = await _exchangeCode(code);
    _tokens = ColabTokens.fromJson(tokenData);
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
      expiry: DateTime.now().add(Duration(seconds: data['expires_in'] ?? 3600)),
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
    final dir = Directory('${await _configDir}');
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

  // --- Internos ---

  Future<String> get _configDir async {
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/colab';
  }

  String _randomState() {
    final random = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$random${random.hashCode.toRadixString(36)}';
  }

  /// Espera UNA request del navegador en el servidor local.
  Future<String> _waitForCode(HttpServer server, String expectedState) async {
    final completer = Completer<String>();

    server.timeout(const Duration(minutes: 5), onTimeout: (_) {
      server.close();
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('Tiempo agotado esperando autorización'));
      }
    });

    server.listen((request) {
      final code = request.uri.queryParameters['code'];
      final state = request.uri.queryParameters['state'];

      // Responder al navegador
      request.response.headers.contentType = ContentType.html;
      if (code != null && state == expectedState) {
        request.response.write('<html><body><h2>Autenticado.</h2>'
            '<p>Cerrá esta ventana.</p></body></html>');
        request.response.close();
        server.close();
        if (!completer.isCompleted) completer.complete(code);
      } else {
        request.response.write('<html><body><h2>Error</h2>'
            '<p>${state != expectedState ? 'State inválido' : 'Código faltante'}</p>'
            '</body></html>');
        request.response.close();
        server.close();
        if (!completer.isCompleted) {
          completer.completeError(Exception('State mismatch o código faltante'));
        }
      }
    });

    return completer.future;
  }

  /// Canjea código de autorización por tokens.
  Future<Map<String, dynamic>> _exchangeCode(String code) async {
    final response = await http.post(
      Uri.parse(ColabConfig.tokenUri),
      body: {
        'code': code,
        'client_id': ColabConfig.clientId,
        'client_secret': ColabConfig.clientSecret,
        'redirect_uri': ColabConfig.redirect,
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

    return {
      'access_token': data['access_token'],
      'refresh_token': data['refresh_token'],
      'expiry': DateTime.now()
          .add(Duration(seconds: data['expires_in'] ?? 3600))
          .toIso8601String(),
      'scopes': (data['scope'] as String?)?.split(' ') ?? [],
    };
  }
}
