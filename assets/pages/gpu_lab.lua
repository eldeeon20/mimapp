-- GPU Lab — WebGPU/WGSL desde Lua (f16 real si el chip soporta)
theme_apply{ preset = "neon" }

gui_heading{text="GPU Lab · WGSL en caliente"}
gui_text{id="info", text="(tocá init)"}
gui_button{text="Init GPU", on_click="init"}
gui_button{text="GELU 64K f32", on_click="g32"}
gui_button{text="GELU 64K f16", on_click="g16"}
gui_button{text="Linear 256³", on_click="lin"}
gui_button{text="Attention 128×64", on_click="attn"}
gui_button{text="Shader custom (x2+1)", on_click="shader"}
gui_scroll{ height = 300, children = {
  gui_text{id="out", text="", multiline=true},
} }

handler("on_event", function(id, res)
  engine_set("out", res)
end)

local shader = [[
enable shader-f16;
struct Params { x: f32, y: f32, z: f32, n: u32 }
@group(0) @binding(0) var<storage, read_write> data: array<f16>;
@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    if (gid.x >= params.n) { return; }
    let v = f32(data[gid.x]);
    data[gid.x] = f16(v * params.x + params.y);
}
]]

handler("init", function()
  engine_set("out", "iniciando…")
  local id = gpu_init_start()
  -- poll corto para refrescar info apenas esté listo
  handler("on_event", function(jid, res)
    engine_set("out", res)
    engine_set("info", gpu_info() .. (gpu_has_f16() and " [f16 ✓]" or " [f16 ✗]"))
  end)
end)

handler("g32", function() local i = gpu_gelu_start(65536, false); engine_set("out","job "..i) end)
handler("g16", function() local i = gpu_gelu_start(65536, true);  engine_set("out","job "..i) end)
handler("lin", function() local i = gpu_linear_start(256,256,256,false); engine_set("out","job "..i) end)
handler("attn", function() local i = gpu_attn_start(128,64,true); engine_set("out","job "..i) end)

handler("shader", function()
  local i = gpu_wgsl_start(shader, 1024, 16, 2.0, 1.0, 0.0)
  engine_set("out", "compilando WGSL f16… job " .. i)
end)

gui_link{text="← Descargas", href="lua://hf_browser"}
gui_link{text="Nostr DM →", href="lua://nostr_dm_lab"}
