//! DHT Busca: spider de la red Mainline (Kademlia BitTorrent) que atrapa
//! info_hashes y resuelve sus metadatos, para armar un índice local
//! buscable por texto.
//!
//! - NODO: corre en modo servidor → ayuda a la red como nodo de ruteo.
//! - PASIVO: cada get_peers/announce_peer que llega de otros revela un
//!   info_hash → capturado con RequestFilter (atrapa TODO).
//! - ACTIVO: get_peers(Id::random()) a ritmo moderado + ráfagas find_node
//!   para crecer la tabla de ruteo.
//! - METADATOS: librqbit trae nombre/tamaño/archivos SIN bajar contenido;
//!   torrent evictado tras resolver (solo indexamos).
//!
//! Kademlia NO tiene búsqueda por nombre: se busca texto sobre el índice
//! local acumulado acá. Mismo enfoque del crawler de referencia.

use anyhow::{anyhow, Context, Result};
use librqbit::{
    AddTorrent, AddTorrentOptions, DhtSessionConfig, ListenerMode, ListenerOptions, Session,
    SessionOptions, SessionPersistenceConfig,
};
use librqbit::dht::DhtPersistenceConfig;
use mainline::{
    Dht, GetPeersRequestArguments, Id, PutRequest, PutRequestSpecific, RequestFilter,
    RequestTypeSpecific, ServerSettings,
};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
use std::net::{Ipv4Addr, SocketAddrV4, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::Semaphore;

use crate::gt::eventlog::EventLog;

/// Hashes esperando metadatos se rinden pasado este tiempo (se libera el
/// slot para nuevos; el torrent queda en la sesión y se indexa si resuelve).
const PENDING_TIMEOUT: Duration = Duration::from_secs(180);
/// Tope de espera por hash al pedir metadatos: si no resuelve en este
/// tiempo, se suelta y sigue con el siguiente. Nunca nos quedamos colgados
/// en un solo hash cuando hay varios en cola.
const RESOLVE_TIMEOUT: Duration = Duration::from_secs(60);
/// Ritmo activo moderado (~10 consultas/seg) para no saturar la red.
const TICK_ACTIVO: Duration = Duration::from_millis(100);
/// Tope duro del índice en RAM (los más viejos se recortan al guardar).
const TOPE_INDICE: usize = 20_000;
/// Tope de resoluciones de metadatos concurrentes hacia rqbit. Acota cuántos
/// `add_torrent` corren a la vez para no saturar la red/DHT ni hacer un
/// cuello de botella cuando llegan muchos hashes de golpe (30-50).
const MAX_CONCURRENT_META: usize = 8;

const BOOTSTRAP: &[&str] = &[
    "router.bittorrent.com:6881",
    "router.utorrent.com:6881",
    "dht.transmissionbt.com:6881",
    "router.bitcomet.com:6881",
    "dht.libtorrent.org:25401",
    "dht.aelitis.com:6881",
];

// ------------------------------------------------------------------ datos

#[derive(Clone, Serialize, Deserialize)]
pub struct Hallado {
    pub info_hash: String,
    pub nombre: String,
    pub tamano: u64,
    pub archivos: usize,
    pub fecha_ms: i64,
    #[serde(default)]
    pub creation_date: String,
    #[serde(default)]
    pub comment: String,
}

/// Captura en vivo: cada hash interceptado por el spider, con estado de
/// resolución. Se muestra en la UI para que el usuario vea qué está
/// atrapando en tiempo real (la lista de "hashes"), aparte de los metadatos
/// ya resueltos.
#[derive(Clone)]
pub(crate) struct Captura {
    pub hash: String,
    pub nombre: String,
    pub resuelto: bool,
}

#[derive(Clone, Default, Serialize, Deserialize)]
struct Estado {
    hallados: Vec<Hallado>,
    pedidos: Arc<AtomicU64>,
}

fn ahora_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Ping KRPC find_node a cada semilla bootstrap: distingue en segundos
/// entre "red bloquea UDP", "semillas mudas" y "nodo vivo".
fn ping_semillas(
    logs: crate::gt::eventlog::EventLog,
    ok: Arc<AtomicU64>,
    tot: Arc<AtomicU64>,
) {
    for semilla in BOOTSTRAP {
        tot.fetch_add(1, Ordering::Relaxed);
        // 1 · DNS
        let addrs: Vec<_> = match semilla.to_socket_addrs() {
            Ok(a) => a.collect(),
            Err(e) => {
                logs.push(format!("seed {semilla}: DNS ✗ ({e})"));
                continue;
            }
        };
        let Some(destino) = addrs.into_iter().next() else {
            logs.push(format!("seed {semilla}: DNS sin direcciones"));
            continue;
        };
        // 2 · paquete KRPC find_node mínimo
        let id = [0x07u8; 20];
        let target = [0x03u8; 20];
        let mut pkt = Vec::with_capacity(98);
        pkt.extend_from_slice(b"d1:ad2:id20:");
        pkt.extend_from_slice(&id);
        pkt.extend_from_slice(b"6:target20:");
        pkt.extend_from_slice(&target);
        pkt.extend_from_slice(b"e1:q9:find_node1:t2:aa1:y1:qe");
        // 3 · enviar y esperar respuesta corta
        let sock = std::net::UdpSocket::bind("0.0.0.0:0");
        let sock = match sock {
            Ok(s) => s,
            Err(e) => {
                logs.push(format!("seed {semilla}: UDP local ✗ ({e})"));
                continue;
            }
        };
        let _ = sock.set_read_timeout(Some(Duration::from_secs(3)));
        if sock.send_to(&pkt, destino).is_err() {
            logs.push(format!("seed {semilla}: envío ✗"));
            continue;
        }
        let mut buf = [0u8; 1400];
        match sock.recv_from(&mut buf) {
            Ok((n, _)) => {
                ok.fetch_add(1, Ordering::Relaxed);
                logs.push(format!(
                    "seed {semilla}: ✓ respondió ({n} B)"
                ));
            }
            Err(_) => {
                logs.push(format!(
                    "seed {semilla}: ✗ sin respuesta en 3s (UDP bloqueado o muda)"
                ));
            }
        }
    }
}

// ----------------------------------------------------------------- filtro

/// Captura TODOS los info_hashes que pasan por nuestro nodo.
#[derive(Clone, Debug)]
struct FiltroAtrapador {
    tx: Arc<Sender<String>>,
    vistos: Arc<AtomicU64>,
    /// TODO request que cruza el nodo (diagnóstico de sordera: si esto
    /// queda en 0 la red bloquea UDP o el bootstrap no llegó a nadie).
    pedidos: Arc<AtomicU64>,
}

impl FiltroAtrapador {
    fn captura(&self, hash: String) {
        self.vistos.fetch_add(1, Ordering::Relaxed);
        let _ = self.tx.send(hash);
    }
}

impl RequestFilter for FiltroAtrapador {
    fn allow_request(&self, request: &mainline::RequestSpecific, _from: SocketAddrV4) -> bool {
        self.pedidos.fetch_add(1, Ordering::Relaxed);
        let hash = match &request.request_type {
            RequestTypeSpecific::GetPeers(GetPeersRequestArguments { info_hash }) => {
                hex_id(info_hash)
            }
            RequestTypeSpecific::Put(PutRequest {
                put_request_type: PutRequestSpecific::AnnouncePeer(args),
                ..
            }) => hex_id(&args.info_hash),
            _ => return true,
        };
        self.captura(hash);
        true
    }
}

fn hex_id(id: &Id) -> String {
    id.as_bytes().iter().map(|b| format!("{b:02x}")).collect()
}

/// Parse root-level creation date and comment from full torrent bytes (when present).
/// `torrent_bytes` es `Bytes` (siempre presente) en librqbit 9.
fn parse_root_metadata(torrent_bytes: &[u8]) -> (String, String) {
    let root = match librqbit::torrent_from_bytes(torrent_bytes) {
        Ok(r) => r,
        Err(_) => return (String::new(), String::new()),
    };
    let creation_date = root
        .creation_date
        .map(|ts| {
            chrono::DateTime::from_timestamp(ts as i64, 0)
                .map(|dt| dt.format("%Y-%m-%d %H:%M").to_string())
                .unwrap_or_else(|| ts.to_string())
        })
        .unwrap_or_default();
    let comment = root
        .comment
        .as_ref()
        .map(|c| String::from_utf8_lossy(c.as_ref()).into_owned())
        .unwrap_or_default();
    (creation_date, comment)
}

// -------------------------------------------------------------- el motor

pub struct DhtBusca {
    stop: Arc<AtomicBool>,
    hilo_spider: Option<JoinHandle<()>>,
    indice: Arc<Mutex<Estado>>,
    nuevos_desde_poll: Arc<Mutex<Vec<String>>>,
    stats: Arc<Mutex<Stats>>,
    vistos: Arc<AtomicU64>,
    pedidos: Arc<AtomicU64>,
    semillas_ok: Arc<AtomicU64>,
    semillas_total: Arc<AtomicU64>,
    canal: Mutex<Option<Arc<Sender<String>>>>,
    logs: EventLog,
    dir_cache: PathBuf,
    runtime: Arc<tokio::runtime::Runtime>,
    max_meta: usize,
    /// Handle vivo del nodo DHT, compartido entre el hilo spider y el loop de
    /// metadatos (solo lectura vía lock corto; el Dht no es Clone).
    dht: Arc<Mutex<Option<Dht>>>,
    /// Base de capturas en vivo (cada hash interceptado, con estado de
    /// resolución). Se expone a la UI como la lista de "hashes".
    capturas: Arc<Mutex<VecDeque<Captura>>>,
    /// true = el spider hace sondeo de hashes aleatorios (get_peers sobre ids
    /// random). false = solo captura pasiva (lo que otros buscan de verdad).
    /// El find_node de mantenimiento de tabla Kademlia NO se desactiva con esto.
    pub(crate) sondear_aleatorio: Arc<AtomicBool>,
}

#[derive(Clone, Default, serde::Serialize)]
pub struct Stats {
    pub nodos_tabla: usize,
    /// semillas bootstrap que respondieron UDP / total probadas
    pub semillas_ok: u64,
    pub semillas_total: u64,
    pub capturados: u64,
    /// requests DHT de CUALQUIER tipo que cruzaron el nodo. Si queda en 0
    /// con el spider corriendo => red bloquea UDP o bootstrap sin pares.
    pub pedidos: u64,
    pub resueltos: usize,
    pub pendientes: usize,
}

impl DhtBusca {
    /// Carga caché previa y prepara el motor (no conecta todavía).
    pub fn new(dir_cache: &str, max_meta: usize) -> Result<Self> {
        let dir = PathBuf::from(dir_cache);
        std::fs::create_dir_all(&dir).map_err(|e| anyhow!("creando {dir_cache}: {e}"))?;
        let indice = cargar(&dir.join("dhtbusca.json"))?;
        Ok(Self {
            stop: Arc::new(AtomicBool::new(false)),
            hilo_spider: None,
            indice: Arc::new(Mutex::new(indice)),
            nuevos_desde_poll: Arc::new(Mutex::new(Vec::new())),
            stats: Arc::new(Mutex::new(Stats::default())),
            vistos: Arc::new(AtomicU64::new(0)),
            pedidos: Arc::new(AtomicU64::new(0)),
            semillas_ok: Arc::new(AtomicU64::new(0)),
            semillas_total: Arc::new(AtomicU64::new(0)),
            canal: Mutex::new(None),
            logs: EventLog::new(),
            dir_cache: dir,
            dht: Arc::new(Mutex::new(None)),
            capturas: Arc::new(Mutex::new(VecDeque::new())),
            sondear_aleatorio: Arc::new(AtomicBool::new(true)),
            runtime: Arc::new(
                tokio::runtime::Builder::new_multi_thread()
                    .worker_threads(2)
                    .enable_all()
                    .build()
                    .context("runtime tokio")?,
            ),
            max_meta: max_meta.clamp(10, 2000),
        })
    }

    /// Arranca nodo servidor + hilos de captura y metadatos.
    /// `pasivo`/`activo` se pueden combinar; con ambos apagados no hace nada.
    pub fn start(&mut self, pasivo: bool, activo: bool) -> Result<()> {
        if self.hilo_spider.is_some() {
            return Err(anyhow!("el spider ya está corriendo"));
        }
        if !pasivo && !activo {
            return Err(anyhow!("activá pasivo o activo (o ambos)"));
        }
        self.stop.store(false, Ordering::SeqCst);

        let (tx_hash, rx_hash): (_, Receiver<String>) = channel();
        let tx_filtro: Arc<Sender<String>> = Arc::new(tx_hash.clone());
        *self.canal.lock().unwrap_or_else(|e| e.into_inner()) =
            Some(tx_filtro.clone());
        let vistos_hilo = self.vistos.clone();
        let pedidos_hilo = self.pedidos.clone();
        let sem_ok = self.semillas_ok.clone();
        let sem_tot = self.semillas_total.clone();
        let logs_ping = self.logs.clone();
        let stop = self.stop.clone();
        let logs = self.logs.clone();
        let dht_arc = self.dht.clone();
        let sondear = self.sondear_aleatorio.clone();

        // diagnóstico inmediato: ¿nuestra red deja salir UDP?
        {
            let l = logs_ping.clone();
            let ok = sem_ok.clone();
            let tot = sem_tot.clone();
            std::thread::Builder::new()
                .name("dhtbusca-seeds".into())
                .spawn(move || ping_semillas(l, ok, tot))
                .ok();
        }

        // Filtro que atrapa TODOS los info_hashes que cruzan el nodo
        // (entran por get_peers/announce_peer de otros pares).
        let filtro = || {
            Box::new(FiltroAtrapador {
                tx: tx_filtro.clone(),
                vistos: vistos_hilo.clone(),
                pedidos: pedidos_hilo.clone(),
            }) as Box<dyn RequestFilter>
        };

        // Construye el nodo servidor. Fija el puerto 6881 para que el reenvío
        // UPnP/NAT-PMP apunte al socket real: si escucha en un puerto efímero
        // el nodo queda sordo a lo entrante y la captura pasiva da 0 aunque la
        // red salga (ese es el bug de "nodos 0 / nada entra").
        let dht = match Dht::builder()
            .server_mode()
            .server_settings(ServerSettings {
                filter: filtro(),
                ..ServerSettings::default()
            })
            .bind_address(Ipv4Addr::UNSPECIFIED)
            .port(6881)
            .bootstrap(BOOTSTRAP)
            .request_timeout(Duration::from_secs(10))
            .build()
        {
            Ok(d) => d,
            Err(e) => {
                logs.push(format!(
                    "✗ bind 6881 falló ({e:?}); reintento en puerto efímero (pasivo puede no funcionar)"
                ));
                match Dht::builder()
                    .server_mode()
                    .server_settings(ServerSettings {
                        filter: filtro(),
                        ..ServerSettings::default()
                    })
                    .bootstrap(BOOTSTRAP)
                    .request_timeout(Duration::from_secs(10))
                    .build()
                {
                    Ok(d) => d,
                    Err(e2) => {
                        logs.push(format!("✗ DHT no arrancó: {e2:?}"));
                        return Err(anyhow!("DHT no arrancó: {e2:?}"));
                    }
                }
            }
        };
        *dht_arc.lock().unwrap_or_else(|e| e.into_inner()) = Some(dht);
        let dht_meta = dht_arc.clone();

        // El DHT vive en su propio hilo (API sync de mainline).
        let builder_thread = std::thread::Builder::new().name("dhtbusca-spider".into());
        let handle = builder_thread.spawn(move || {
            let _ = dht_arc
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .as_ref()
                .unwrap()
                .bootstrapped();
            logs.push("✓ nodo DHT servidor en red · ayudando a rutear");

            let mut vistos: HashSet<[u8; 20]> = HashSet::new();
            let mut ultimo_find_node = Instant::now();
            loop {
                if stop.load(Ordering::SeqCst) {
                    break;
                }
                if activo {
                    if ultimo_find_node.elapsed() >= Duration::from_secs(30) {
                        for _ in 0..5 {
                            let _ = dht_arc
                                .lock()
                                .unwrap_or_else(|e| e.into_inner())
                                .as_ref()
                                .unwrap()
                                .find_node(Id::random());
                        }
                        ultimo_find_node = Instant::now();
                    }
                    // Sondeo de hashes aleatorios: se puede desactivar desde la UI
                    // (botón "Sondeo aleatorio"). Mantiene find_node arriba para
                    // que la tabla Kademlia siga creciendo, pero deja de generar
                    // hashes al azar (solo captura pasiva = torrents reales).
                    if sondear.load(Ordering::SeqCst) {
                        let id = Id::random();
                        vistos.insert(*id.as_bytes());
                        if vistos.len() > 50_000 {
                            vistos.clear();
                        }
                        // como el crawler: si el id aleatorio tiene swarm,
                        // también entra al canal (descubrimiento activo real)
                        let mut iter = dht_arc
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .as_ref()
                            .unwrap()
                            .get_peers(id);
                        if iter.next().is_some() {
                            vistos_hilo.fetch_add(1, Ordering::Relaxed);
                            let _ = tx_filtro.send(hex_id(&id));
                        }
                    }
                    std::thread::sleep(TICK_ACTIVO);
                } else {
                    // solo pasivo: dormir largo, el filter sigue alimentando
                    std::thread::sleep(Duration::from_millis(500));
                }
            }
            logs.push("■ spider detenido");
        })?;
        self.hilo_spider = Some(handle);

        // Resolución de metadatos sobre runtime tokio propio (rqbit async).
        let indice = self.indice.clone();
        let nuevos = self.nuevos_desde_poll.clone();
        let stats = self.stats.clone();
        let vistos_meta = self.vistos.clone();
        let logs_meta = self.logs.clone();
        let dir_tmp = self.dir_cache.join("_meta");
        let stop2 = self.stop.clone();
        let max_meta = self.max_meta;
        let capturas_arc = self.capturas.clone();
        self.runtime.spawn(async move {
            meta_loop(
                rx_hash,
                stop2,
                indice,
                nuevos,
                stats,
                vistos_meta,
                logs_meta,
                dir_tmp,
                max_meta,
                dht_meta,
                capturas_arc,
            )
            .await;
        });

        self.logs.push(format!(
            "✓ spider iniciado (pasivo:{pasivo} activo:{activo} tope_meta:{max_meta})"
        ));
        Ok(())
    }

    pub fn stop(&mut self) -> Result<()> {
        if self.hilo_spider.is_none() {
            return Err(anyhow!("no está corriendo"));
        }
        self.stop.store(true, Ordering::SeqCst);
        *self.canal.lock().unwrap_or_else(|e| e.into_inner()) = None;
        guardar(&self.dir_cache.join("dhtbusca.json"), &self.indice)?;
        self.logs.push("✓ detenido e índice guardado");
        self.hilo_spider = None;
        Ok(())
    }

    /// Nuevos hallazgos desde el poll anterior (para refresco en vivo).
    pub fn poll_nuevos(&self) -> Vec<Hallado> {
        let mut n = self.nuevos_desde_poll.lock().unwrap_or_else(|e| e.into_inner());
        let out: Vec<Hallado> = n
            .iter()
            .filter_map(|h| buscar_exacto(&self.indice, h))
            .collect();
        n.clear();
        out
    }

    /// Búsqueda de texto por nombre sobre TODO el índice acumulado.
    pub fn buscar(&self, texto: &str) -> Vec<Hallado> {
        let q = texto.trim().to_lowercase();
        if q.is_empty() {
            return vec![];
        }
        let est = self.indice.lock().unwrap_or_else(|e| e.into_inner());
        let mut hits: Vec<Hallado> = est
            .hallados
            .iter()
            .filter(|h| h.nombre.to_lowercase().contains(&q))
            .cloned()
            .collect();
        hits.sort_by(|a, b| b.fecha_ms.cmp(&a.fecha_ms));
        hits.truncate(200);
        hits
    }

    /// Índice completo de metadatos resueltos (los persistidos en
    /// dhtbusca.json y recargados al abrir). `limit<=0` = todos. Ordenado
    /// del más nuevo al más viejo. Sirve para poblar la lista RESUELTOS al
    /// iniciar, incluidos los que venían del JSON.
    pub fn resueltos(&self, limit: i32) -> Vec<Hallado> {
        let est = self.indice.lock().unwrap_or_else(|e| e.into_inner());
        let take = if limit <= 0 {
            est.hallados.len()
        } else {
            limit as usize
        };
        let mut v: Vec<Hallado> = est.hallados.iter().cloned().collect();
        v.sort_by(|a, b| b.fecha_ms.cmp(&a.fecha_ms));
        v.truncate(take);
        v
    }

    /// Base de capturas en vivo (cada hash interceptado, con estado de
    /// resolución). `limit<=0` devuelve todas.
    pub(crate) fn capturas(&self, limit: i32) -> Vec<Captura> {
        let g = self.capturas.lock().unwrap_or_else(|e| e.into_inner());
        let take = if limit <= 0 {
            g.len()
        } else {
            limit as usize
        };
        g.iter().rev().take(take).cloned().collect()
    }

    /// Filtra la base por hash o nombre (substring, parcial, case-insensitive).
    pub(crate) fn capturas_filtradas(&self, texto: &str, limit: i32) -> Vec<Captura> {
        let q = texto.trim().to_lowercase();
        let g = self.capturas.lock().unwrap_or_else(|e| e.into_inner());
        let take = if limit <= 0 {
            g.len()
        } else {
            limit as usize
        };
        g.iter()
            .rev()
            .filter(|c| {
                q.is_empty()
                    || c.hash.contains(&q)
                    || c.nombre.to_lowercase().contains(&q)
            })
            .take(take)
            .cloned()
            .collect()
    }

    pub fn total(&self) -> usize {
        self.indice.lock().unwrap_or_else(|e| e.into_inner()).hallados.len()
    }

    pub fn stats(&self) -> Stats {
        let mut st = self.stats.lock().unwrap_or_else(|e| e.into_inner()).clone();
        st.capturados = self.vistos.load(Ordering::Relaxed);
        st.pedidos = self.pedidos.load(Ordering::Relaxed);
        st.semillas_ok = self.semillas_ok.load(Ordering::Relaxed);
        st.semillas_total = self.semillas_total.load(Ordering::Relaxed);
        st
    }

    /// Prueba manual: acepta magnet completo o info_hash hex de 40.
    /// Sirve para diagnosticar si el pipeline funciona en esta red.
    pub fn probar(&self, texto: &str) -> Result<()> {
        let t = texto.trim();
        let hash = if t.starts_with("magnet:") {
            t.split("xt=urn:btih:")
                .nth(1)
                .and_then(|resto| {
                    Some(resto[..40.min(resto.len())].to_string())
                })
                .ok_or_else(|| anyhow!("magnet sin xt=urn:btih:"))?
        } else {
            t.to_string()
        };
        if hash.len() != 40 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(anyhow!(
                "esperaba un info_hash hex de 40 o magnet; got '{}'",
                &hash
            ));
        }
        let canal = self.canal.lock().unwrap_or_else(|e| e.into_inner());
        let tx = canal
            .as_ref()
            .ok_or_else(|| anyhow!("el spider no está corriendo"))?;
        let _ = tx.send(hash.to_lowercase());
        self.logs.push(format!("✓ magnet de prueba inyectado"));
        Ok(())
    }

    /// Guarda el índice a disco sin parar el spider.
    pub fn guardar_ahora(&self) -> Result<()> {
        guardar(&self.dir_cache.join("dhtbusca.json"), &self.indice)
    }

    pub fn take_logs(&self) -> Vec<String> {
        self.logs.drain()
    }
}

