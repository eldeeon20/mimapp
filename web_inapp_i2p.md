# web_inapp_i2p.md — Browser inappwebview + I2P embebido

Estado: browser IMPLEMENTADO · I2P embebido (emissary) IMPLEMENTADO (Rust+Dart, sin enchufe al
browser todavía) · Fecha: 2026-08-26

## 1. Browser (fase 1, ya en la app)

El botón **Web** abre un mini browser sobre `flutter_inappwebview` (plugin puro, NO la app de
referencia [pichillilorenzo/flutter_browser_app](https://github.com/pichillilorenzo/flutter_browser_app),
solo inspiración). El código Lua quedó **intacto pero suelto** en `lib/lua/` sin invocar.

```
lib/browser/
├── browser_tab.dart        # modelo de pestaña + contrato BrowserTabLike
├── browser_tabs.dart       # BrowserTabs (ChangeNotifier): lista/activa/add/close cap 8,
│                           #   registro de controladores, toggle global JS en vivo
├── browser_webview.dart    # BrowserWebview: envuelve UN InAppWebView; progreso/url/título;
│                           #   descargas → DownloadManager global
└── browser_cookies.dart    # CookieStore singleton: get/set/clearAll/dump

lib/services/browser_downloads.dart  # DownloadManager singleton: streaming con progreso
lib/screens/inapp_web_screen.dart    # URL bar + chips pestañas + IndexedStack + switch JS
```

Alcance actual: barra URL, pestañas (tope 8), **único toggle JavaScript**, descargas directas.
Pendiente declarado: selector de red (Directo/Tor/I2P), sha256-verify, cargo-deny CI.

## 2. I2P embebido — emissary (IMPLEMENTADO)

Router I2P **dentro de la app**: [eepnet/emissary](https://github.com/eepnet/emissary)
(Rust puro, **MIT**, crates.io `emissary-core`/`emissary-util` 0.4.0). Porte del ejemplo
oficial `examples/rust-tutorial`. Sin puente local: Rust habla DIRECTO por SAMv3.

### Estructura (archivos chicos por funcionalidad)

```
rust/src/api/i2p/
├── mod.rs      # declara + re-exporta fns FRB (prefijo i2p_)
├── state.rs    # estáticos compartidos: ROUTER_TASK, SAM_PORT, ESTADO, runtime()
├── router.rs   # i2p_start(data_dir,sam_port,transport_port,publicar)/stop/is_running
│               #   Storage→load→reseed solo si vacío→Config→Router::new→spawn
├── status.rs   # i2p_estado/i2p_sam_port/i2p_probe_sam (hitos propios + sonda TCP)
├── sam.rs      # cliente SAMv3 mínimo: HELLO/SESSION TRANSIENT/STREAM CONNECT
├── tunnel.rs   # i2p_http_get(url)/i2p_download(url,dest)->u64 — HTTP/1.1 sobre el stream
└── hosts.rs    # resolución nombre.i2p→destino base64 (hosts.txt mirrors + caché 7d)

lib/services/i2p_service.dart   # singleton espejo TorService (refresh cachea estado)
lib/screens/i2p_test_screen.dart# panel opciones: estado/iniciar/detener/sonda +
                                #   publicar switch + campos libres GET y descarga
settings_screen.dart            # ListTile "I2P (experimental)" debajo de Tor
```

### Decisiones
| Tema | Valor |
|---|---|
| Puertos | TODOS elegidos libres al azar por Dart (`_freePort()`): SAMv3 TCP, transports. Nada fijo, nada pisa a Tor SOCKS5 |
| Publicar direcciones | `publish_ipv4/6 = publicar` param, default OFF (tras CGNAT nadie alcanza el puerto); switch en el panel, solo cambia con router apagado |
| IPv6 | ACTIVO siempre (`ipv4:true, ipv6:true`) |
| PQ | ML-KEM-768 activo (como ejemplo oficial) |
| Transit tunnels | Como el ejemplo oficial (max 1000) |
| Reseed | Solo primer boot (después usa NetDb + disco) |
| Nombres `.i2p` | hosts.txt de mirrors claros con caché 7d; `xxx.b32.i2p` y destinos base64 funcionan sin hosts.txt |
| Ciclo | Router vive a nivel app hasta stop explícito; is_finished() detecta muertes silenciosas |

### Pendiente
- **Enchufe al browser** (botón/opciones web): ProxyController del WebView apuntando a… decisión
  futura — hoy NO hay puente local; si el WebView necesita proxy se evaluará entonces
- Persistencia del switch "publicar" (hoy es por sesión)
- cargo-deny en CI (allowlist permissive-only)

## 3. Riesgos CI conocidos
- API emissary 0.4.0 tomada VERBATIM del ejemplo oficial del repo (imports exactos)
- Crate nuevo grande (~93k líneas core): compile time sube; fix-push si algo
