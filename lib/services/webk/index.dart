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

/// Puerta: cargador que SOLO muestra el contenido si el puente Dart está
/// verificado. En Chrome (sin flutter_inappwebview) se queda bloqueado y
/// el contenido real nunca se revela ni se sirve sin señal.
const kWebkPuerta = '''<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WebK · puerta</title>
<style>
body{font-family:sans-serif;text-align:center;padding-top:60px;background:#020617;color:#fff;margin:0}
.card{display:inline-block;border:1px solid #B57CFF55;border-radius:12px;padding:24px 40px;background:#0B1220}
#estado{color:#B57CFF}
</style>
</head>
<body>
<div class="card">
<h1>Puerta WebK</h1>
<p id="estado">comprobando puente…</p>
</div>
<script>
(async function(){
  var el = document.getElementById('estado');
  if(!window.flutter_inappwebview){
    el.textContent = 'BLOQUEADO: sin puente Dart (¿Chrome?). Contenido oculto.';
    return;
  }
  el.textContent = 'puente detectado, pidiendo pase a Dart…';
  try{
    var r = await window.flutter_inappwebview.callHandler(
      'webk', {cmd: 'abrir', pagina: 'demo.html', llave: window.WEBK_LLAVE || ''});
    el.textContent = (r === 'OK')
      ? 'pase OK: Dart carga el contenido…'
      : 'DENEGADO por Dart: ' + r;
  }catch(e){ el.textContent = 'error: ' + e; }
})();
</script>
</body>
</html>
''';

/// Segundo ejemplo: demo del puente (estado + hora del server Dart).
const kWebkDemo = '''<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WebK · demo puente</title>
<style>
body{font-family:sans-serif;text-align:center;padding-top:40px;background:#020617;color:#fff;margin:0}
h1{color:#4DD0E1}
.card{display:inline-block;border:1px solid #4DD0E155;border-radius:12px;padding:24px 40px;background:#0B1220;max-width:90vw}
button{margin:4px;padding:8px 14px;border-radius:8px;border:1px solid #4DD0E1;background:#0B1220;color:#fff}
pre{text-align:left;background:#00000088;border-radius:8px;padding:12px;min-width:280px;white-space:pre-wrap}
</style>
</head>
<body>
<div class="card">
<h1>Demo puente</h1>
<p>Esta página solo se ve si Dart verificó el puente.</p>
<p>
<button onclick="llamar('estado')">Estado server</button>
<button onclick="llamar('hora')">Hora Dart</button>
<button onclick="pedirAuth()">Pedir autorización</button>
</p>
<pre id="out">puente: listo, tocá un botón…</pre>
</div>
<script>
function out(t){ document.getElementById('out').textContent = t; }
async function llamar(cmd, extra){
  if(!window.flutter_inappwebview){ out('sin puente (página fuera de WebK)'); return; }
  try{
    const r = await window.flutter_inappwebview.callHandler(
      'webk', Object.assign({cmd: cmd}, extra || {}));
    out(typeof r === 'object' ? JSON.stringify(r, null, 1) : String(r));
  }catch(e){ out('error: ' + e); }
}
function pedirAuth(){ llamar('autorizar', {llave: window.WEBK_LLAVE || ''}); }
</script>
</body>
</html>
''';

/// Puerta: cargador que SOLO muestra el contenido si el puente Dart está
/// verificado. En Chrome (sin flutter_inappwebview) se queda bloqueado y
/// el contenido real nunca se revela ni se sirve sin señal.
const kWebkPuerta = '''<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WebK · puerta</title>
<style>
body{font-family:sans-serif;text-align:center;padding-top:60px;background:#020617;color:#fff;margin:0}
.card{display:inline-block;border:1px solid #B57CFF55;border-radius:12px;padding:24px 40px;background:#0B1220}
#estado{color:#B57CFF}
</style>
</head>
<body>
<div class="card">
<h1>Puerta WebK</h1>
<p id="estado">comprobando puente…</p>
</div>
<script>
(async function(){
  var el = document.getElementById('estado');
  if(!window.flutter_inappwebview){
    el.textContent = 'BLOQUEADO: sin puente Dart (¿Chrome?). Contenido oculto.';
    return;
  }
  el.textContent = 'puente detectado, pidiendo pase a Dart…';
  try{
    var r = await window.flutter_inappwebview.callHandler(
      'webk', {cmd: 'abrir', pagina: 'demo.html', llave: window.WEBK_LLAVE || ''});
    el.textContent = (r === 'OK')
      ? 'pase OK: Dart carga el contenido…'
      : 'DENEGADO por Dart: ' + r;
  }catch(e){ el.textContent = 'error: ' + e; }
})();
</script>
</body>
</html>
''';

/// Segundo ejemplo: demo del puente (estado + hora del server Dart).
const kWebkDemo = '''<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WebK · demo puente</title>
<style>
body{font-family:sans-serif;text-align:center;padding-top:40px;background:#020617;color:#fff;margin:0}
h1{color:#4DD0E1}
.card{display:inline-block;border:1px solid #4DD0E155;border-radius:12px;padding:24px 40px;background:#0B1220;max-width:90vw}
button{margin:4px;padding:8px 14px;border-radius:8px;border:1px solid #4DD0E1;background:#0B1220;color:#fff}
pre{text-align:left;background:#00000088;border-radius:8px;padding:12px;min-width:280px;white-space:pre-wrap}
</style>
</head>
<body>
<div class="card">
<h1>Demo puente</h1>
<p>Esta página solo se ve si Dart verificó el puente.</p>
<p>
<button onclick="llamar('estado')">Estado server</button>
<button onclick="llamar('hora')">Hora Dart</button>
<button onclick="pedirAuth()">Pedir autorización</button>
</p>
<pre id="out">puente: listo, tocá un botón…</pre>
</div>
<script>
function out(t){ document.getElementById('out').textContent = t; }
async function llamar(cmd, extra){
  if(!window.flutter_inappwebview){ out('sin puente (página fuera de WebK)'); return; }
  try{
    const r = await window.flutter_inappwebview.callHandler(
      'webk', Object.assign({cmd: cmd}, extra || {}));
    out(typeof r === 'object' ? JSON.stringify(r, null, 1) : String(r));
  }catch(e){ out('error: ' + e); }
}
function pedirAuth(){ llamar('autorizar', {llave: window.WEBK_LLAVE || ''}); }
</script>
</body>
</html>
''';
