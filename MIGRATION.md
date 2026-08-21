# MIGRATION.md — Reestructuración de `lib/`

## Reglas del proyecto

1. `main.dart` solo inicia App.
2. `app/` controla el flujo global.
3. AppShell es el root visual de la aplicación.
4. Router controla la navegación.
5. Cada funcionalidad grande es un módulo independiente.
6. Cada módulo tiene un archivo `<modulo>.dart` como entrada pública.
7. `pages` = pantallas.
8. `widgets` = componentes visuales.
9. Services pertenecen al módulo que los necesita.
10. Solo el estado global pertenece a AppController.
11. Un módulo no importa internals de otro módulo.
12. Evitar dependencias circulares.
13. No crear capas/carpetas hasta que exista una necesidad real.
14. Código generado nunca se mezcla con UI.
15. Si un módulo crece demasiado, se subdivide internamente sin cambiar su API pública.
16. Desde fuera del módulo: `import 'package:pr_app/lua/lua.dart'`, nunca internals.
17. Barrel exporta solo la API pública (no todo).

## Estructura objetivo

```
lib/
├── main.dart                              ← BOOT, NO TOCAR
│
├── app/                                   ← SCENE ROOT
│   ├── app.dart                           ← MaterialApp + Theme
│   ├── router.dart                        ← navegación, conecta módulos
│   ├── state.dart                         ← AppController (solo estado global)
│   ├── services.dart                      ← init notificaciones + background
│   │
│   └── widgets/
│       ├── app_shell.dart                 ← Scaffold principal
│       └── bottom_bar.dart                ← navegación inferior
│
├── pages/                                 ← pantallas globales
│   └── home_page.dart                     ← diseño nuevo
│
├── colab/                                 ← módulo Colab
│   ├── colab.dart                         ← API pública (barrel)
│   ├── colab_service.dart                 ← ColabService
│   ├── pages/
│   │   └── colab_page.dart                ← UI Colab (antes dialog)
│   └── widgets/
│
├── crypto/                                ← módulo ToolSec/Crypto
│   ├── crypto.dart                        ← API pública (barrel)
│   ├── crypto_service.dart                ← encodeFileSecure + cipher
│   ├── pages/
│   │   └── crypto_page.dart               ← UI ToolSec (antes dialog)
│   └── widgets/
│
├── lua/                                   ← módulo Lua
│   ├── lua.dart                           ← API pública (barrel)
│   ├── pages/
│   │   └── lua_page.dart                  ← Lua tool
│   └── widgets/
│       ├── lua_console.dart
│       └── lua_runner.dart
│
├── rust/                                  ← módulo Rust/FRB
│   ├── rust.dart                          ← barrel (RustLib.init)
│   ├── pages/
│   ├── widgets/
│   └── bridge/                            ← FRB generated (no mezclar con UI)
│
├── media/                                 ← módulo Media
│   ├── media.dart                         ← API pública (barrel)
│   ├── pages/
│   │   ├── media_page.dart                ← Media tool
│   │   └── player_page.dart
│   └── widgets/
│       ├── media_player.dart              ← MediaPlayer logic
│       └── media_card.dart
│
└── laurelia/                              ← módulo IA Laurelia
    ├── laurelia.dart                      ← API pública (barrel)
    ├── pages/
    │   └── laurelia_page.dart             ← IA chat
    └── widgets/
        ├── chat.dart
        └── message.dart
```

## Mapeo de archivos existentes

| Archivo actual | Migración a |
|---|---|
| `main.dart` | **se queda** (cambia import a `app/app.dart`) |
| `gui/engine_shell.dart` | **ELIMINAR** → `app/widgets/app_shell.dart` |
| `ai/laurelia_chat.dart` | `laurelia/` (lógica interna) |
| `colab_cli/colab_auth.dart` | `colab/` |
| `colab_cli/colab_config.dart` | `colab/` |
| `colab_cli/colab_dialog.dart` | `colab/pages/colab_page.dart` |
| `colab_cli/colab_keep_alive.dart` | `colab/` |
| `colab_cli/colab_sessions.dart` | `colab/` |
| `lua/lua_controller.dart` | `lua/` |
| `lua/page_model.dart` | `lua/` |
| `lua/page_registry.dart` | `lua/` |
| `media/media_player.dart` | `media/widgets/media_player.dart` |
| `screens/ai_screen.dart` | `laurelia/pages/laurelia_page.dart` |
| `screens/media_screen.dart` | `media/pages/media_page.dart` |
| `services/colab_service.dart` | `colab/colab_service.dart` |
| `toolsec/toolsec.dart` | `crypto/crypto_service.dart` |
| `toolsec/toolsec_dialog.dart` | `crypto/pages/crypto_page.dart` |
| `widgets/gui_*` (11 archivos) | `lua/widgets/` |

## Archivos a ELIMINAR después de migrar

- `gui/` (completo)
- `screens/` (completo)
- `widgets/gui_*` (11 archivos, migrados a `lua/widgets/`)
- `toolsec/` (completo, migrado a `crypto/`)
- `colab_cli/` (completo, migrado a `colab/`)
- `services/colab_service.dart` (migrado a `colab/colab_service.dart`)
- `ai/` (completo, migrado a `laurelia/`)

## Flujo de dependencias

```
                    APP
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
       COLAB      CRYPTO     MEDIA ←→ LAURELIA
          │          │          │         │
       service    service    service   service
       pages      pages      pages     pages
       widgets    widgets    widgets   widgets
```

- Lua → Media (para video) y Lua → Laurelia (para IA) se comunican vía AppService
- No dependencias circulares

## Fases de implementación

| Fase | Qué | Archivos nuevos |
|---|---|---|
| **1** | Crear `app/` (app, router, state, services, app_shell, bottom_bar) | 6 |
| **2** | Crear `pages/home_page.dart` con el diseño nuevo | 1 |
| **3** | Migrar `colab/` completo | 5-6 |
| **4** | Migrar `crypto/` completo | 3-4 |
| **5** | Migrar `media/` | 4 |
| **6** | Migrar `laurelia/` | 3-4 |
| **7** | Migrar `lua/` | 3-4 |
| **8** | Crear `rust/` barrel vacío | 1 |
| **9** | Actualizar `main.dart` (import `app/app.dart`) | 1 |
| **10** | Eliminar archivos viejos | — |
| **11** | Push + CI verification | — |

## Bloqueo actual

Esperando a que CI pase con notificaciones + servicio en segundo plano funcionando.
Una vez verificado, se arranca la migración completa.
