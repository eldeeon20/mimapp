-- KEM Lab — criptografía post-cuántica
theme_apply{ preset = "dark" }

gui_heading{text="KEM Post-Cuántico"}
gui_text{text="X25519 · ML-KEM 512/768/1024 · X25519+ML-KEM768 · X-Wing"}
gui_button{text="Listar algoritmos", on_click="algos"}
gui_button{text="Roundtrip X-Wing", on_click="rt_xwing"}
gui_button{text="Roundtrip ML-KEM-1024", on_click="rt_1024"}
gui_scroll{ height = 260, children = {
  gui_text{id="out", text="(sin ejecutar)", multiline=true},
} }

handler("on_event", function(id, res)
  engine_set("out", res)
end)

handler("algos", function()
  local id = kem_algos()
  engine_set("out", "buscando algoritmos… job " .. id)
end)

handler("rt_xwing", function()
  local id = kem_roundtrip_start("XWingKemDraft06")
  engine_set("out", "roundtrip X-Wing… job " .. id)
end)

handler("rt_1024", function()
  local id = kem_roundtrip_start("MlKem1024")
  engine_set("out", "roundtrip ML-KEM-1024… job " .. id)
end)

gui_link{text="← Shamir Lab", href="lua://shamir_lab"}
gui_link{text="HuggingFace →", href="lua://hf_browser"}
