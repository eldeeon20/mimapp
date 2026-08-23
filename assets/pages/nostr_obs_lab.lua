-- Nostr Obs Lab — chat con clave compartida + observador solo lectura
theme_apply{ preset = "neon" }

gui_heading{text="Nostr Observador (Shared-Key)"}
gui_text{text="Pegá la shared key que entrega un participante y mirá la"}
gui_text{text="conversación sin poder escribir ni ver identidades."}
gui_input{id="shared", value="", label="shared key (hex)"}
gui_button{text="Conectar observador", on_click="connect"}
gui_button{text="Poll", on_click="poll"}
gui_scroll{ height = 260, children = {
  gui_text{id="out", text="(desconectado)", multiline=true},
} }

handler("on_event", function(id, res)
  engine_set("out", res)
end)

local relays = "wss://relay.damus.io|wss://nos.lol|wss://relay.nostr.wine"

handler("connect", function()
  local id = obs_connect_start(engine_get("shared") or "", relays)
  engine_set("out", "conectando observador… job " .. id)
end)

handler("poll", function()
  local id = obs_poll_start()
end)

gui_link{text="← Nostr DM", href="lua://nostr_dm_lab"}
gui_link{text="Inicio de labs →", href="lua://kem_lab"}
