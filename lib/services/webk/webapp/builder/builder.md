# Builder · editor de páginas web (webapp/builder/)

Editor visual dentro de WebK: arrastrás componentes, editás texto,
previsualizás y guardás la web como **3 archivos separados**
(`index.html` + `style.css` + `script.js`), en ZIP o en las db cifradas.

## Qué hace

- **Armar**: panel izquierdo con componentes (texto, título, botón,
  imagen, contenedor) → drag&drop al lienzo → clic para seleccionar →
  panel derecho edita el texto / elimina.
- **Ver código** (👁 Código): muestra los 3 campos separados ya
  generados (index/style/script), solo lectura.
- **Preview** (▶): overlay con iframe local (`srcdoc`, sin `window.open`
  porque en el WebView no anda).
- **⬇ Archivos**: descarga los 3 sueltos (navegador).
- **⬇ ZIP**: empaqueta los 3 en `mi-web.zip` (writer propio, sin
  librerías ni internet: método store + CRC32 a mano).
- **💾 WebK**: guarda el sitio triple en `webapp/sitio/<nombre>/`
  (index con cargador + css + js) y lo abre ahí mismo.
- **📂 Sitios**: lista lo guardado en el índice y lo abre.
- **SQL 💾 / SQL 📂**: guarda/traer/borra el ZIP en la db `sitios`
  cifrada (viaja en base64 porque el puente pasa texto).
- **BD 💾 / BD 📂**: guarda la página con **versión** (1.0, 1.1…)
  en la db `paginas` cifrada; la lista muestra ▶ por versión.

## Partes (qué archivo hace qué)

```
builder/
  builder.html   ← marcas + cargador + paneles (código, preview)
  builder.css    ← TODO el estilo del editor
  js/
    partes.json    ← MANIFIESTO: lista de partes en orden (único lugar)
    componentes.js ← drag&drop, crear, seleccionar, props, eliminar,
                     limpiar, arranque (clicks iniciales)
    generar.js     ← contenidoLimpio(), buildTriple(), buildWeb(),
                     getPageStyles(), getPageScript()
    descargas.js   ← descargar(), descargarTriple(), ZIP (crc32,
                     zipArchivos, bajarZip)
    codigo.js      ← verCodigo(), cerrarCodigo()
    puente.js      ← puente() = canal JS→Dart, llave() = sesión
    sitios.js      ← guardarEnWebk(), verWeb(), misWebs()
    zipsql.js      ← b64DeBlob/blobDeB64, zipGuardarSQL/Listar/Bajar/Borrar
    paginasdb.js   ← bdGuardar/Listar/Ver/Borrar (versiones)
    preview.js     ← previewWeb(), cerrarPrevia()
```

El `builder.html` NO usa `<script src>` común: el servidor respondería
el reto, no el código. El **cargador** pide el css, lee `partes.json` y
trae cada js **con pase** (puente `pase` + `fetch` + inyección).
Sin llave no sale nada.

## Cómo extender

### Agregar un componente (ej: video)

En `js/componentes.js`, dentro de `createElement(type)`:

```js
if(type === "video"){
  wrapper.innerHTML =
    '<video controls style="max-width:100%"></video>';
}
```

Y en `builder.html`, en el aside `#tools`:

```html
<div class="tool" draggable="true" data-type="video">
  🎬 Video
</div>
```

Nada más: el drop, la selección, las props y el build lo toman solo
(todo pasa por `createElement` + `contenidoLimpio`).

### Agregar una parte js nueva (ej: `js/temas.js`)

1. Crear `webapp/builder/js/temas.js` (funciones globales, estilo del
   resto: `function miTema(){…}`).
2. Agregarlo a `js/partes.json` en el lugar que corresponda
   (antes de quien lo use).
3. Listo: ni el html ni Dart se tocan (el servidor trae a demanda).

Ojo con el orden: `componentes.js` define `page`/`selectElement` (base),
`generar.js` los usa; `puente.js` antes que `sitios/zipsql/paginasdb`.

### Agregar un botón del editor

En `builder.html` (`#bar`): `<button onclick="miFn()">…</button>`,
la función en el js que corresponda. Si habla con Dart, usar
`puente().callHandler('webk', {cmd: 'mi_cmd', …, llave: llave()})`
y atender `mi_cmd` en un conector (`puentes/`, ver `webk.md`).

### Cambiar lo que trae una web generada

- Estilo base: `getPageStyles()` en `js/generar.js`.
- Script base: `getPageScript()` en `js/generar.js`.
- Estructura del triple: `buildTriple()` (index con `<link>`/`<script src>`,
  css, js). Lo usan descargas, ZIP, código, SQL y BD: un solo cambio
  llega a todos.

## Limitaciones (y por qué)

- **Sin internet**: placeholder de imagen en data-URI (no via.placeholder),
  sin CDNs. Todo lo que la web generada necesite debe ir inline o no ir.
- **ZIP sin compresión** (store): empaqueta, no achica. DEFLATE real =
  escribir LZ77+Huffman a mano (~300 líneas) o vendorizar librería.
- **ZIP sin cifrado**: el `.zip` descargado lo abre cualquiera. Lo
  cifrado son las db (`sitios`, `paginas`); el transporte WebK
  (reto+ping+pase+llave).
- **Bridge pasa texto/JSON**: el ZIP viaja en base64 (+37% de tamaño).
  Topes: sitio triple 2MB, zip ~6MB (el índice vive en RAM y el puente
  manda todo en un mensaje).
- **`prompt`/`confirm` nativos**: se usan para nombre/pass/borrados.
  En el WebView andan; si algún día se ven mal, reemplazar por un
  modal propio del builder.
- **Descargas en la app**: el anchor-blob anda en navegador; en el
  WebView puede fallar según versión → por eso existen 💾 WebK,
  SQL 💾 y BD 💾 (quedan dentro, cifrados).
- **Preview aislado**: el iframe lleva `sandbox="allow-scripts"`: la
  vista previa corre JS pero sin puente ni red (a propósito).
- **Una página a la vez en el lienzo**: sin pestañas ni deshacer.
  El estado vive en el DOM (`#page`); recargar el builder lo pierde
  (guardar primero).
