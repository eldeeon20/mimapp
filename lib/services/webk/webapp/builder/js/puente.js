/* Puente WebK: acceso al canal JS->Dart y a la llave. */
function puente(){
  return window.flutter_inappwebview;
}

function llave(){
  return window.WEBK_LLAVE || '';
}
