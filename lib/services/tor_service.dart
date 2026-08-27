import 'dart:convert';
import 'dart:io';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
  final _log = <String>[];

  bool get busy => _busy;
  String get state => _state;
  bool get running => _running;
  List<String> get log => List.unmodifiable(_log);

  /// Sin puente local: el HTTP sale directo por arti desde Rust.
  String? get proxyUrl => null;

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
      _fase = await rust.torEstado();
    } catch (_) {}
    notifyListeners();
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

      // Llamada bloqueante de varios segundos (corre en hilo Rust).
      final msg =
          await rust.torStart(stateDir: stateDir.path, cacheDir: cacheDir.path);
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

  /// GET HTTP(S) DIRECTO por arti desde Rust (sin puente local).
  /// Sirve para páginas comunes, APIs y .onion.
  Future<String> httpGet(String url, {int reintentos = 1}) async {
    if (!_running) throw 'Tor no está corriendo';
    try {
      final r = await rust.torHttpGet(url: url);
      _say('GET $url OK');
      return r;
    } catch (e) {
      if (reintentos > 0 && _fase != 'listo') {
        _say('GET esperando red (${e.toString().split('\n').first})…');
        try { await rebootstrap(); } catch (_) {}
        await Future.delayed(const Duration(seconds: 4));
        return httpGet(url, reintentos: reintentos - 1);
      }
      throw e;
    }
  }

  Future<String> download(
    String url, {
    required String savePath,
    void Function(int got, int? total)? onProgress,
  }) async {
    if (!_running) throw 'Tor no está corriendo';
    try {
      final n = await rust.torDownload(url: url, destPath: savePath);
      onProgress?.call(n.toInt(), n.toInt());
      _say('descargado $url → $savePath ($n B)');
      return savePath;
    } catch (e) {
      rethrow;
    }
  }
}

extension PingCrudoTor on TorService {
  /// Conectividad cruda por el circuito hacia host:puerto (sin HTTP).
  Future<String> tcpPing(String host, int puerto) =>
      rust.torTcpPing(host: host, puerto: puerto);
}
