import 'dart:convert';
import 'dart:typed_data';

import '../servidor/mime.dart';

/// Una página registrada en WebK.
class WebkPagina {
  final String nombre;
  final Uint8List bytes;
  final String mime;
  const WebkPagina({
    required this.nombre,
    required this.bytes,
    required this.mime,
  });
}

/// Respuesta del índice (página + bytes a servir).
typedef WebkResolvedor = Future<WebkPagina?> Function(String ruta);

/// Índice de páginas de WebK: registra, resuelve y valida básico.
///
/// Las páginas viven como ARCHIVOS en esta carpeta (paginas/*.html):
/// a futuro serán muchas y el índice las resuelve por nombre sin
/// tocar código. Nada de html suelto en Dart.
///
/// Parseo hoy: chequeo mínimo de forma (un html trae <html>…</html>).
/// TODO(fase 2, pendiente): al DESCIFRAR cada página, comprobar
/// hash/firma en [verificarContenido] antes de servirla. Hoy es
/// passthrough a propósito.
class WebkIndex {
  final _paginas = <String, WebkPagina>{};

  void registrar(String nombre, Uint8List bytes) {
    final n = _normalizar(nombre);
    _paginas[n] = WebkPagina(
      nombre: n,
      bytes: bytes,
      mime: MimeUtil.deNombre(n),
    );
  }

  void registrarTexto(String nombre, String texto) =>
      registrar(nombre, Uint8List.fromList(utf8.encode(texto)));

  List<String> get paginas => _paginas.keys.toList()..sort();

  /// Resuelve una ruta ('/hola.html' o 'hola.html'; '' → hola.html).
  /// null = no existe o no pasó verificación.
  Future<WebkPagina?> resolver(String ruta) async {
    var nombre = _normalizar(ruta);
    if (nombre.isEmpty) nombre = 'hola.html';
    final p = _paginas[nombre];
    if (p == null) return null;
    if (!bienFormada(p)) return null;
    if (!await verificarContenido(p)) return null;
    return p;
  }

  /// ¿La página está bien formada? (mínimo: html abre y cierra).
  /// No-html siempre pasa (lo sirve tal cual).
  bool bienFormada(WebkPagina p) {
    if (!p.mime.contains('html')) return true;
    final t = utf8.decode(p.bytes, allowMalformed: true).toLowerCase();
    return t.contains('<html') && t.contains('</html>');
  }

  /// Hook criptográfico (FASE 2, hoy desactivado a pedido).
  ///
  /// Acá va: descifrar la página con su llave + comprobar hash/firma
  /// contra el manifiesto. Si falla → false y [resolver] sirve 404.
  // ignore: avoid-unused-parameters
  Future<bool> verificarContenido(WebkPagina p) async {
    // TODO(fase 2): comprobación hash/firma al descifrar.
    return true;
  }

  static String _normalizar(String ruta) {
    var n = ruta.trim();
    while (n.startsWith('/')) {
      n = n.substring(1);
    }
    return n;
  }
}
