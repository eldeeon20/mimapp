-- HuggingFace Browser — buscar modelos y leer rangos de checkpoints
theme_apply{ preset = "ocean" }

gui_heading{text="HuggingFace Browser"}
gui_input{id="token", value="", label="token (vacío = anónimo)"}
gui_button{text="Init", on_click="init"}
gui_input{id="author", value="ScortexIA", label="autor"}
gui_button{text="Buscar modelos", on_click="search"}
gui_input{id="repo", value="ScortexIA/laurelia", label="repo_id"}
gui_button{text="Leer header tokenizer.json (0..512)", on_click="range"}
gui_scroll{ height = 280, children = {
  gui_text{id="out", text="(sin ejecutar)", multiline=true},
} }

handler("on_event", function(id, res)
  engine_set("out", res)
end)

local function tok()
  return engine_get("token") or ""
end

handler("init", function()
  engine_set("out", "iniciando cliente…")
  local id = hf_init_start(tok())
end)

handler("search", function()
  local a = engine_get("author") or "ScortexIA"
  local id = hf_search_start(a, 10)
  engine_set("out", "buscando modelos de " .. a .. "… job " .. id)
end)

handler("range", function()
  local r = engine_get("repo") or "ScortexIA/laurelia"
  local id = hf_range_start(r, "tokenizer.json", 0, 512)
  engine_set("out", "bajando rango… job " .. id)
end)

gui_link{text="← GPU Lab", href="lua://gpu_lab"}
gui_link{text="Nostr DM →", href="lua://nostr_dm_lab"}
