import 'dart:convert';
import 'dart:typed_data';

/// Ruta del ping del reto (POST con {nonce, llave, fecha}).
const kRutaPing = '/webk-ping';

/// Reto pendiente: el server ya mandó el js de prueba y espera el ping.
/// Si nadie responde antes de [expira], el server lo borra (corta).
class RetoPendiente {
  final String pagina;
  final DateTime expira;
  const RetoPendiente(this.pagina, this.expira);

  bool get vencido => DateTime.now().isAfter(expira);
}

/// Pase de una sola vez: el ping respondió bien y habilita UNA carga
/// del html real. Se quema al usarse (o al vencer).
class PaseUnico {
  final String pagina;
  final DateTime expira;
  const PaseUnico(this.pagina, this.expira);

  bool get vencido => DateTime.now().isAfter(expira);
}

/// Html+js mínimo del reto: NO trae contenido, solo prueba el ping.
///
/// - `window.WEBK_NONCE`: lo escribe el server al servir el reto.
/// - `window.WEBK_LLAVE`: la inyecta SOLO la app en su WebView (Dart→JS
///   con evaluateJavascript). Chrome no la tiene → su ping es DENEGADO
///   y el pendiente vence (conexión cortada, html jamás servido).
/// - `fecha`: Date.now() del que responde; el server tolera ±30s.
String construirReto(String nonce, String ruta) {
  final shell = '''
<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WebK · reto</title>
<style>
body{font-family:sans-serif;text-align:center;padding-top:60px;background:#020617;color:#fff;margin:0}
.card{display:inline-block;border:1px solid #B57CFF55;border-radius:12px;padding:24px 40px;background:#0B1220}
#estado{color:#B57CFF}
</style>
</head>
<body>
<div class="card">
<h1>WebK</h1>
<p id="estado">verificando…</p>
</div>
<script>
window.WEBK_NONCE='$nonce';
window.WEBK_RUTA='$ruta';
(function(){
  var el = document.getElementById('estado');
  var intentos = 0;
  function ping(){
    intentos++;
    var llave = window.WEBK_LLAVE || '';
    if(!llave){
      // espera la inyección Dart→JS de la app (~8s); Chrome nunca la recibe
      if(intentos < 40){ setTimeout(ping, 200); return; }
      el.textContent = 'BLOQUEADO: sin llave de sesión. Contenido oculto.';
      return;
    }
    fetch('$kRutaPing', {method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(
        {nonce: window.WEBK_NONCE, llave: llave, fecha: Date.now()})})
    .then(function(r){
      return r.json().catch(function(){ return {ok: false}; })
        .then(function(j){ return {s: r.status, j: j}; });
    })
    .then(function(x){
      if(x.s === 200 && x.j && x.j.ok && x.j.pase){
        el.textContent = 'pase OK, cargando…';
        location.href =
          window.WEBK_RUTA + '?pase=' + encodeURIComponent(x.j.pase);
      }else{
        el.textContent = 'DENEGADO por el server.';
      }
    })
    .catch(function(e){ el.textContent = 'error: ' + e; });
  }
  setTimeout(ping, 300);
})();
</script>
</body>
</html>
''';
  return shell;
}

/// Respuesta JSON del ping ya codificada.
Uint8List pingJson(bool ok, {String pase = '', String error = ''}) =>
    Uint8List.fromList(utf8.encode(ok
        ? '{"ok":true,"pase":"$pase"}'
        : '{"ok":false,"error":"$error"}'));
