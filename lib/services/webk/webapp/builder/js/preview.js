/* ---------- PREVIEW (iframe local, sin window.open) ---------- */

function previewWeb(){

  document.getElementById("marcoWeb").srcdoc = buildWeb();

  document.getElementById("vistaPrevia").classList.add("ver");

}


function cerrarPrevia(){

  document.getElementById("vistaPrevia").classList.remove("ver");

  document.getElementById("marcoWeb").srcdoc = "";

}