impl Drop for DhtBusca {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        let _ = guardar(&self.dir_cache.join("dhtbusca.json"), &self.indice);
    }
}

// ------------------------------------------------------------- metadatos

#[allow(clippy::too_many_arguments)]
async fn meta_loop(
    rx: Receiver<String>,
    stop: Arc<AtomicBool>,
    indice: Arc<Mutex<Estado>>,
    nuevos: Arc<Mutex<Vec<String>>>,
    stats: Arc<Mutex<Stats>>,
    vistos_meta: Arc<AtomicU64>,
    logs: EventLog,
    dir_tmp: PathBuf,
    max_meta: usize,
    dht_arc: Arc<Mutex<Option<Dht>>>,
    capturas: Arc<Mutex<VecDeque<Captura>>>,
) {
    let _ = std::fs::create_dir_all(&dir_tmp);
    let mut aviso_sordo = false;
    // MISMA receta que el test de rqbit que SÍ resuelve (api/torrent/session.rs):
    // Session::new por defecto DEJA EL DHT DESHABILITADO, por eso un magnet
    // nunca encontraba pares y no se resolvía. Hay que habilitar DHT, dar
    // persistencia y un listen. Con esto rqbit resuelve info_hashes reales.
    let mut sopts = SessionOptions::default();
    sopts.persistence = Some(SessionPersistenceConfig::Json {
        folder: Some(dir_tmp.clone()),
    });
    sopts.dht = Some(DhtSessionConfig {
        persistence: Some(DhtPersistenceConfig {
            config_filename: Some(dir_tmp.join("dht.json")),
            ..Default::default()
        }),
        ..Default::default()
    });
    sopts.listen = Some(ListenerOptions {
        mode: ListenerMode::TcpAndUtp,
        listen_addr: "[::]:0".parse::<std::net::SocketAddr>().unwrap(),
        enable_upnp_port_forwarding: true,
        utp_opts: None,
        announce_port: None,
        ipv4_only: false,
        max_pending_incoming_handshake_checks: 256,
    });
    sopts.fastresume = true;
    let session = match Session::new_with_opts(dir_tmp.clone(), sopts).await {
        Ok(s) => s,
        Err(e) => {
            logs.push(format!("✗ rqbit Session: {e:?}"));
            return;
        }
    };

    // Semáforo: a lo sumo MAX_CONCURRENT_META resoluciones de metadatos
    // corriendo a la vez. Así si llegan 30-50 hashes de golpe no saturan la
    // red/DHT ni se forma un cuello de botella: se encolan y se resuelven de
    // a MAX_CONCURRENT_META, cada una con su propio RESOLVE_TIMEOUT.
    let sem = Arc::new(Semaphore::new(MAX_CONCURRENT_META));

    let mut pendientes: HashMap<String, Instant> = HashMap::new();

    while !stop.load(Ordering::SeqCst) {
        // 1) drenar hashes entrantes respetando el tope concurrente
        loop {
            match rx.try_recv() {
                Ok(hash) => {
                    if hash.len() != 40 || pendientes.contains_key(&hash) {
                        continue;
                    }
                    if ya_indexado(&indice, &hash) {
                        continue;
                    }
                    if pendientes.len() >= max_meta {
                        if let Some((viejo, _)) =
                            pendientes.iter().min_by_key(|(_, t)| **t).map(|(k, t)| (k.clone(), *t))
                        {
                            pendientes.remove(&viejo);
                        }
                    }
                    let magnet = format!("magnet:?xt=urn:btih:{hash}");
                    pendientes.insert(hash.clone(), Instant::now());
                    // Registrar en la base de capturas en vivo (estado: resolviendo).
                    {
                        let mut cap =
                            capturas.lock().unwrap_or_else(|e| e.into_inner());
                        if cap.len() >= 5000 {
                            cap.pop_back();
                        }
                        if !cap.iter().any(|c| c.hash == hash) {
                            cap.push_front(Captura {
                                hash: hash.clone(),
                                nombre: String::new(),
                                resuelto: false,
                            });
                        }
                    }
                    let s = session.clone();
                    let sem = sem.clone();
                    tokio::spawn(async move {
                        // Espera un slot del semáforo antes de tocar rqbit.
                        let _permit = match sem.acquire().await {
                            Ok(p) => p,
                            Err(_) => return,
                        };
                        let add = AddTorrent::Url(magnet.into());
                        // paused: rqbit AGREGA el torrent a la sesión (así
                        // with_torrents lo cosecha) pero NO baja el contenido.
                        // overwrite por si reaparece. Sin DHT no resolvía nada;
                        // la sesión ahora viene con DHT habilitado (ver arriba).
                        let opts = AddTorrentOptions {
                            overwrite: true,
                            paused: true,
                            ..Default::default()
                        };
                        // No nos quedamos esperando para siempre un hash: si no
                        // resuelve en RESOLVE_TIMEOUT, soltamos y seguimos con
                        // el siguiente. El torrent queda en la sesión; si luego
                        // resuelve, el cosechado lo indexa igual.
                        let _ = tokio::time::timeout(
                            RESOLVE_TIMEOUT,
                            s.add_torrent(add, Some(opts)),
                        )
                        .await;
                    });
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => break,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => return,
            }
        }

        // 2) evictar los atascados
        let ahora = Instant::now();
        pendientes.retain(|_, t| ahora.duration_since(*t) < PENDING_TIMEOUT);

        // 3) cosechar metadatos listos con with_torrents (API estable 9.x):
        // name/archivos/tamaño + torrent_bytes (creation_date/comentario).
        let cosechados_celd: std::cell::RefCell<Vec<Hallado>> = std::cell::RefCell::new(Vec::new());
        session.with_torrents(|iter| {
            for (_idx, tor) in iter {
                let hash = tor.info_hash().as_string();
                // Cosechar todo lo que ya tenga metadato y NO esté indexado:
                // así un hash lento que resuelve después de soltarse también
                // entra. No dependemos de seguir en `pendientes`.
                if ya_indexado(&indice, &hash) {
                    continue;
                }
                let got: Option<Hallado> = tor
                    .with_metadata(|meta| {
                        let nombre = meta.info.name().unwrap_or_default().to_string();
                        if nombre.is_empty() {
                            return None;
                        }
                        let tamano = meta.info.iter_file_lengths().sum::<u64>();
                        let archivos = meta.info.iter_file_lengths().count();
                        let (creation_date, comment) =
                            parse_root_metadata(meta.torrent_bytes.as_ref());
                        Some(Hallado {
                            info_hash: hash.clone(),
                            nombre: nombre.chars().take(200).collect(),
                            tamano,
                            archivos,
                            fecha_ms: ahora_ms(),
                            creation_date,
                            comment,
                        })
                    })
                    .ok()
                    .flatten();
                if let Some(h) = got {
                    cosechados_celd.borrow_mut().push(h);
                }
            }
        });
        let cosechados = cosechados_celd.into_inner();
        for h in &cosechados {
            pendientes.remove(&h.info_hash);
        }
        // Marcar en la base de capturas los que ya resolvieron su metadato.
        {
            let mut cap = capturas.lock().unwrap_or_else(|e| e.into_inner());
            for h in &cosechados {
                if let Some(c) = cap.iter_mut().find(|c| c.hash == h.info_hash) {
                    c.resuelto = true;
                    c.nombre = h.nombre.clone();
                }
            }
        }

        if !cosechados.is_empty() {
            {
                let mut est = indice.lock().unwrap_or_else(|e| e.into_inner());
                for h in &cosechados {
                    if !est.hallados.iter().any(|x| x.info_hash == h.info_hash) {
                        est.hallados.push(h.clone());
                    }
                }
                if est.hallados.len() > TOPE_INDICE {
                    let exceso = est.hallados.len() - TOPE_INDICE;
                    est.hallados.drain(0..exceso);
                }
            }
            {
                let mut n = nuevos.lock().unwrap_or_else(|e| e.into_inner());
                n.extend(cosechados.iter().map(|h| h.info_hash.clone()));
            }
            logs.push(format!("✓ {} nuevo(s) indexado(s)", cosechados.len()));
        }

        // 4) stats vivos
        // nodos_tabla = muestra real de la tabla de ruteo (cercanos a un id
        // aleatorio). Antes estaba hardcodeado en 0: por eso la UI mostraba
        // "Kademlia: 0 nodos" siempre.
        let nodos = dht_arc
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .map(|d| d.get_closest_nodes(Id::random()).len())
            .unwrap_or(0);
        let (semillas_ok, pedidos) = {
            let s = stats.lock().unwrap_or_else(|e| e.into_inner());
            (s.semillas_ok, s.pedidos)
        };
        {
            let mut st = stats.lock().unwrap_or_else(|e| e.into_inner());
            st.nodos_tabla = nodos;
            st.resueltos = indice.lock().unwrap_or_else(|e| e.into_inner()).hallados.len();
            st.pendientes = pendientes.len();
            st.capturados = vistos_meta.load(Ordering::Relaxed);
        }
        // Diagnóstico único: UDP sale (semillas responden) pero nada entra =>
        // falta reenviar el 6881 en el router para la captura pasiva.
        if !aviso_sordo && semillas_ok > 0 && pedidos == 0 {
            aviso_sordo = true;
            logs.push(
                "⚠ UDP sale (semillas responden) pero 0 paquetes entran: el nodo \
                 necesita el puerto 6881 reenviado (UPnP/NAT-PMP) y el DHT debe \
                 escuchar en 6881 para captura pasiva."
                    .to_string(),
            );
        }

        tokio::time::sleep(Duration::from_secs(2)).await;
    }
    logs.push("■ resolución de metadatos terminada");
}

// ---------------------------------------------------------------- helpers

fn ya_indexado(indice: &Arc<Mutex<Estado>>, hash: &str) -> bool {
    indice
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .hallados
        .iter()
        .any(|h| h.info_hash == hash)
}

fn buscar_exacto(indice: &Arc<Mutex<Estado>>, hash: &str) -> Option<Hallado> {
    indice
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .hallados
        .iter()
        .find(|h| h.info_hash == hash)
        .cloned()
}

fn ruta_cache(p: &Path) -> String {
    p.to_string_lossy().into_owned()
}

fn cargar(p: &Path) -> Result<Estado> {
    if !p.exists() {
        return Ok(Estado::default());
    }
    let bytes = std::fs::read(p).map_err(|e| anyhow!("leyendo {}: {e}", ruta_cache(p)))?;
    serde_json::from_slice(&bytes).context(format!("JSON corrupto: {}", ruta_cache(p)))
}

fn guardar(p: &Path, indice: &Arc<Mutex<Estado>>) -> Result<()> {
    let est = indice.lock().unwrap_or_else(|e| e.into_inner());
    let tmp = p.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_vec(&*est)?)
        .map_err(|e| anyhow!("escribiendo {}: {e}", ruta_cache(&tmp)))?;
    std::fs::rename(&tmp, p).map_err(|e| anyhow!("renombrando {}: {e}", ruta_cache(p)))?;
    Ok(())
}
