/* ---------- GENERAR WEB FINAL ---------- */

/* Cuerpo limpio: clona la página y le saca marcas del editor. */
function contenidoLimpio(){

  const clone =
    page.cloneNode(true);


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

function getPageStyles(){

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

  return `
// JavaScript de tu web
`;

}
