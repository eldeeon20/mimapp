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
