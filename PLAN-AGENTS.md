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

## AGENT 2 (responsable: humano/otro agente) — Fixes pendientes

| # | Tarea | Archivo |
|---|---|---|
| 2.1 | GPU F16 automático: switch nunca bloqueado (`gpu_test_screen.dart:178`), clamp `useF16 = _f16 && GpuContext.instance.hasF16` en ops y títulos honestos; guard muerto línea 82 fuera | `gpu_test_screen.dart`, `services/gpu/{gelu,linear,attention}.dart` |
| 2.2 | Debug "error de tabla" Lua web: ninguna página abre (kem/gpu/shamir/nostr/hf); solo Laurelia/Media andan. Rastrear carga en `lua_page.dart` → `gui_runtime.dart` → globals vs lo que piden los `.lua` de `assets/pages/` | `lib/lua/*`, `assets/pages/*.lua` |
| 2.3 | Globals Lua `ring_*` (ring_keypair_start / ring_sign_start / ring_verify_start, patrón jobs de `lua_nostr.dart`) | `lib/lua/lua_nostrring.dart` nuevo + registro en controller |
| 2.4 | Actualizar este MD con lo hecho por cada agent al cerrar tarea | `PLAN-AGENTS.md` |
