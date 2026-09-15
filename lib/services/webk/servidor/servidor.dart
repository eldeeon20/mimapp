import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../paginas/indice.dart';
import 'reto.dart';

/// Servidor HTTP local de WebK (web criptográfica).
///
/// - Escucha SOLO en loopback (127.0.0.1, puerto aleatorio): de afuera
///   no se llega ni a ver el puerto.
/// - Sordo por defecto: sin señal previa de la app responde 403 y cierra,
///   sin banner ni info (el que sondea no saca nada).
/// - [autorizarUna] es LA señal desde la app: habilita UNA sola conexión;
///   se consume al usarse.
/// - El html real NUNCA se sirve directo: cada conexión autorizada recibe
///   primero el js de prueba (reto). El js responde el ping con
///   {nonce, llave, fecha}:
///   - sin respuesta en [_retoSegs] → el pendiente se borra (conexión
///     cortada) y cuenta en [retosCaidos];
///   - con respuesta válida (llave de sesión de la app + fecha fresca) →
///     el server da un pase de una sola vez y recién ahí manda el html+js.
///   - Chrome no tiene la llave (solo la app la inyecta en SU WebView) →
///     su ping es DENEGADO y el html jamás sale.
class WebkServer {
  HttpServer? _srv;
  WebkResolvedor? resolvedor;

  bool _autorizado = false;

  /// Llave de sesión: la app la genera al iniciar y la inyecta en SU
  /// WebView (Dart→JS). El ping del reto solo vale con esta llave.
  String llaveSesion = '';

  int servidas = 0;
  int rechazadas = 0;
  int retosCaidos = 0;
  int get retosActivos => _retos.length;

  final _retos = <String, RetoPendiente>{};
  final _pases = <String, PaseUnico>{};
  final _rnd = Random.secure();

  /// Segundos que el server espera el ping antes de cortar el reto.
  static const _retoSegs = 10;

  /// Vida del pase de una sola vez (se quema al usarse).
  static const _paseSegs = 60;

  /// Tolerancia del ping-fecha (ms): |ahora - fecha| mayor → DENEGADO.
  static const _sesgoFechaMs = 30000;

  bool get corriendo => _srv != null;
  int get puerto => _srv?.port ?? 0;
  String get baseUrl =>
      corriendo ? 'http://127.0.0.1:$puerto' : '';

  /// Levanta el servidor (cierra el anterior si había).
  Future<int> iniciar() async {
    await detener();
    _srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _srv!.listen(_atender);
    return _srv!.port;
  }

  /// Señal desde la app: autoriza UNA conexión. Se consume al usarse.
  void autorizarUna() {
    _autorizado = true;
  }

  /// Emite un pase directo para [pagina] (lo pide Dart tras verificar la
  /// llave del puente JS→Dart). Para composición interna: una página ya
  /// cargada incrusta otra por iframe o fetch sin pasar el reto de nuevo.
  /// El pase se quema al usarse (o al vencer).
  String emitirPase(String pagina) {
    final pase = _token();
    _pases[pase] = PaseUnico(
      pagina,
      DateTime.now().add(const Duration(seconds: _paseSegs)),
    );
    Timer(const Duration(seconds: _paseSegs), () => _pases.remove(pase));
    return pase;
  }

