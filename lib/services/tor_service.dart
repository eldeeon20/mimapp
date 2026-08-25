import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socks5_proxy/socks_client.dart';

import '../src/rust/api/tor.dart' as rust;

/// Tor embebido vía arti: singleton que gestiona el ciclo de vida del
/// cliente y expone el proxy SOCKS5 local para cualquier HttpClient.
/// Además trae listo el acceso por túnel para páginas comunes, descargas
/// de CDN con progreso y git smart-http (https sobre socks5h).
class TorService extends ChangeNotifier {
  TorService._();
  static final TorService instance = TorService._();

  static const host = '127.0.0.1';

  bool _busy = false;
  String _state = 'apagado';
  final _log = <String>[];

  bool get busy => _busy;
  String get state => _state;
  List<String> get log => List.unmodifiable(_log);

  int? get port => rust.torSocksPort();
  bool get running => rust.torIsRunning();

  /// URL de proxy para cualquier cliente que soporte SOCKS5
  /// (reqwest Rust, git smart-http, curl…). Null si Tor está apagado.
  String? get proxyUrl {
    final p = port;
    return (p == null) ? null : 'socks5h://$host:$p';
  }

  void _say(String m) {
    debugPrint('[tor] $m');
    _log.insert(0, m);
    if (_log.length > 40) _log.removeLast();
    notifyListeners();
  }

  /// Puerto libre al azar (patrón del plugin Foundation).
  Future<int> _freePort() async {
    final s = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  Future<void> start() async {
    if (_busy || running) return;
    _busy = true;
    _state = 'bootstrapeando…';
    notifyListeners();
    try {
      final support = await getApplicationSupportDirectory();
      final stateDir = Directory('${support.path}/tor_state');
      final cacheDir = Directory('${support.path}/tor_cache');
      if (!stateDir.existsSync()) stateDir.createSync(recursive: true);
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);

      final port = await _freePort();
      // Llamada bloqueante de varios segundos (corre en hilo Rust).
      final msg = rust.torStart(
          socksPort: port,
          stateDir: stateDir.path,
          cacheDir: cacheDir.path);
      _state = 'en marcha · $msg';
      _say(msg);
    } catch (e) {
      _state = 'error';
      _say('ERROR: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (_busy) return;
    try {
      rust.torStop();
      _state = 'apagado';
      _say('detenido');
    } catch (e) {
      _say('ERROR stop: $e');
    }
    notifyListeners();
  }

  Future<void> rebootstrap() async {
    if (_busy) return;
    _busy = true;
    _state = 're-bootstrapeando…';
    notifyListeners();
    try {
      rust.torRebootstrap();
      _state = 'en marcha';
      _say('re-bootstrap ok');
    } catch (e) {
      _say('ERROR re-bootstrap: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> setDormant(bool soft) async {
    try {
      rust.torSetDormant(soft: soft);
      _say(soft ? 'modo dormante soft' : 'modo normal');
    } catch (e) {
      _say('ERROR dormant: $e');
    }
  }

  /// Cliente HttpClient ya enchufado al SOCKS5 local (patrón example).
  HttpClient _tunnelClient(int p) {
    final c = HttpClient();
    SocksTCPClient.assignToHttpClient(c, [
      ProxySettings(InternetAddress.loopbackIPv4, p),
    ]);
    return c;
  }

  /// GET HTTP(S) por el circuito: HttpClient común + SOCKS5 local.
  /// Sirve para páginas comunes (duckduckgo, check.torproject.org) y .onion.
  Future<String> httpGet(String url) async {
    final p = port;
    if (p == null) throw 'Tor no está corriendo';
    final client = _tunnelClient(p);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      var body = await utf8.decodeStream(res);
      if (body.length > 4000) body = '${body.substring(0, 4000)}…';
      _say('GET $url → HTTP ${res.statusCode} (${body.length} B)');
      return 'HTTP ${res.statusCode}\n\n$body';
    } finally {
      client.close();
    }
  }

  /// Descarga streaming a archivo POR EL CIRCUITO (CDN/HF/git smart-http),
  /// con progreso opcional [onProgress](recibido, total?). Retorna savePath.
  /// Recomendado https:// para TLS extremo a extremo sobre el túnel.
  Future<String> download(
    String url, {
    required String savePath,
    void Function(int got, int? total)? onProgress,
  }) async {
    final p = port;
    if (p == null) throw 'Tor no está corriendo';
    final client = _tunnelClient(p);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode} en $url';
      final total = res.contentLength;
      final sink = File(savePath).openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        got += chunk.length;
        sink.add(chunk);
        onProgress?.call(got, total);
      }
      await sink.flush();
      await sink.close();
      _say('descargado $url → $savePath ($got B)');
      return savePath;
    } finally {
      client.close();
    }
  }
}
