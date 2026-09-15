/* ---------- DESCARGAR (navegador: 3 archivos sueltos) ---------- */

function descargar(nombre, contenido){

  const blob =
    new Blob(
      [contenido],
      {type: "text/plain;charset=utf-8"}
    );


  const url =
    URL.createObjectURL(blob);


  const a =
    document.createElement("a");


  a.href = url;

  a.download =
    nombre;


  document.body.appendChild(a);

  a.click();

  a.remove();


  URL.revokeObjectURL(url);

}


function descargarTriple(){

  const t = buildTriple();

  descargar("index.html", t.html);
  descargar("style.css", t.css);
  descargar("script.js", t.js);

  document.getElementById("status")
    .textContent =
    "3 archivos descargados";

}


/* ---------- ZIP (sin librerías: store, con CRC32) ---------- */

const _TABLA_CRC = (function(){
  const t = new Uint32Array(256);
  for(let n = 0; n < 256; n++){
    let c = n;
    for(let k = 0; k < 8; k++){
      c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    t[n] = c >>> 0;
  }
  return t;
})();


function crc32(bytes){
  let c = 0xFFFFFFFF;
  for(let i = 0; i < bytes.length; i++){
    c = _TABLA_CRC[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) >>> 0;
}


function zipArchivos(archivos){

  const enc = new TextEncoder();

  const datos = [];   // trozos del zip
  const central = []; // directorio central
  let offset = 0;


  function u16(v){
    datos.push(new Uint8Array([v & 0xFF, (v >> 8) & 0xFF]));
  }

  function u32(v){
    datos.push(new Uint8Array(
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]));
  }

  function crudo(b){
    datos.push(b);
  }


  archivos.forEach(f => {

    const nombre = enc.encode(f.nombre);
    const cuerpo = enc.encode(f.texto);
    const crc = crc32(cuerpo);

    // cabecera local (30 fijos + nombre + cuerpo)
    u32(0x04034b50);
    u16(20); u16(0); u16(0); u16(0); u16(0);
    u32(crc); u32(cuerpo.length); u32(cuerpo.length);
    u16(nombre.length); u16(0);
    crudo(nombre);
    crudo(cuerpo);

    // entrada central
    const c = [];
    const cu16 = v => c.push(v & 0xFF, (v >> 8) & 0xFF);
    const cu32 = v => c.push(
      v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF);
    cu32(0x02014b50);
    cu16(20); cu16(20);
    cu16(0); cu16(0); cu16(0); cu16(0);
    cu32(crc); cu32(cuerpo.length); cu32(cuerpo.length);
    cu16(nombre.length);
    cu16(0); cu16(0); cu16(0); cu16(0);
    cu32(0); cu32(offset);
    for(let i = 0; i < nombre.length; i++) c.push(nombre[i]);
    central.push(new Uint8Array(c));

    offset += 30 + nombre.length + cuerpo.length;

  });


  const inicioCentral = offset;
  let tamCentral = 0;
  central.forEach(c => { datos.push(c); tamCentral += c.length; });

  function u16f(v){
    datos.push(new Uint8Array([v & 0xFF, (v >> 8) & 0xFF]));
  }

  function u32f(v){
    datos.push(new Uint8Array(
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]));
  }

  // fin del directorio
  u32f(0x06054b50);
  u16f(0); u16f(0);
  u16f(archivos.length); u16f(archivos.length);
  u32f(tamCentral); u32f(inicioCentral); u16f(0);

  return new Blob(datos, {type: "application/zip"});

}


function bajarZip(){

  const t = buildTriple();

  const zip = zipArchivos([
    {nombre: "index.html", texto: t.html},
    {nombre: "style.css", texto: t.css},
    {nombre: "script.js", texto: t.js}
  ]);


  const url =
    URL.createObjectURL(zip);


  const a =
    document.createElement("a");


  a.href = url;

  a.download =
    "mi-web.zip";


  document.body.appendChild(a);

  a.click();

  a.remove();


  URL.revokeObjectURL(url);


  document.getElementById("status")
    .textContent =
    "ZIP descargado";

}
