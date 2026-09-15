/* Cargar web para editar: lee un ZIP (store, sin comprimir) y
   reconstruye el lienzo + el css/js del sitio. Sin librerías:
   el CDN no carga en la app (sin internet). Solo método 0;
   si viene DEFLATE se avisa (bajarlo de SQL sale en store). */

function leerZip(buf){

  const v = new DataView(buf);
  const n = v.byteLength;
  const le = true;

  // fin del directorio (EOCD) buscado desde atrás
  let fin = -1;
  const desde = Math.max(0, n - 22 - 65536);
  for(let i = n - 22; i >= desde; i--){
    if(v.getUint32(i, le) === 0x06054b50){ fin = i; break; }
  }
  if(fin < 0) throw new Error("no es un zip");

  const total = v.getUint16(fin + 10, le);
  let off = v.getUint32(fin + 16, le);
  const dec = new TextDecoder();
  const archivos = {};

  for(let k = 0; k < total; k++){
    if(v.getUint32(off, le) !== 0x02014b50){
      throw new Error("zip roto (central)");
    }
    const metodo = v.getUint16(off + 10, le);
    const tamC = v.getUint32(off + 20, le);
    const ln = v.getUint16(off + 28, le);
    const le2 = v.getUint16(off + 30, le);
    const lc = v.getUint16(off + 32, le);
    const locOff = v.getUint32(off + 42, le);
    const nombre = dec.decode(new Uint8Array(buf, off + 46, ln));
    off += 46 + ln + le2 + lc;

    // cabecera local → inicio de datos
    if(v.getUint32(locOff, le) !== 0x04034b50){
      throw new Error("zip roto (local): " + nombre);
    }
    if(metodo !== 0){
      throw new Error("«" + nombre + "» viene comprimido (método "
        + metodo + "): solo leo store");
    }
    const lnL = v.getUint16(locOff + 26, le);
    const leL = v.getUint16(locOff + 28, le);
    const ini = locOff + 30 + lnL + leL;
    archivos[nombre] =
      dec.decode(new Uint8Array(buf, ini, tamC));
  }

  return archivos;

}


/* Categorías de edición (webs externas): no se descarta lo que
   sí se puede modificar, se manda a otro panel. */
const noVisual = [
  "SCRIPT",
  "STYLE",
  "HEAD"
];

const editableAttributes = [
  "LINK",
  "META",
  "TITLE"
];

const special = [
  "NOSCRIPT",
  "TEMPLATE"
];


/* ¿A qué panel va este elemento? 'noVisual' | 'attrs' | 'special' | 'visual'.
   - noVisual: fuera del lienzo (SCRIPT/STYLE → editores de código).
   - attrs: al lienzo como distintivo, se editan atributos/texto.
   - special: al lienzo con su contenido extraído.
   - visual: al lienzo tal cual. */
function categoriaDe(el){

  // Si está dentro de un elemento no visual, tampoco se muestra
  if(el.closest("script, style, head")){
    return "noVisual";
  }

  if(noVisual.includes(el.tagName)){
    return "noVisual";
  }

  if(editableAttributes.includes(el.tagName)){
    return "attrs";
  }

  if(special.includes(el.tagName)){
    return "special";
  }

  return "visual";

}


/* Tipo de elemento por etiqueta (para reconstruir el lienzo). */
function tipoDeEtiqueta(tag){
  switch(tag){
    case "H1": case "H2": case "H3": return "title";
    case "P": case "TITLE": return "text";
    case "BUTTON": return "button";
    case "IMG": return "image";
    case "LINK": return "link";
    case "META": return "meta";
    default: return "box";
  }
}


/* Texto del distintivo (LINK/META/TITLE no se ven en el lienzo,
   así que muestran una etiqueta con lo editable). */
function textoDistintivo(nodo){
  switch(nodo.tagName){
    case "LINK":
      return "🔗 LINK → " + (nodo.getAttribute("href") || "(sin href)");
    case "META": {
      const n = nodo.getAttribute("name")
        || nodo.getAttribute("charset")
        || nodo.getAttribute("property")
        || "meta";
      const c = nodo.getAttribute("content") || "";
      return "🏷 META " + n + (c ? " = " + c : "");
    }
    case "TITLE":
      return "📌 TITLE: " + nodo.textContent.trim();
    default:
      return nodo.tagName;
  }
}


/* Envuelve LINK/META/TITLE: el nodo real queda oculto y se muestra
   un distintivo con lo editable (href, atributos, texto). */
