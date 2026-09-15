/* ---------- GENERAR WEB FINAL ---------- */

/* Cuerpo limpio: clona la página y le saca marcas del editor. */
function contenidoLimpio(){

  const clone =
    page.cloneNode(true);


  // distintivos del editor (LINK/META/TITLE): sale la etiqueta y
  // el wrapper, queda solo el nodo real limpio (sin display:none)
  clone
    .querySelectorAll("[data-editor]")
    .forEach(b => {

      const w = b.parentElement;
      const real =
        (w && w.firstElementChild !== b) ? w.firstElementChild : null;

      b.remove();

      if(w && real){
        if(real.style) real.style.display = "";
        w.replaceWith(real);
      }else if(w){
        w.remove();
      }

    });


  clone
    .querySelectorAll(".element")
    .forEach(el => {

      el.classList.remove("element");
      el.classList.remove("selected");

      el.removeAttribute("data-type");

    });

  return clone.innerHTML;

}


/* Triple separado: index + css + js (campos independientes). */
function buildTriple(){

  return {
    html: `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Mi Web</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>

${contenidoLimpio()}

  <script src="script.js"><\/script>
</body>
</html>`,
    css: `body {
  font-family: sans-serif;
}

${getPageStyles()}`,
    js: getPageScript()
  };

}


function buildWeb(){

  const cuerpo = contenidoLimpio();


  return `<!DOCTYPE html>

<html lang="es">

<head>

<meta charset="UTF-8">

<meta name="viewport"
content="width=device-width,initial-scale=1">

<title>Mi Web</title>

<style>

body{
  margin:0;
  font-family:Arial,sans-serif;
}

${getPageStyles()}

</style>

</head>

<body>

${cuerpo}

<script>

${getPageScript()}

<\/script>

</body>

</html>`;

}


/* ---------- CSS DE LA WEB GENERADA ---------- */

/* Css/js del sitio cargado desde un zip (null = los de base).
   El próximo guardado/triple/preview los usa tal cual. */
let SITIO_CSS = null;
let SITIO_JS = null;


function getPageStyles(){

  if(SITIO_CSS !== null) return SITIO_CSS;

  return `
#page{
  max-width:900px;
  margin:auto;
  padding:40px;
}
`;

}


/* ---------- JS DE LA WEB GENERADA ---------- */

function getPageScript(){

  if(SITIO_JS !== null) return SITIO_JS;

  return `
// JavaScript de tu web
`;

}
