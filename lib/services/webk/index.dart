import 'dart:convert';
import 'dart:typed_data';

import 'mime.dart';

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

/// Índice de páginas de WebK: registra, resuelve y valida básico.
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

/// Hola-mundo de respaldo si el asset no carga (misma idea que hola.html).
const kWebkHolaRespaldo = '''<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WebK · hola</title></head>
<body style="font-family:sans-serif;text-align:center;padding-top:60px;background:#020617;color:#fff">
<h1>Hola WebK</h1>
<p>Servido por el servidor local (RAM, una sola conexión autorizada).</p>
</body>
</html>
''';
