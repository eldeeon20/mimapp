import 'dart:convert';
import 'dart:io';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socks5_proxy/socks_client.dart';

import '../src/rust/api/tor.dart' as rust;

/// Tor embebido vía arti: singleton que gestiona el ciclo de vida del
/// cliente y expone el proxy SOCKS5 local para cualquier HttpClient.
/// Además trae listo el acceso por túnel para páginas comunes, descargas
/// de CDN con progreso y git smart-http (https sobre socks5h).
///
/// Nota FRB: los bindings se generan async aunque el Rust sea sync, así que
/// [refresh] consulta y cachea running/port para que los getters sean sync
/// (mismo tratamiento que el otro agente aplicó a Needle).
class TorService extends ChangeNotifier {
  TorService._();
  static final TorService instance = TorService._();

  static const host = '127.0.0.1';

  bool _busy = false;
  String _state = 'apagado';
  bool _running = false;
  int? _port;
  final _log = <String>[];

  bool get busy => _busy;
  String get state => _state;
  bool get running => _running;
  int? get port => _port;
  List<String> get log => List.unmodifiable(_log);

  /// URL de proxy para cualquier cliente que soporte SOCKS5
  /// (reqwest Rust, git smart-http, curl…). Null si Tor está apagado.
  String? get proxyUrl {
    final p = _port;
    return (_running && p != null) ? 'socks5h://$host:$p' : null;
  }

  void _say(String m) {
    debugPrint('[tor] $m');
    _log.insert(0, m);
    if (_log.length > 40) _log.removeLast();
    notifyListeners();
  }

  String? _fase;
  /// Fase del ciclo de vida reportada por Rust:
  /// apagado · bootstrap · calentando circuitos… · listo
  String get fase => _fase ?? (_running ? 'bootstrap' : 'apagado');

  /// Consulta el estado real lado Rust y actualiza la caché local.
  Future<void> refresh() async {
    try {
      _running = await rust.torIsRunning();
      _port = await rust.torSocksPort();
      _fase = await rust.torEstado();
    } catch (_) {}
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
    if (_busy || _running) return;
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
      final msg = await rust.torStart(
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
      await refresh();
    }
  }

  Future<void> stop() async {
    if (_busy) return;
    try {
      await rust.torStop();
      _state = 'apagado';
      _say('detenido');
    } catch (e) {
      _say('ERROR stop: $e');
    }
    await refresh();
  }

  Future<void> rebootstrap() async {
    if (_busy) return;
    _busy = true;
    _state = 're-bootstrapeando…';
    notifyListeners();
    try {
      await rust.torRebootstrap();
      _state = 'en marcha';
      _say('re-bootstrap ok');
    } catch (e) {
      _say('ERROR re-bootstrap: $e');
    } finally {
      _busy = false;
      await refresh();
    }
  }

  Future<void> setDormant(bool soft) async {
    try {
      await rust.torSetDormant(soft: soft);
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
  Future<String> httpGet(String url, {int reintentos = 1}) async {
    if (!_running || _port == null) throw 'Tor no está corriendo';
    final client = _tunnelClient(_port!);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      var body = await utf8.decodeStream(res);
      if (body.length > 4000) body = '${body.substring(0, 4000)}…';
      _say('GET $url → HTTP ${res.statusCode} (${body.length} B)');
      return 'HTTP ${res.statusCode}\n\n$body';
    } catch (e) {
      // circuito recién nacido: reconstruimos y probamos UNA vez más
      // antes de culpar al usuario.
      if (reintentos > 0) {
        _say('GET falló (${e.toString().split('\n').first}) · '
            'rebootstrap + reintento…');
        try { await rebootstrap(); } catch (_) {}
        await Future.delayed(const Duration(seconds: 4));
        return httpGet(url, reintentos: reintentos - 1);
      }
      throw _traducirSocks(e, 'GET $url');
    } finally {
      client.close();
    }
  }

  /// Los errores crudos del túnel (socket cortado a mitad del handshake
  /// SOCKS5) son ilegibles: los traducimos a qué hacer.
  static Object _traducirSocks(Object e, String que) {
    final s = e.toString();
    if (s.contains('fewer bytes') || s.contains('Size: 0')) {
      return 'circuito Tor cortado o bootstrap sin terminar; '
          'esperá ~10s y reintentá ($que)';
    }
    if (s.contains('Connection refused') || s.contains('refused')) {
      return 'Tor no acepta conexiones en este momento; tocá Re-bootstrap ($que)';
    }
    return e;
  }

  /// Descarga streaming a archivo POR EL CIRCUITO (CDN/HF/git smart-http),
  /// con progreso opcional [onProgress](recibido, total?). Retorna savePath.
  /// Recomendado https:// para TLS extremo a extremo sobre el túnel.
  Future<String> download(
    String url, {
    required String savePath,
    void Function(int got, int? total)? onProgress,
  }) async {
    if (!_running || _port == null) throw 'Tor no está corriendo';
    final client = _tunnelClient(_port!);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode} en $url';
      final total = res.contentLength;
      final sink = File(savePath).openWrite();
      var got = 0;
      // HttpClientResponse implementa Stream<List<int>> directamente.
      await for (final chunk in res) {
        got += chunk.length;
        sink.add(chunk);
        onProgress?.call(got, total);
      }
      await sink.flush();
      await sink.close();
      _say('descargado $url → $savePath ($got B)');
      return savePath;
    } catch (e) {
      throw _traducirSocks(e, 'descarga $url');
    } finally {
      client.close();
    }
  }
}

