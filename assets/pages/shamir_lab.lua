-- Shamir Lab — partir y reconstruir secretos
theme_apply{ preset = "terminal" }

gui_heading{text="Shamir Secret Sharing"}
gui_input{id="sec", value="mi secreto super seguro", label="secreto"}
gui_button{text="Demo: parte 5 / umbral 3", on_click="demo"}
gui_scroll{ height = 280, children = {
  gui_text{id="out", text="(sin ejecutar)", multiline=true},
} }

handler("on_event", function(id, res)
  engine_set("out", res)
end)

handler("demo", function()
  local sec = engine_get("sec")
  if sec == nil or sec == "" then sec = "sin secreto" end
  local id = shamir_demo_start(sec, 5, 3)
  engine_set("out", "partiendo… job " .. id)
end)

gui_link{text="← KEM Lab", href="lua://kem_lab"}
gui_link{text="GPU Lab →", href="lua://gpu_lab"}
