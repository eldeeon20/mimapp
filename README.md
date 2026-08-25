# mimapp

App **multiplataforma** (Android primero) hecha con **Flutter + Rust**, unida por
[flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/). Todo lo pesado vive en Rust:
redes P2P, IA local, cifrado, spiders. La UI es Flutter puro, navegable desde un **menú radial**.

## Qué hay adentro

| Módulo | Qué hace |
|---|---|
| **Needle** | IA de chat local en el dispositivo (Candle/Mistral 7B cuantizado), sin nube |
| **Nostrn+** | red social sobre Nostr: posts, likes, replies, perfiles, DMs, subida de imágenes Blossom |
| **Tor** | tráfico onion para las funciones de red sensibles (arti + socks) |
| **DHT Busca** | spider Kademlia BitTorrent: descubre y lista torrents en vivo (fork mainline vendido) |
| **Iroh P2P** | transferencia directa de archivos por ticket BLAKE3 + **chat directo estilo DM** entre dos peers, sin servidor |
| **Navegador in-app** | webview con pestañas, cookies y modo I2P planificado |

## Arquitectura

```
lib/                    Flutter (pantallas + servicios Dart)
├─ app/                 app raíz, menú radial, rutas
├─ screens/             una pantalla por función (needle, nostrn, iroh_test, dht_busca…)
├─ services/            puentes finos hacia los APIs generados por FRB
└─ src/rust/api/        bindings generados (no editar a mano)

rust/
├─ src/api/             API pública por módulo (wrappers legibles, errores traducidos)
├─ src/gt/              motor real: needle/, gestion.rs (social), dhtbusca/, irohp2p.rs, tor…
├─ mainline/            fork de mainline vendido (el upstream borró los tipos que necesitábamos)
└─ Cargo.toml           workspace único; iroh 1.x, librqbit 9, arti, candle…

web_inapp_i2p.md        plan del navegador in-app con I2P
```

Convenciones clave:
- **Constructores top-level** (`motorDhtNew`, `irohNuevo`) porque FRB no soporta ctors sync con Result.
- **Objetos opacos** (`IrohViva`, `MotorDht`) con helper interno `con()/con_mut()`.
- Los métodos async corren en workers tokio de FRB → **nunca `block_on` dentro**; se usa `bloquea()`
  (spawn en runtime propio + canal).
- Errores siempre en castellano y accionables, nunca crudos.

## Probar Iroh entre dos dispositivos

1. En ambos: menú radial → **Iroh** → *Iniciar nodo*.
2. Peer 1 copia su **ticket de conexión** (o el ticket de un archivo ofrecido).
3. Peer 2 lo pega:
   - ticket de conexión → abre **chat directo** (burbujas yo/par, sin servidor);
   - ticket de archivo → baja el contenido verificado por BLAKE3.
