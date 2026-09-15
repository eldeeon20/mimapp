/* ==================================================
   WEB BUILDER: lógica del editor (drag, props, build)
   Lo sirve WebK con pase; el html solo trae el cargador.
================================================== */

/* ---------- DRAG & DROP ---------- */

let draggedType = null;

document.querySelectorAll(".tool").forEach(tool => {

  tool.addEventListener("dragstart", e => {

    draggedType = tool.dataset.type;

  });

});


const page =
  document.getElementById("page");


page.addEventListener("dragover", e => {

  e.preventDefault();

  page.classList.add("drag-over");

});


page.addEventListener("dragleave", () => {

  page.classList.remove("drag-over");

});


page.addEventListener("drop", e => {

  e.preventDefault();

  page.classList.remove("drag-over");

  if (!draggedType) return;

  const element =
    createElement(draggedType);

  page.appendChild(element);

  selectElement(element);

  draggedType = null;

});


/* ---------- CREAR COMPONENTES ---------- */

const IMG_SIN_RED = 'data:image/svg+xml;utf8,' + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="150">'
  + '<rect width="300" height="150" fill="#ccc"/>'
  + '<text x="150" y="80" text-anchor="middle" font-size="16" fill="#666">Imagen</text></svg>');


function createElement(type){

  const wrapper =
    document.createElement("div");

  wrapper.className = "element";

  wrapper.dataset.type = type;


  if(type === "text"){

    wrapper.innerHTML =
      "<p>Nuevo texto</p>";

  }


  if(type === "title"){

    wrapper.innerHTML =
      "<h1>Nuevo título</h1>";

  }


  if(type === "button"){

    wrapper.innerHTML =
      '<button>Nuevo botón</button>';

  }


  if(type === "image"){

    wrapper.innerHTML =
      '<img src="' + IMG_SIN_RED + '" style="max-width:100%">';

  }


  if(type === "box"){

    wrapper.innerHTML =
      '<div style="min-height:120px;padding:20px;border:1px solid #ccc">Contenedor</div>';

  }


  wrapper.addEventListener("click", e => {

    e.stopPropagation();

    selectElement(wrapper);

  });


  return wrapper;

}


/* ---------- SELECCIONAR ---------- */

let selected = null;


function selectElement(element){

  if(selected){

    selected.classList.remove("selected");

  }

  selected = element;

  selected.classList.add("selected");

  showProperties();

}


/* ---------- PROPIEDADES ---------- */

function showProperties(){

  if(!selected) return;


  const content =
    document.getElementById("propertyContent");


  const hijo =
    selected.firstElementChild;

  const tag = hijo ? hijo.tagName : "";


  // LINK: se edita el href (el contenido no)
  if(tag === "LINK"){

    content.innerHTML = `

      <label>href</label>

      <textarea id="editHref">${escapeHtml(hijo.getAttribute("href") || "")}</textarea>

      <button onclick="aplicarLink()">
        Aplicar
      </button>

      <button onclick="deleteSelected()">
        Eliminar
      </button>

    `;

    return;

  }


  // META: se editan atributos (charset, name/content…)
  if(tag === "META"){

    content.innerHTML = `

      <label>name / property / charset</label>

      <textarea id="editMetaN">${escapeHtml(hijo.getAttribute("name") || hijo.getAttribute("property") || hijo.getAttribute("charset") || "")}</textarea>

      <label>content</label>

      <textarea id="editMetaC">${escapeHtml(hijo.getAttribute("content") || "")}</textarea>

      <button onclick="aplicarMeta()">
        Aplicar
      </button>

      <button onclick="deleteSelected()">
        Eliminar
      </button>

    `;

    return;

  }


  const text =
    selected.innerText;


  content.innerHTML = `

    <label>Texto</label>

    <textarea id="editText">${escapeHtml(text)}</textarea>

    <button onclick="applyText()">
      Aplicar
    </button>

    <button onclick="deleteSelected()">
      Eliminar
    </button>

  `;

}


function refrescarDistintivo(){

  if(!selected) return;

  const b = selected.querySelector("[data-editor]");

  if(!b || typeof textoDistintivo !== "function") return;

  const hijo = selected.firstElementChild;

  if(hijo) b.textContent = textoDistintivo(hijo);

}


function aplicarLink(){

  if(!selected) return;

  const hijo = selected.firstElementChild;

  if(!hijo || hijo.tagName !== "LINK") return;

  hijo.setAttribute("href", document.getElementById("editHref").value);

  refrescarDistintivo();

}


function aplicarMeta(){

  if(!selected) return;

  const hijo = selected.firstElementChild;

  if(!hijo || hijo.tagName !== "META") return;

  const n = document.getElementById("editMetaN").value.trim();
  const c = document.getElementById("editMetaC").value;

  ["name", "property", "charset"].forEach(a => hijo.removeAttribute(a));

  if(n){
    if(/^utf-?8$/i.test(n)) hijo.setAttribute("charset", n);
    else if(n.includes(":")) hijo.setAttribute("property", n);
    else hijo.setAttribute("name", n);
  }

  if(c) hijo.setAttribute("content", c);
  else hijo.removeAttribute("content");

  refrescarDistintivo();

}


function applyText(){

  if(!selected) return;

  const value =
    document.getElementById("editText").value;


  const child =
    selected.firstElementChild;


  if(child){

    child.textContent = value;

  }

  refrescarDistintivo(); // TITLE y otros con distintivo

}


/* ---------- ELIMINAR ---------- */

function deleteSelected(){

  if(!selected) return;

  selected.remove();

  selected = null;

  document.getElementById("propertyContent")
    .textContent = "Seleccioná un elemento.";

}


/* ---------- LIMPIAR ---------- */

function clearPage(){

  page.innerHTML = "";

  selected = null;

  SITIO_CSS = null; // lienzo nuevo = código base
  SITIO_JS = null;

}


/* ---------- ESCAPAR TEXTO ---------- */

function escapeHtml(text){

  return text
    .replaceAll("&","&amp;")
    .replaceAll("<","&lt;")
    .replaceAll(">","&gt;")
    .replaceAll('"',"&quot;");

}

/* ---------- ARRANQUE (clicks) ---------- */
/* ---------- CLICK EN CANVAS ---------- */

page.addEventListener("click", e => {

  if(e.target === page){

    if(selected){

      selected.classList.remove("selected");

      selected = null;

    }

  }

});


/* ---------- ELEMENTOS INICIALES ---------- */

document.querySelectorAll(".element")
  .forEach(element => {

    element.addEventListener("click", e => {

      e.stopPropagation();

      selectElement(element);

    });

  });
