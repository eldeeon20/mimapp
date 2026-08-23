# pr_app — Plan Lua global: router, inicio, tema y bindings

> Estado: implementado en este ciclo. La capa Lua se convierte en la forma
> universal de armar pantallas y llamar a TODAS las capacidades del app.

## 0. Arquitectura base (ya existía)

```
assets/pages/*.lua ──► LuaController (VM lua_dardo_plus)
                        │   prelude: gui_* construye page.body
                        │   globals: engine_get/set, navigate, rust_*, player_*, laurelia_*
                        ▼
                    PageModel (GuiNode tree) ──► GuiRuntime ──► Widgets Flutter
                        ▲
                  StateStore (updates VALUE solo repintan el nodo enlazado)
```

## 1. PageRouter — mini handle plug-and-play (`lib/lua/page_router.dart`)

TODA petición de página pasa por el router; agregar un transporte nuevo es
registrar una rama, nada más. El router no sabe (ni le importa) de dónde
viene la página:

| scheme | transporte | estado |
|---|---|---|
| `lua://nombre` / `nombre` / `local:` | assets locales (páginas en caliente) | ✅ |
| `http(s)://` | red (con normalización GitHub→raw) | ✅ |
| `tcp://host:port/ruta` | socket crudo: manda `GET ruta\n`, lee hasta cerrar | ✅ |
| `udp://host:port` | datagrama request/response (timeout 5s) | ✅ |
| `nostrn://npub/nombre` | evento Nostr (NIP-23-ish, tag d=nombre) | ✅ vía NostrChat |
| `magnet:` / `torrent:` | STUB — interfaz lista, se activa al portar torrent de Gtool | stub |

Extras: caché LRU en memoria + historial automático en `HistoryStore`.

## 2. Inicio tipo navegador (`lua_page.dart`)

Header nativo sobre el canvas:
- **Búsqueda**: texto libre → nombre local o URL completa → router.
- **Historial**: chips con las últimas visitas (`HistoryStore`, cifrado AES-GCM
  en archivo aparte `lua_history.pr`).
- **Recomendados**: grilla de páginas registradas (metadata: título/icono/
  color/descr) + lo que haya en caché.
- Botón ⌂ vuelve al inicio; back lógico entre páginas visitadas.

## 3. Hipervínculos

`gui_link{ text="Ir a KEM", href="lua://kem_lab" }` → botón estilizado cuyo
on_click viaja por el router. Cualquier página puede linkear a cualquiera,
local o remota: la web interna es navegable como hipertexto.

## 4. Tema + widgets nuevos

- `lib/lua/lua_theme.dart`: presets `dark` / `neon` / `terminal` / `ocean`;
  desde Lua: `theme_apply{ preset="neon" }` o colores puntuales hex.
- Colores hex `#RRGGBB` ya soportados en todo nodo (existía).
- Widgets nuevos:
  - `gui_card{ ... }` — contenedor con sombra/radio/borde que acepta children
  - `gui_grid{ columns=2, ... }` — GridView para children
  - `gui_scroll{ ... }` — área scrolleable anidada
  - `gui_style_button{ label, icon, color }` — botón custom (gradiente+icono)
  - `gui_zoom_image{ src, height }` — imagen pinch-zoom (InteractiveViewer)
  - `gui_link{ text, href }`
- Children: los contenedores aceptan tabla `children = { gui_text{...}, ... }`.

## 5. Bindings globales (jobs + on_event)

La VM es sincrónica y Rust devuelve Futures ⇒ patrón jobs:

```lua
id = shamir_demo_start("mi secreto", 5, 3)   -- retorna id de job YA
-- el controller drena jobs cada 300ms e invoca en Lua:
function handlers.on_event(id, result)  -- result = string resumen/op data
  engine_set("out", result)
end
-- o polling manual: done, res = job_poll(id)
```

Partes nuevas (patrón igual que lua_player/lua_laurelia):

| parte | globals |
|---|---|
| `lua_shamir.dart` | `shamir_demo_start`, `shamir_split_start`, `shamir_combine_start` |
| `lua_kem.dart` | `kem_algos()`, `kem_keygen_start`, `kem_roundtrip_start` |
| `lua_hf.dart` | `hf_init_start`, `hf_search_start`, `hf_range_start`, `hf_download_start` |
| `lua_gpu.dart` | `gpu_init_start`, `gpu_info()`, `gpu_has_f16()`, `gpu_gelu_start`, `gpu_linear_start`, `gpu_attn_start`, `gpu_wgsl_start(code,n,dx,px,py,pz)` 🔥 shaders desde Lua |
| `lua_nostr.dart` | `dm_connect_start`, `dm_send_start`, `dm_poll_start`, `obs_connect_start`, `obs_poll_start` |

Helpers: `job_poll(id)` y `job_wait(id)` (yield cooperativo), `job_count()`.

## 6. Páginas ejemplo (linkeadas entre sí)

`inicio` (nativa) · `demo` · `player` · `laurelia` · `shamir_lab` ·
`kem_lab` · `gpu_lab` · `hf_browser` · `nostr_dm_lab` · `nostr_obs_lab`.
Cada lab muestra su API con links a los demás.

## 7. Decisiones tomadas

- Async en Lua: **jobs + on_event** (no bloquea UI).
- Historial: **archivo aparte** `lua_history.pr` cifrado fuerte (no config.pr).
- Torrent: **stub** hasta portar el módulo de Gtool.
- Cifrado global: CryptoVault AES-256-GCM + PBKDF2 (config.pr migra solo).
