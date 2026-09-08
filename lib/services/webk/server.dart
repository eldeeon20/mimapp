import 'dart:async';
import 'dart:io';

import 'index.dart';

/// Respuesta del índice (página + bytes a servir).
typedef WebkResolvedor = Future<WebkPagina?> Function(String ruta);

/// Servidor HTTP local de WebK (web criptográfica).
///
/// - Escucha SOLO en loopback (127.0.0.1, puerto aleatorio): de afuera
///   no se llega ni a ver el puerto.
/// - Sordo por defecto: sin señal previa de la app responde 403 y cierra,
///   sin banner ni info (el que sondea no saca nada).
/// - [autorizarUna] es LA señal desde la app: habilita UNA sola conexión;
///   se consume al usarse. Cada recurso extra (css/js/favicon) necesita
///   otra señal explícita.
class WebkServer {
  HttpServer? _srv;
  WebkResolvedor? resolvedor;
  bool _autorizado = false;
  int servidas = 0;
  int rechazadas = 0;

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

  Future<void> _atender(HttpRequest req) async {
    if (!_autorizado) {
      rechazadas++;
      try {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
      } catch (_) {}
      return;
    }
    _autorizado = false; // una sola conexión: se consume acá
    try {
      final pagina = await resolvedor?.call(req.uri.path);
      if (pagina == null) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      servidas++;
      req.response.headers.contentType =
          ContentType.parse(pagina.mime);
      req.response.headers.contentLength = pagina.bytes.length;
      req.response.add(pagina.bytes);
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> detener() async {
    _autorizado = false;
    final s = _srv;
    _srv = null;
    try {
      await s?.close(force: true);
    } catch (_) {}
  }
}
