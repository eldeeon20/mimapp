# web_inapp_i2p.md — Browser inappwebview + plan I2P

Estado: IMPLEMENTADO fase 1 (browser) · I2P: REFERENCIA futura · Fecha: 2026-08-25

## 1. Qué se implementó (browser)

El botón **Web** de abajo ya no abre la web Lua: ahora abre un mini browser
sobre `flutter_inappwebview` (plugin puro, NO la app completa de referencia
[pichillilorenzo/flutter_browser_app](https://github.com/pichillilorenzo/flutter_browser_app),
que queda solo como inspiración). El código Lua quedó **intacto pero suelto**
en `lib/lua/` sin invocar.

### Estructura modular

```
lib/browser/
├── browser_tab.dart        # modelo de pestaña + contrato BrowserTabLike
├── browser_tabs.dart       # BrowserTabs (ChangeNotifier): lista/activa/
│                           #   add/close cap 8, registro de controladores,
│                           #   toggle global JS aplicado en vivo
├── browser_webview.dart    # BrowserWebview: envuelve UN InAppWebView;
│                           #   progreso, url/título → gestor; descargas →
│                           #   DownloadManager global
└── browser_cookies.dart    # CookieStore singleton: get/set/clearAll/dump

lib/services/
└── browser_downloads.dart  # DownloadManager singleton: streaming a archivo
                            #   en <appSupport>/browser_downloads con progreso

lib/screens/
└── inapp_web_screen.dart   # pantalla fina: URL bar + Go/Atrás, chips de
                            #   pestañas (+/✕), IndexedStack (conserva estado),
                            #   switch JavaScript ON/OFF
```

### Alcance actual
- Barra URL (agrega https:// si falta esquema), Go/recargar, Atrás
- Pestañas múltiples con estado preservado (IndexedStack), tope 8
- **Único toggle: JavaScript** (global, aplicado en vivo a todos los tabs)
- Descargas del WebView derivadas a `DownloadManager` (directas por ahora)

### Pendientes declarados (fases siguientes)
| Pendiente | Dónde entra |
|---|---|
| Clase **Proxy** (Tor/I2P/directo) | `BrowserTabs`/`DownloadManager`: método setProxy; hoy NO hay selector |
| sha256-verify en descargas | `DownloadManager.start(..., expectedSha256)` |
| cargo-deny en CI | workflow Android, allowlist permissive-only |
| Wire extra del browser (favoritos, incógnito) | ideas del repo de referencia |

## 2. I2P — de dónde sale (referencia)

Un cliente I2P necesita SIEMPRE un router corriendo. Dos fuentes:

| Fuente | Qué es | Licencia | Esfuerzo |
|---|---|---|---|
| App oficial I2P Android (router EXTERNO) | El usuario instala el router; expone puertos localhost | Router fuera de nuestra APK → sin impacto para nosotros | Bajo |
| i2pd embebido (PurpleI2P/i2pd) | Router C++ compilado con NDK dentro de la app | Apache-2.0 ✓ | Alto (NDK, reseed, ciclo de vida) |

**Recomendado**: empezar con router externo. Puertos que expone y que
consumiríamos:

| Puerto | Protocolo | Uso |
|---|---|---|
| 4444 | HTTP proxy | eepsites (.i2p) desde HttpClient/WebView |
| 4447 | SOCKS5 | mismo patrón que Tor (socks5h) |
| 7656 | SAM v3 | API para P2P/mensajería futura |

Integración prevista (cuando toque): clase `Proxy` con selección por destino,
regla extra en `ProxyController` del WebView para `.i2p`, y primer bootstrap
lento (reseed de floodfills, minutos).

## 3. Riesgos CI conocidos
- Versión exacta del plugin vs Flutter/Kotlin del CI (fix-push si gradle protesta)
- Nombres de callbacks v6 (`onWebViewControllerCreated`, `WebUri`) tomados de docs 6.x