function envolverDistintivo(nodo){
  nodo.style.display = "none";
  const w = document.createElement("div");
  w.className = "element";
  w.dataset.type = nodo.tagName.toLowerCase();
  w.appendChild(nodo);
  const b = document.createElement("span");
  b.setAttribute("data-editor", "1");
  b.textContent = textoDistintivo(nodo);
  w.appendChild(b);
  w.addEventListener("click", e => {
    e.stopPropagation();
    selectElement(w);
  });
  return w;
}


/* Mete un nodo ya existente dentro de un wrapper editable.
   Le saca lo no editable anidado (scripts/estilos sueltos). */
function envolverElemento(nodo){
  nodo.querySelectorAll("script,style,link,meta,noscript,template")
    .forEach(n => n.remove());
  const w = document.createElement("div");
  w.className = "element";
  w.dataset.type = tipoDeEtiqueta(nodo.tagName);
  w.appendChild(nodo);
  w.addEventListener("click", e => {
    e.stopPropagation();
    selectElement(w);
  });
  return w;
}


/* Código inline de la web cargada: lo inyectamos nosotros
   (SITIO_JS/SITIO_CSS) en vez de tirarlo. Con src externo se saltea
   (sin internet no cargaría igual). */
function inyectarCodigo(tmp){
  tmp.querySelectorAll("style").forEach(s => {
    if(s.textContent.trim()){
      SITIO_CSS = (SITIO_CSS ?? getPageStyles())
        + "\n/* de la web cargada */\n" + s.textContent;
    }
  });
  tmp.querySelectorAll("script").forEach(s => {
    if(!s.src && s.textContent.trim()){
      SITIO_JS = (SITIO_JS ?? getPageScript())
        + "\n/* de la web cargada */\n" + s.textContent;
    }
  });
}


function reconstruirDesdeHtml(cuerpo){
  page.innerHTML = "";
  selected = null;
  const tmp = document.createElement("div");
  tmp.innerHTML = cuerpo;
  inyectarCodigo(tmp);
  Array.from(tmp.childNodes).forEach(n => {
    if(n.nodeType === 3 && !n.textContent.trim()) return; // blancos
    if(n.nodeType !== 1){
      const w = document.createElement("div");
      w.className = "element";
      w.dataset.type = "text";
      const p = document.createElement("p");
      p.textContent = n.textContent;
      w.appendChild(p);
      w.addEventListener("click", e => {
        e.stopPropagation();
        selectElement(w);
      });
      page.appendChild(w);
      return;
    }
    const cat = categoriaDe(n);
    if(cat === "noVisual") return; // SCRIPT/STYLE/HEAD: al editor de código
    if(cat === "attrs"){ // LINK/META/TITLE: distintivo con lo editable
      page.appendChild(envolverDistintivo(n));
      return;
    }
    if(cat === "special"){ // NOSCRIPT/TEMPLATE: se edita su contenido
      const d = document.createElement("div");
      d.innerHTML = n.innerHTML;
      page.appendChild(envolverElemento(d));
      return;
    }
    page.appendChild(envolverElemento(n));
  });
}


async function cargarZipEnEditor(archivo){
  const estado = document.getElementById("status");
  try{
    const buf = await archivo.arrayBuffer();
    const z = leerZip(buf);
    const keys = Object.keys(z);
    // busca el index (raíz o primer html)
    let idx = keys.find(k => /(^|\/)index\.html$/.test(k));
    if(!idx) idx = keys.find(k => /\.html?$/.test(k));
    if(!idx) throw new Error("el zip no trae html");
    const base = idx.includes("/") ? idx.slice(0, idx.lastIndexOf("/") + 1) : "";
    const html = z[idx];
    const m = html.match(/<body[^>]*>([\s\S]*)<\/body>/i);
    reconstruirDesdeHtml(m ? m[1] : html);
    // css/js del zip pasan a ser los del sitio (próximo guardado los usa)
    SITIO_CSS = z[base + "style.css"] ?? null;
    SITIO_JS = z[base + "script.js"] ?? null;
    estado.textContent =
      "Cargado: " + idx + " (" + keys.length + " archivos)";
  }catch(e){
    estado.textContent = "ERROR cargar: " + e.message;
  }
}


function entradaCargar(){
  const inp = document.getElementById("archivoZip");
  if(inp) inp.click();
}


/* El input vive en builder.html; al elegir zip se carga al lienzo. */
(function(){
  const inp = document.getElementById("archivoZip");
  if(!inp) return;
  inp.addEventListener("change", async e => {
    const f = e.target.files && e.target.files[0];
    inp.value = "";
    if(f) await cargarZipEnEditor(f);
  });
})();
