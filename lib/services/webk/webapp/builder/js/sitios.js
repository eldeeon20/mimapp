/* Sitios en WebK (webapp/sitio/): guardar, ver, listar. */
async function guardarEnWebk(){

  if(!puente()){
    document.getElementById("status").textContent = "sin puente";
    return;
  }

  const nombre = prompt("Nombre para la web:", "mi-web") || "mi-web";

  const t = buildTriple();

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_guardar", nombre: nombre,
       cuerpo: contenidoLimpio(), css: t.css, js: t.js, llave: llave()});

    if(r && typeof r === "object" && r.ok){

      document.getElementById("status").textContent =
        "Guardada en WebK: " + r.pagina;

      verWeb(r.pagina);

    }else{

      document.getElementById("status").textContent = "ERROR: " + r;

    }

  }catch(e){

    document.getElementById("status").textContent = "error: " + e;

  }

}


async function verWeb(pagina){

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "abrir", pagina: pagina, llave: llave()});

    if(r !== "OK"){
      document.getElementById("status").textContent = "DENEGADO: " + r;
    }

  }catch(e){

    document.getElementById("status").textContent = "error: " + e;

  }

}


async function misWebs(){

  const caja = document.getElementById("listaSitios");

  if(!puente()){
    caja.innerHTML = "sin puente";
    return;
  }

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_sitios", llave: llave()});

    if(r && typeof r === "object" && r.sitios){

      caja.innerHTML = r.sitios.length ? "" : "vacío";

      r.sitios.forEach(s => {

        const b = document.createElement("button");

        b.textContent = s;

        b.onclick = () => verWeb(s);

        caja.appendChild(b);

      });

    }else{

      caja.innerHTML = "ERROR: " + r;

    }

  }catch(e){

    caja.innerHTML = "error: " + e;

  }

}
