/* ---------- ZIP EN SQL (db "sitios" cifrada) ---------- */

function b64DeBlob(blob){

  return new Promise(function(res, rej){

    const fr = new FileReader();

    fr.onload = () => res(String(fr.result).split(",")[1] || "");

    fr.onerror = () => rej(fr.error);

    fr.readAsDataURL(blob);

  });

}


function blobDeB64(b64){

  const bin = atob(b64);
  const b = new Uint8Array(bin.length);

  for(let i = 0; i < bin.length; i++) b[i] = bin.charCodeAt(i);

  return new Blob([b], {type: "application/zip"});

}


async function zipPass(){

  const r = await puente().callHandler(
    "webk",
    {cmd: "builder_zip_abrir",
     pass: prompt("Pass del zip-sql:", "") || "",
     llave: llave()});

  if(r !== "OK"){
    document.getElementById("status").textContent = "zip-sql: " + r;
    return false;
  }

  return true;

}


async function zipGuardarSQL(){

  if(!puente()){
    document.getElementById("status").textContent = "sin puente";
    return;
  }

  if(!(await zipPass())) return;

  const nombre = prompt("Nombre para el zip:", "mi-web") || "mi-web";

  const t = buildTriple();

  const b64 = await b64DeBlob(zipArchivos([
    {nombre: "index.html", texto: t.html},
    {nombre: "style.css", texto: t.css},
    {nombre: "script.js", texto: t.js}
  ]));

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_zip_guardar", nombre: nombre, b64: b64, llave: llave()});

    document.getElementById("status").textContent =
      (r === "OK") ? ("ZIP en SQL: " + nombre) : ("ERROR: " + r);

    if(r === "OK") zipListarSQL(false);

  }catch(e){

    document.getElementById("status").textContent = "error: " + e;

  }

}


async function zipListarSQL(pedirPass){

  const caja = document.getElementById("listaZips");

  if(!puente()){
    caja.innerHTML = "sin puente";
    return;
  }

  try{

    if(pedirPass !== false){
      if(!(await zipPass())) return;
    }

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_zip_listar", llave: llave()});

    if(r && typeof r === "object" && r.zips){

      caja.innerHTML = r.zips.length ? "" : "vacío";

      r.zips.forEach(z => {

        const b = document.createElement("button");

        b.textContent = "⬇ " + z.nombre + " (" + Math.round(z.tamB64 / 137) + "B)";

        b.onclick = () => zipBajarSQL(z.nombre);

        caja.appendChild(b);


        const d = document.createElement("button");

        d.textContent = "✕";

        d.onclick = () => zipBorrarSQL(z.nombre);

        caja.appendChild(d);

      });

    }else{

      caja.innerHTML = "ERROR: " + r;

    }

  }catch(e){

    caja.innerHTML = "error: " + e;

  }

}


async function zipBajarSQL(nombre){

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_zip_bajar", nombre: nombre, llave: llave()});

    if(r && typeof r === "object" && r.b64){

      const url = URL.createObjectURL(blobDeB64(r.b64));
      const a = document.createElement("a");
      a.href = url;
      a.download = nombre + ".zip";
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);

      document.getElementById("status").textContent =
        "ZIP bajado: " + nombre;

    }else{

      document.getElementById("status").textContent = "ERROR: " + r;

    }

  }catch(e){

    document.getElementById("status").textContent = "error: " + e;

  }

}


async function zipBorrarSQL(nombre){

  if(!confirm("¿Borrar zip «" + nombre + "»?")) return;

  try{

    const r = await puente().callHandler(
      "webk",
      {cmd: "builder_zip_borrar", nombre: nombre, llave: llave()});

    if(r === "OK"){ zipListarSQL(false); }

    else{ document.getElementById("status").textContent = "ERROR: " + r; }

  }catch(e){

    document.getElementById("status").textContent = "error: " + e;

  }

}
