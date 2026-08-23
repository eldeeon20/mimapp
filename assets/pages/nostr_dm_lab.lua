-- Nostr DM Lab — chat NIP-17 sin observador
theme_apply{ preset = "dark" }

gui_heading{text="Nostr DM (NIP-17)"}
gui_text{text="Peer A y Peer B en el mismo dispositivo: generá keys en uno,"}
gui_text{text="pasá el npub al otro campo y conversen por los relays."}
gui_input{id="nsec", value="", label="mi nsec (vacío = generar)"}
gui_input{id="peer", value="", label="npub del otro peer"}
gui_button{text="Generar keys", on_click="gen"}
gui_button{text="Conectar", on_click="connect"}
gui_button{text="Poll mensajes", on_click="poll"}
gui_input{id="msg", value="hola desde Lua!", label="mensaje"}
gui_button{text="Enviar", on_click="send"}
gui_scroll{ height = 240, children = {
  gui_text{id="out", text="(desconectado)", multiline=true},
} }

handler("on_event", function(id, res)
  if string.find(res, '"msgs"') then
    -- respuesta de poll: mostrar crudo
    engine_set("chatlog", res)
    return
  end
  if string.find(res, '"mi_npub"') then
    engine_set("peer_hint", res)
  end
  engine_set("out", res)
end)

local relays = "wss://relay.damus.io|wss://nos.lol|wss://relay.nostr.wine"

handler("gen", function()
  -- genera identidad con el generador global (Keyl) y la muestra
  engine_set("out", "usá Config → Nostr Keys para generar, o pegá un nsec")
end)

handler("connect", function()
  local id = dm_connect_start(engine_get("nsec") or "", engine_get("peer") or "", relays)
  engine_set("out", "conectando… job " .. id)
end)

handler("send", function()
  local id = dm_send_start(engine_get("msg") or "")
  engine_set("out", "enviando… job " .. id)
end)

handler("poll", function()
  local id = dm_poll_start()
end)

gui_link{text="← HF Browser", href="lua://hf_browser"}
gui_link{text="Nostr Obs →", href="lua://nostr_obs_lab"}
