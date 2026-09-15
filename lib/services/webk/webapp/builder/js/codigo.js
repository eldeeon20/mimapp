/* ---------- CAMPOS SEPARADOS (ver código html/css/js) ---------- */

function verCodigo(){

  const panel =
    document.getElementById("panelCodigo");

  const t = buildTriple();

  document.getElementById("campoHtml").value = t.html;
  document.getElementById("campoCss").value = t.css;
  document.getElementById("campoJs").value = t.js;

  panel.classList.toggle("ver");

}


function cerrarCodigo(){

  document.getElementById("panelCodigo").classList.remove("ver");

}


/* El JS y el CSS se editan acá (SCRIPT/STYLE no van al lienzo).
   Aplicar los deja en el sitio: el próximo triple/zip/SQL/BD/preview
   los usa. El html es solo lectura (lo dibuja el lienzo). */
function aplicarCodigo(){

  SITIO_CSS = document.getElementById("campoCss").value;
  SITIO_JS = document.getElementById("campoJs").value;

  document.getElementById("status").textContent =
    "Código aplicado al sitio";

}