  String _token() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    final hex =
        b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '$hex${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
  }

  Future<void> _responder(
    HttpRequest req,
    int codigo,
    Uint8List bytes,
    String mime,
  ) async {
    try {
      req.response.statusCode = codigo;
      req.response.headers.contentType = ContentType.parse(mime);
      req.response.headers.contentLength = bytes.length;
      req.response.add(bytes);
      await req.response.close();
    } catch (_) {}
  }

  Future<void> _cerrar(HttpRequest req, int codigo) async {
    try {
      req.response.statusCode = codigo;
      await req.response.close();
    } catch (_) {}
  }

  Future<void> _atender(HttpRequest req) async {
    final ruta = req.uri.path;

    // Ping del reto: se valida solo (nonce+llave+fecha), no consume señal.
    if (ruta == kRutaPing && req.method == 'POST') {
      await _atenderPing(req);
      return;
    }

    // Pase de un ping ya respondido: ÉL es la señal, no consume otra.
    final pase = req.uri.queryParameters['pase'] ?? '';
    if (pase.isNotEmpty && _usarPase(pase, ruta)) {
      await _servirReal(req, ruta);
      return;
    }

    if (!_autorizado) {
      rechazadas++;
      await _cerrar(req, HttpStatus.forbidden);
      return;
    }
    _autorizado = false; // una sola conexión: se consume acá

    // El html NO sale directo: se manda el js de prueba y se espera el ping.
    final nonce = _token();
    _retos[nonce] = RetoPendiente(
      ruta,
      DateTime.now().add(const Duration(seconds: _retoSegs)),
    );
    Timer(const Duration(seconds: _retoSegs), () {
      if (_retos.remove(nonce) != null) retosCaidos++; // sin ping: se corta
    });
    await _responder(
      req,
      HttpStatus.ok,
      Uint8List.fromList(utf8.encode(construirReto(nonce, ruta))),
      'text/html; charset=utf-8',
    );
  }

  /// Sirve la página real (solo llega acá con pase válido de un ping).
  Future<void> _servirReal(HttpRequest req, String ruta) async {
    try {
      final pagina = await resolvedor?.call(ruta);
      if (pagina == null) {
        await _cerrar(req, HttpStatus.notFound);
        return;
      }
      servidas++;
      await _responder(req, HttpStatus.ok, pagina.bytes, pagina.mime);
    } catch (_) {
      await _cerrar(req, HttpStatus.internalServerError);
    }
  }

  /// ¿El pase vale para esta ruta? Se quema al usarse (una sola vez).
  bool _usarPase(String pase, String ruta) {
    final p = _pases.remove(pase);
    if (p == null || p.vencido) return false;
    return _normalizar(p.pagina) == _normalizar(ruta);
  }

  static String _normalizar(String ruta) {
    var n = ruta.trim();
    while (n.startsWith('/')) {
      n = n.substring(1);
    }
    return n;
  }

  /// Ping del reto {nonce, llave, fecha}: responde {ok, pase} o DENEGADO.
  Future<void> _atenderPing(HttpRequest req) async {
    Future<void> negar(String error) async {
      rechazadas++;
      await _responder(
        req,
        HttpStatus.forbidden,
        pingJson(false, error: error),
        'application/json; charset=utf-8',
      );
    }

    Map<String, dynamic> cuerpo;
    try {
      final texto = await utf8.decoder.bind(req).join();
      final v = jsonDecode(texto);
      if (v is! Map) {
        await negar('CUERPO?');
        return;
      }
      cuerpo = Map<String, dynamic>.from(v);
    } catch (_) {
      await negar('CUERPO?');
      return;
    }

    final nonce = cuerpo['nonce']?.toString() ?? '';
    final reto = _retos.remove(nonce); // el ping también quema el reto
    if (reto == null || reto.vencido) {
      await negar('RETO?');
      return;
    }
    if (llaveSesion.isEmpty ||
        cuerpo['llave']?.toString() != llaveSesion) {
      await negar('DENEGADO');
      return;
    }
    final fecha = cuerpo['fecha'];
    final fechaMs = fecha is num ? fecha.toInt() : -1;
    if (fechaMs < 0 ||
        (DateTime.now().millisecondsSinceEpoch - fechaMs).abs() >
            _sesgoFechaMs) {
      await negar('FECHA?');
      return;
    }

    final pase = emitirPase(reto.pagina);
    await _responder(
      req,
      HttpStatus.ok,
      pingJson(true, pase: pase),
      'application/json; charset=utf-8',
    );
  }

  Future<void> detener() async {
    _autorizado = false;
    llaveSesion = '';
    _retos.clear();
    _pases.clear();
    final s = _srv;
    _srv = null;
    try {
      await s?.close(force: true);
    } catch (_) {}
  }
}
