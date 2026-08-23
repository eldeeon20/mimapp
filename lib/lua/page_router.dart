import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../services/history_store.dart';
import '../../src/rust/api/nostr_page.dart' as rust;
import 'page_registry.dart';

/// Resultado de resolver una página: el código Lua crudo + su uri origen.
class PageSource {
  final String uri;
  final String code;
  PageSource({required this.uri, required this.code});
}

/// Mini router/handle de páginas: TODA petición pasa por acá y se enruta
/// por scheme. Plug-and-play: un transporte nuevo es una rama nueva.
///
///   lua://nombre / nombre / local:  → assets (páginas en caliente)
///   http(s)://                      → red
///   tcp://host:port/ruta            → socket crudo
///   udp://host:port                 → datagrama request/response
///   nostrn://npub/nombre            → evento NIP-23 (kind 30023, tag d=nombre)
///   magnet: / torrent:              → STUB (futura porte de Gtool)
class PageRouter {
  static final PageRouter instance = PageRouter._();

  PageRouter._();

  /// Caché LRU simple (uri -> código). Cap para no crecer infinito.
  final Map<String, String> _cache = {};
  static const _cap = 32;

  /// Relays Nostr usados por el transporte nostrn://. Vacío = defaults
  /// del lado Rust. Configurable desde Lua/UI en caliente.
  List<String> nostrRelays = [];

  /// Catálogo de recomendados desde el registro de páginas.
  List<Map<String, String>> recommended() => PageRegistryMeta.recommended();

  /// Resuelve un uri a código Lua. Lanza Exception con mensaje legible.
  Future<PageSource> resolve(String rawUri) async {
    final uri = rawUri.trim();
    if (uri.isEmpty) throw Exception('Uri vacía');

    final cached = _cache[uri];
    if (cached != null) {
      await HistoryStore.instance.add(uri, title: titleOf(cached));
      return PageSource(uri: uri, code: cached);
    }

    final lower = uri.toLowerCase();
    final PageSource src;
    if (lower.startsWith('magnet:') || lower.startsWith('torrent:')) {
      throw Exception(
          'Transporte torrent aún no disponible (stub del router)');
    } else if (lower.startsWith('tcp://')) {
      src = await _viaTcp(uri);
    } else if (lower.startsWith('udp://')) {
      src = await _viaUdp(uri);
    } else if (lower.startsWith('nostrn://') ||
        lower.startsWith('nostr://')) {
      src = await _viaNostr(uri);
    } else if (lower.startsWith('http://') ||
        lower.startsWith('https://')) {
      src = await _viaHttp(uri);
    } else {
      src = await _viaLocal(_stripLocal(uri));
    }

    _cache[uri] = src.code;
    if (_cache.length > _cap) {
      _cache.remove(_cache.keys.first);
    }
    return src;
  }

  // ------------------------------------------------------------ transportes

  Future<PageSource> _viaLocal(String name) async {
    final asset = PageRegistry.assetPath(name);
    if (asset == null) {
      throw Exception('Página local desconocida: "$name"');
    }
    final code = await rootBundle.loadString(asset);
    await HistoryStore.instance.add('lua://$name', title: titleOf(code));
    return PageSource(uri: 'lua://$name', code: code);
  }

  Future<PageSource> _viaHttp(String url) async {
    final res = await http.get(Uri.parse(_normalizeGithub(url)));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} al cargar $url');
    }
    final code = utf8.decode(res.bodyBytes);
    await HistoryStore.instance.add(url, title: titleOf(code));
    return PageSource(uri: url, code: code);
  }

  Future<PageSource> _viaTcp(String uri) async {
    final m = RegExp(r'^tcp://([^/:]+):(\d+)(/.*)?$').firstMatch(uri);
    if (m == null) throw Exception('tcp uri inválida: $uri');
    final host = m.group(1)!;
    final port = int.parse(m.group(2)!);
    final path = m.group(3) ?? '/';

    final socket = await Socket.connect(host, port,
        timeout: const Duration(seconds: 5));
    final completer = CompleterCompat();
    socket.listen(completer.addData, onDone: completer.close,
        onError: completer.fail);
    socket.write('GET $path\n');
    final data = await completer.future
        .timeout(const Duration(seconds: 8));
    socket.destroy();
    final code = utf8.decode(data, allowMalformed: true);
    await HistoryStore.instance.add(uri, title: titleOf(code));
    return PageSource(uri: uri, code: code);
  }

  Future<PageSource> _viaUdp(String uri) async {
    final m = RegExp(r'^udp://([^/:]+):(\d+)$').firstMatch(uri);
    if (m == null) throw Exception('udp uri inválida: $uri');
    final host = m.group(1)!;
    final port = int.parse(m.group(2)!);

    final socket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.send(utf8.encode('GET\n'), InternetAddress(host), port);
    final completer = CompleterCompat();
    Timer(const Duration(seconds: 5), () => completer.close());
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket.receive();
        if (dg != null) completer.addData(dg.data);
      }
    });
    final data = await completer.future;
    socket.close();
    final code = utf8.decode(data, allowMalformed: true);
    await HistoryStore.instance.add(uri, title: titleOf(code));
    return PageSource(uri: uri, code: code);
  }

  Future<PageSource> _viaNostr(String uri) async {
    final m =
        RegExp(r'^(?:nostrn|nostr)://([^/]+)/(.+)$').firstMatch(uri);
    if (m == null) throw Exception('nostrn uri inválida: $uri');
    final code = await rust.nostrPageFetch(
      npubOrHex: m.group(1)!,
      name: m.group(2)!,
      relays: nostrRelays.isEmpty ? null : nostrRelays,
    );
    await HistoryStore.instance.add(uri, title: titleOf(code));
    return PageSource(uri: uri, code: code);
  }

  // ---------------------------------------------------------------- helpers

  String _stripLocal(String uri) {
    var u = uri;
    for (final p in ['lua://', 'local:', '/']) {
      if (u.toLowerCase().startsWith(p)) u = u.substring(p.length);
    }
    return u.trim();
  }

  String _normalizeGithub(String url) {
    final match = RegExp(
      r'^https?://github\.com/([^/]+/[^/]+)/(blob|raw)/(.+)$',
    ).firstMatch(url);
    if (match == null) return url;
    return 'https://raw.githubusercontent.com/${match.group(1)}/${match.group(3)}';
  }

  /// Título heurístico desde el primer comentario del script.
  static String titleOf(String code) {
    for (final line in code.split('\n')) {
      final t = line.trim();
      if (t.startsWith('--')) {
        return t.replaceFirst(RegExp(r'^--+\s*'), '').trim();
      }
      if (t.isNotEmpty && !t.startsWith('--')) break;
    }
    return 'página';
  }
}

/// Acumulador mínimo de bytes para los transports de sockets.
class CompleterCompat {
  final _c = Completer<List<int>>();
  final _buf = BytesBuilder();

  void addData(List<int> chunk) => _buf.add(chunk);
  void close() {
    if (!_c.isCompleted) _c.complete(_buf.toBytes());
  }

  void fail(Object e) {
    if (!_c.isCompleted) _c.completeError(e);
  }

  Future<List<int>> get future => _c.future;
}