/// Passthrough de eventos de un socket para esperar respuestas
/// secuenciales durante el handshake SOCKS5.
class _CanalSocks {
  final Socket s;
  final _c = StreamController<List<int>>();
  StreamSubscription<List<int>>? _sub;
  _CanalSocks(this.s) {
    _sub = s.listen(_c.add, onError: _c.addError, onDone: () {});
  }
  Future<List<int>> leer({int segs = 8}) =>
      _c.stream.first.timeout(Duration(seconds: segs),
          onTimeout: () => throw 'timeout esperando al proxy');
  Future<void> soltar() async {
    await _sub?.cancel();
    _c.close();
  }
}

extension TunelCrudoTor on TorService {
  /// Abre un socket CRUDO hacia [host]:[puerto] a través del circuito,
  /// con el mismo handshake del ejemplo oficial de Foundation-Devices.
  /// Si [ssl], actualiza a TLS con SNI=[host] y devuelve el socket seguro.
  Future<SecureSocket> socketSeguroPorTor(String host, int puerto) async {
    if (!_running || _port == null) throw 'Tor no está corriendo';
    final raw = await Socket.connect(InternetAddress.loopbackIPv4, _port!);
    final canal = _CanalSocks(raw);
    try {
      // 1 · greeting: versión 5, un método, sin autenticación
      raw.add([0x05, 0x01, 0x00]);
      final saludo = await canal.leer();
      if (saludo.length < 2 || saludo[1] != 0x00) {
        throw 'SOCKS5: método rechazado por el proxy local';
      }
      // 2 · CONNECT por nombre de dominio (ATYP 0x03)
      final dom = host.codeUnits;
      raw.add([
        0x05, 0x01, 0x00, 0x03, dom.length, ...dom,
        (puerto >> 8) & 0xFF, puerto & 0xFF,
      ]);
      final conn = await canal.leer(segs: 15);
      if (conn.length < 2 || conn[1] != 0x00) {
        throw 'el circuito no pudo alcanzar $host:$puerto '
            '(código ${conn.length > 1 ? conn[1] : '?'})';
      }
      // 3 · soltar nuestro listener y entregarle el socket a TLS
      await canal.soltar();
      return SecureSocket.secure(raw, host: host);
    } catch (_) {
      await canal.soltar();
      raw.destroy();
      rethrow;
    }
  }

  /// Ping Electrum real: server.version por TLS dentro del circuito.
  /// Devuelve la primera línea que responde el nodo.
  Future<String> pingElectrum(String host, int puerto) async {
    final sec = await socketSeguroPorTor(host, puerto);
    try {
      sec.writeln(
          '{"jsonrpc":"2.0","id":"0","method":"server.version",'
          '"params":["mimapp","1.0"]}');
      final linea = await sec
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      return linea;
    } finally {
      sec.destroy();
    }
  }
}