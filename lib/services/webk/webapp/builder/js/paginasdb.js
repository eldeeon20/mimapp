/* ---------- PÁGINAS EN DB (db "paginas", con versiones) ---------- */

async function bdPass(){

  const r = await puente().callHandler(
    "webk",
    {cmd: "builder_pagina_abrir",
     pass: prompt("Pass de la db paginas:", "") || "",
     llave: llave()});

  if(r !== "OK"){
    document.getElementById("status").textContent = "db paginas: " + r;
    return false;
  }

  return true;

}


async function bdGuardar(){

  if(!puente()){
    document.getElementById("status").textContent = "sin puente";
    return;
  }

  if(!(await bdPass())) return;

  const nombre = prompt("Nombre de la página:", "mi-web") || "mi-web";

  const t = buildTriple();

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_pagina_guardar", nombre: nombre,
       cuerpo: contenidoLimpio(), css: t.css, js: t.js, llave: llave()});

    if(r && typeof r === "object" && r.ok){

      document.getElementById("status").textContent =
        "DB: " + r.nombre + " v" + r.version;

      bdListar(false);

    }else{

      document.getElementById("status").textContent = "ERROR: " + r;

    }

  }catch(e){

    document.getElementById("status").textContent = "error: " + e;

  }

}


async function bdListar(pedirPass){

  const caja = document.getElementById("listaPags");

  if(!puente()){
    caja.innerHTML = "sin puente";
    return;
  }

  try{

    if(pedirPass !== false){
      if(!(await bdPass())) return;
    }

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_pagina_listar", llave: llave()});

    if(r && typeof r === "object" && r.paginas){

      caja.innerHTML = r.paginas.length ? "" : "vacío";

      r.paginas.forEach(p => {

        const t = document.createElement("div");

        t.innerHTML = "<b>" + p.nombre + "</b>";

        caja.appendChild(t);

        p.versiones.forEach(v => {

          const b = document.createElement("button");

          b.textContent = "▶ v" + v;

          b.onclick = () => bdVer(p.nombre, v);

          caja.appendChild(b);

        });


        const d = document.createElement("button");

        d.textContent = "✕ todas";

        d.onclick = () => bdBorrar(p.nombre, "");

        caja.appendChild(d);

      });

    }else{

      caja.innerHTML = "ERROR: " + r;

    }

  }catch(e){

    caja.innerHTML = "error: " + e;

  }

}


async function bdVer(nombre, version){

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_pagina_ver",
       nombre: nombre, version: version, llave: llave()});

    if(r && typeof r === "object" && r.ok){

      document.getElementById("status").textContent =
        "DB: " + nombre + " v" + r.version;

      verWeb(r.pagina);

    }else{

      document.getElementById("status").textContent = "ERROR: " + r;

    }

  }catch(e){

    document.getElementById("status").textContent = "error: " + e;

  }

}


async function bdBorrar(nombre, version){

  if(!confirm("¿Borrar «" + nombre + (version ? " v" + version : " (todas)") + "»?")) return;

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_pagina_borrar",
       nombre: nombre, version: version, llave: llave()});

    if(r === "OK"){ bdListar(false); }

    else{ document.getElementById("status").textContent = "ERROR: " + r; }

  }catch(e){

    document.getElementById("status").textContent = "error: " + e;

  }

}
