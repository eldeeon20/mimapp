# PLAN-AGENTS.md — Port Godot/Gtool → mimapp

División de trabajo en dos agentes. Cada uno marca sus tareas al cerrarlas.

## AGENT 1 (responsable: ox) — Nostringer UI (rama Godot)

Fuente: `mio/Gtool/example_godot/nostringer/*.gd`
Base lista: Rust `api/nostringer.rs` ✅ · service `services/nostringer.dart` ✅

| # | Tarea | Archivo | Origen |
|---|---|---|---|
| 1.1 ✅ | Pantalla firmas ring: keypairs xonly/compressed, ring N pubkeys, sign SAG/BLSAG, verify | `lib/screens/ring_signatures_test_screen.dart` | `test_nostringer.gd` |
| 1.2 ✅ | Centro del radial menu → botón real que abre esa pantalla (icono fingerprint) | `lib/app/widgets/radial_menu.dart` | — |
| 1.3 ✅ | Pantalla voto anónimo BLSAG: N votantes generados, firma blsag por voto, keyImagesMatch anti doble-voto, conteo | `lib/screens/ring_vote_test_screen.dart` | `test_nostringer_group.gd` |
| 1.4 ✅ | Botón `'rv'` al círculo `_items` + case en `app.dart` | `radial_menu.dart`, `app.dart` | — |

Criterio de hecho: ambas pantallas abren desde el menú, firman/verifican contra
`api/nostringer.rs`, voto rechaza repetidos. **AGENT 1 COMPLETADO** (`4280613`).

## AGENT 2 (responsable: ox) — Fixes pendientes

| # | Tarea | Archivo | Estado |
|---|---|---|---|
| 2.1 | GPU F16 automático: switch nunca bloqueado, clamp `useF16 = _f16 && GpuContext.instance.hasF16` en ops y títulos honestos; guard muerto fuera | `gpu_test_screen.dart`, `services/gpu/{gelu,linear,attention}.dart` | ✅ hecho: switch libre, clamp en los 3 services Y en pantalla, títulos muestran `(auto)` cuando cayó a F32, guard muerto eliminado |
| 2.2 | Debug "error de tabla" Lua web: páginas kem/gpu/shamir/nostr/hf no abren | `lib/lua/lua_controller.dart` | ✅ hecho: hallazgo = las 6 fallidas son las ÚNICAS que llaman `theme_apply{}` al cargar (verificado con Lua 5.3 real: sintaxis/validación OK). Fixes: (1) `theme_apply` blindada (arg en índice 1 + try/catch → peor caso abre sin tema, nunca rompe la carga), (2) `_lua.call` → `pCall` protegido: el error Lua REAL ahora sale en el banner (`Error Lua al ejecutar la página: attempt to…`), (3) parse de nodos con contexto (`nodo N ilegible`), (4) handlers con pCall loguean fallos a debugPrint en vez de tragarlos |
| 2.3 | Globals Lua `ring_*` (patrón jobs de `lua_nostr.dart`) | `lib/lua/lua_nostrring.dart` nuevo + registro en controller | ✅ hecho: `ring_keypair_start`, `ring_sign_start`, `ring_verify_start`, `ring_kimatch_start`; ring como pubkeys CSV separadas por `\|` |
| 2.4 | Actualizar este MD al cerrar tarea | `PLAN-AGENTS.md` | ✅ |

Nota para verificación on-device (2.2): si una página sigue sin abrir, el banner
ahora muestra el mensaje exacto de Lua — copiar ese texto tal cual.
