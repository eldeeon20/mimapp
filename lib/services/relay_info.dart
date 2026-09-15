import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Resultado de revisar UN relay: documento NIP-11 + latencia real.
/// Sin pasar por usuarios: directo contra el relay.
class RelayCheck {
  /// URL normalizada (wss://…).
  final String url;
  final String nombre;
  final String descripcion;
  final String contacto;
  final String software;
  final String version;
  final List<int> nips;
  final bool limitado;
  final bool conPago;

  /// ms del apretón WebSocket. -1 = no conecta.
  final int latenciaMs;

  /// '' = todo bien; si no, el motivo.
  final String error;

  bool get ok => error.isEmpty && latenciaMs >= 0;

  const RelayCheck({
    required this.url,
    this.nombre = '',
    this.descripcion = '',
    this.contacto = '',
    this.software = '',
    this.version = '',
    this.nips = const [],
    this.limitado = false,
    this.conPago = false,
    this.latenciaMs = -1,
    this.error = '',
  });
}

/// Directorio público de relays (api.nostr.watch/v1/online): para
/// descubrir relays que NO tenés. Sin lista local: si la API falla,
/// vuelve vacío (se muestra el error).
class RelayDirectorio {
  /// URLs online ahora mismo. Vacía si la API no responde.
  static Future<List<String>> cargar() async {
    try {
      final res = await http
          .get(Uri.parse('https://api.nostr.watch/v1/online'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        if (j is List) {
          final out = {
            for (final e in j)
              if (e is String && e.trim().isNotEmpty)
                RelayInfo.normalizar(e.trim()),
          }.where((u) => u.isNotEmpty).toList()
            ..sort();
          if (out.isNotEmpty) return out;
        }
      }
    } catch (_) {}
    return [];
  }
}

/// Revisa un relay solo: NIP-11 (https + Accept) + latencia (WebSocket).
class RelayInfo {
  /// Normaliza a wss://host[/ruta] (acepta host pelado, ws://, http://).
  static String normalizar(String crudo) {
    var u = crudo.trim();
    if (u.isEmpty) return '';
    if (!u.contains('://')) u = 'wss://$u';
    u = u.replaceFirst(RegExp(r'^ws://'), 'wss://');
    u = u.replaceFirst(RegExp(r'^http://'), 'https://');
    u = u.replaceFirst(RegExp(r'^https://'), 'wss://');
    // saca barra final (pero no la raíz con ruta)
    while (u.endsWith('/') && u.length > 8) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// wss://host[/ruta] → https://host[/ruta] para pedir el NIP-11.
  static String aHttps(String wss) =>
      wss.replaceFirst(RegExp(r'^wss://'), 'https://');

  /// Revisa un relay: NIP-11 + apretón WebSocket con cronómetro.
  static Future<RelayCheck> revisar(String crudo,
      {int timeoutSecs = 8}) async {
    final url = normalizar(crudo);
    if (url.isEmpty) {
      return const RelayCheck(url: '', error: 'url vacía');
    }
    String nombre = '';
    String descripcion = '';
    String contacto = '';
    String software = '';
    String version = '';
    List<int> nips = const [];
    var limitado = false;
    var conPago = false;
    try {
      final res = await http
          .get(Uri.parse(aHttps(url)),
              headers: {'Accept': 'application/nostr+json'})
          .timeout(Duration(seconds: timeoutSecs));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body);
        if (j is Map) {
          nombre = '${j['name'] ?? ''}';
          descripcion = '${j['description'] ?? ''}';
          contacto = '${j['contact'] ?? ''}';
          software = '${j['software'] ?? ''}';
          version = '${j['version'] ?? ''}';
          final sn = j['supported_nips'];
          if (sn is List) {
            nips = [
              for (final e in sn)
                if (e is num) e.toInt()
            ];
          }
          final lim = j['limitation'];
          if (lim is Map) {
            limitado = lim['auth_required'] == true;
            conPago = lim['payment_required'] == true;
          }
          if (j['fees'] is Map &&
              (j['fees'] as Map).isNotEmpty) {
            conPago = true;
          }
        }
      }
    } catch (_) {
      // sin NIP-11 igual se prueba el WebSocket abajo
    }
    var ms = -1;
    try {
      final t0 = DateTime.now();
      final ws = await WebSocket.connect(url)
          .timeout(Duration(seconds: timeoutSecs));
      ms = DateTime.now().difference(t0).inMilliseconds;
      try {
        await ws.close();
      } catch (_) {}
    } catch (e) {
      final detalle = '$e'.length > 120
          ? '${'$e'.substring(0, 120)}…'
          : '$e';
      return RelayCheck(
        url: url,
        nombre: nombre,
        descripcion: descripcion,
        contacto: contacto,
        software: software,
        version: version,
        nips: nips,
        limitado: limitado,
        conPago: conPago,
        latenciaMs: -1,
        error: 'no conecta: $detalle',
      );
    }
    return RelayCheck(
      url: url,
      nombre: nombre,
      descripcion: descripcion,
      contacto: contacto,
      software: software,
      version: version,
      nips: nips,
      limitado: limitado,
      conPago: conPago,
      latenciaMs: ms,
    );
  }
}
