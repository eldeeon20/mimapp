# tor_pr_app.md — Tor embebido en pr_app vía arti

Estado: PLAN · Fecha: 2026-08-25 · Autor: ox-alpha (Agente A)

## 1. Objetivo

Cliente Tor completo embebido en la app (sin binario externo, sin C-tor):
`arti-client` en el crate Rust existente expuesto por FRB como proxy **SOCKS5
en localhost**. Casos de uso: tráfico de Nostr/torrent/HF/IPFS anonimizado,
acceso a servicios .onion, modo privado on-demand.

Referencia porteada: [Foundation-Devices/tor](https://github.com/Foundation-Devices/tor)
(plugin Flutter+FRB+cargokit, código MIT, 227 líneas de Rust).

## 2. Licencias — evidencia y decisión

| Pieza | Licencia | Verificado |
|---|---|---|
| Plugin Foundation | MIT | LICENSE del repo |
| `arti-client 0.36`, `arti 1.7`, todos los `tor-*` | MIT OR Apache-2.0 | crates.io/docs.rs |
| Único LGPL del universo arti | `equix`, `hashx` (EquiX PoW anti-DoS de onion services) | `maint/check-licenses` de arti (`LGPL_30_OK`) |
| Camino que los arrastra | feature `hs-pow-full` (o `experimental`) | docs.rs features |
| Lockfile de Foundation (5856 líneas) | **cero** equix/hashx | grep Cargo.lock |

**Decisión pr_app**: defaults de licencia limpia, dos reglas duras:

1. NUNCA activar `hs-pow-full` ni `experimental` → no entra LGPL.
   `onion-service-client` SÍ se usa (solo conectarse a .onion, trae
   `tor-hsclient`+`tor-hscrypto`, ambos MIT/Apache).
2. TLS = el mismo stack que ya corre en la app: **rustls 0.23 + ring**
   (`reqwest rustls-tls`, `librqbit rust-tls`). Cargo unifica versiones →
   una sola copia de rustls/ring en el binario. **Cero OpenSSL** (Foundation
   usa native-tls default + static → OpenSSL estático: lo evitamos).

## 3. Dependencias (rust/Cargo.toml)

```toml
# --- Tor embebido (arti, cliente SOCKS5 local) ---
# NOTA LICENCIA: sin hs-pow-full/experimental => árbol 100% MIT/Apache.
# rustls+ring reutiliza el TLS de la app (reqwest/librqbit). Sin OpenSSL.
arti-client = { version = "=0.36.0", default-features = false,
                features = ["tokio", "rustls", "compression", "onion-service-client"] }
tor-rtcompat = { version = "=0.36.0", features = ["tokio", "rustls"] }
tor-config = "=0.36.0"
```

Versiones pineadas con `=` igual que la política del repo (nostr/pkarr).
`arti = "1.7"` solo si necesitamos `arti::proxy::run_proxy`; alternativa:
usar `TorClient::connect()` directo por-stream y exponer un SOCKS5 mínimo
escrito por nosotros (~150 líneas, menos deps). **Decisión inicial**:
porte 1:1 del proxy de Foundation (`arti::proxy`) porque ya está probado;
si el crate `arti` pesa demasiado, se baja al SOCKS5 propio.

## 4. Rust — `rust/src/api/tor.rs`

Porte de la API de Foundation adaptada a rustls:

```rust
// runtime: TokioRustlsRuntime (NO TokioNativeTlsRuntime)
use tor_rtcompat::rustls::TokioRustlsRuntime;

static CLIENT: Mutex<Option<Arc<TorClient<TokioRustlsRuntime>>>>;

pub struct TorStatus { pub bootstrapped: bool, pub phase: String }

#[frb] pub async fn tor_start(state_dir: String, cache_dir: String, socks_port: u16)
    -> Result<String, String>   // bootstrapea y levanta el proxy; % por callback/stream
#[frb] pub fn tor_stop() -> Result<(), String>
#[frb] pub fn tor_status() -> TorStatus
#[frb] pub fn tor_set_dormant(soft: bool)          // batería
#[frb] pub fn tor_rebootstrap() -> Result<(), String>  // cambio de red
#[frb] pub fn tor_socks_port() -> Option<u16>
```

Detalles heredados de Foundation (ya resueltos ahí):
- `allow_onion_addrs(true)`; circuitos preventivos ajustados para móvil
  (`disable_at_threshold(1)`, `min_exit_circs_for_port(1)`).
- Proxy en tarea tokio aparte; stop = abort del JoinHandle (idempotente).
- `set_nofile_limit` antes de bootstrapear (Android tiene FDs bajos).
- Paths absolutos bajo `<appSupport>/tor/{state,cache}` (regla errno=30 ya
  aprendida con IPFS: nada de paths relativos contra CWD Android).
- Bootstrapeo bloqueante de varios segundos → función `async` FRB para no
  trabar la UI.

## 5. Dart

- `lib/services/tor_service.dart` — singleton ChangeNotifier:
  estado (off / bootstrapping % / listo / error), start/stop/dormant,
  `socksProxy` expuesto como `host:port` para otros servicios.
- `lib/screens/tor_test_screen.dart` — botón iniciar (progreso de fases),
  estado de circuitos, test fetch HTTP vía SOCKS5 (ej. check.torproject.org),
  toggle dormant, log. Entrada SIN icono radial nuevo: acción dentro de
  Ajustes o del menú de red (definir al cablear).
- Consumo opcional posterior: flag global `Settings.useTor` que haga que
  reqwest-side APIs pasen por `socks5://127.0.0.1:<port>`.

## 6. Auditoría de licencias en CI

`cargo-deny` (nueva step en el workflow de Android, corre antes del build):

```toml
# deny.toml (raíz de rust/)
[licenses]
allow = ["MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC",
         "Zlib", "BSL-1.0", "Unicode-3.0", "CDLA-Permissive-2.0", "CC0-1.0"]
# LGPL/GPL/AGPL/MPL: denegadas por omisión → falla el build si algo entra
```

Prueba reproducible: si alguien agrega una feature que jala `equix`/`hashx`
(u otro copyleft), CI rojo con el nombre del crate culpable.

## 7. Riesgos abiertos

| Riesgo | Mitigación |
|---|---|
| Provider de rustls de tor-rtcompat vs el nuestro (ring) | fijar feature `rustls` y verificar en el primer build; si duplica ring, pin común |
| Peso del crate `arti` completo (binario +MB) | si molesta: SOCKS5 propio sobre `TorClient::connect` (plan B §3) |
| Bootstrapeo lento/red hostil en CI-emulador | no testear bootstrap en CI, solo compile+lint |
| Codegen FRB nuevo módulo | patrón ya probado (needle/nostr_busca/ipfs) |

## 8. Orden de trabajo

1. Cargo.toml (deps §3) + `rust/src/api/tor.rs` (§4) + mod.rs.
2. `cargo-deny`: deny.toml + step CI.
3. `tor_service.dart` + `tor_test_screen.dart` + wiring.
4. Balance local + ciclo fix-push del usuario.
