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
use mainline::{
    Dht, GetPeersRequestArguments, Id, PutRequest, PutRequestSpecific, RequestFilter,
    RequestTypeSpecific, ServerSettings,
};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::net::SocketAddrV4;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::gt::eventlog::EventLog;

/// Hashes esperando metadatos se rinden a los 5 minutos.
const PENDING_TIMEOUT: Duration = Duration::from_secs(300);
/// Ritmo activo moderado (~10 consultas/seg) para no saturar la red.
const TICK_ACTIVO: Duration = Duration::from_millis(100);
/// Tope duro del índice en RAM (los más viejos se recortan al guardar).
const TOPE_INDICE: usize = 20_000;

const BOOTSTRAP: &[&str] = &[
    "router.bittorrent.com:6881",
    "router.utorrent.com:6881",
    "dht.transmissionbt.com:6881",
    "router.bitcomet.com:6881",
    "dht.libtorrent.org:25401",
];

// ------------------------------------------------------------------ datos

#[derive(Clone, Serialize, Deserialize)]
pub struct Hallado {
    pub info_hash: String,
    pub nombre: String,
    pub tamano: u64,
    pub archivos: usize,
    pub fecha_ms: i64,
}

#[derive(Clone, Default, Serialize, Deserialize)]
struct Estado {
    hallados: Vec<Hallado>,
}

fn ahora_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

// ----------------------------------------------------------------- filtro

/// Captura TODOS los info_hashes que pasan por nuestro nodo.
#[derive(Clone, Debug)]
struct FiltroAtrapador {
    tx: Arc<Sender<String>>,
    vistos: Arc<AtomicU64>,
}

impl FiltroAtrapador {
    fn captura(&self, hash: String) {
        self.vistos.fetch_add(1, Ordering::Relaxed);
        let _ = self.tx.send(hash);
    }
}

impl RequestFilter for FiltroAtrapador {
    fn allow_request(&self, request: &mainline::RequestSpecific, _from: SocketAddrV4) -> bool {
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

// -------------------------------------------------------------- el motor

pub struct DhtBusca {
    stop: Arc<AtomicBool>,
    hilo_spider: Option<JoinHandle<()>>,
    indice: Arc<Mutex<Estado>>,
    nuevos_desde_poll: Arc<Mutex<Vec<String>>>,
    stats: Arc<Mutex<Stats>>,
    vistos: Arc<AtomicU64>,
    canal: Mutex<Option<Arc<Sender<String>>>>,
    logs: EventLog,
    dir_cache: PathBuf,
    runtime: Arc<tokio::runtime::Runtime>,
    max_meta: usize,
}

#[derive(Clone, Default, serde::Serialize)]
pub struct Stats {
    pub nodos_tabla: usize,
    pub capturados: u64,
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
            canal: Mutex::new(None),
            logs: EventLog::new(),
            dir_cache: dir,
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
        let stop = self.stop.clone();
        let logs = self.logs.clone();

        // El DHT vive en su propio hilo (API sync de mainline).
        let builder_thread = std::thread::Builder::new().name("dhtbusca-spider".into());
        let handle = builder_thread.spawn(move || {
            let filtro: Box<dyn RequestFilter> =
                Box::new(FiltroAtrapador {
                tx: tx_filtro.clone(),
                vistos: vistos_hilo.clone(),
            });
            let dht = match Dht::builder()
                .server_mode()
                .server_settings(ServerSettings {
                    filter: filtro,
                    ..ServerSettings::default()
                })
                .bootstrap(BOOTSTRAP)
                .request_timeout(Duration::from_secs(10))
                .build()
            {
                Ok(d) => d,
                Err(e) => {
                    logs.push(format!("✗ DHT no arrancó: {e:?}"));
                    return;
                }
            };
            let _ = dht.bootstrapped();
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
                            let _ = dht.find_node(Id::random());
                        }
                        ultimo_find_node = Instant::now();
                    }
                    let id = Id::random();
                    vistos.insert(*id.as_bytes());
                    if vistos.len() > 50_000 {
                        vistos.clear();
                    }
                    // como el crawler: si el id aleatorio tiene swarm,
                    // también entra al canal (descubrimiento activo real)
                    if dht.get_peers(id).next().is_some() {
                        vistos_hilo.fetch_add(1, Ordering::Relaxed);
                        let _ = tx_filtro.send(hex_id(&id));
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

    pub fn total(&self) -> usize {
        self.indice.lock().unwrap_or_else(|e| e.into_inner()).hallados.len()
    }

    pub fn stats(&self) -> Stats {
        let mut st = self.stats.lock().unwrap_or_else(|e| e.into_inner()).clone();
        st.capturados = self.vistos.load(Ordering::Relaxed);
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
) {
    use librqbit::api::ApiTorrentListOpts;

    let _ = std::fs::create_dir_all(&dir_tmp);
    let session = match librqbit::Session::new(dir_tmp).await {
        Ok(s) => s,
        Err(e) => {
            logs.push(format!("✗ rqbit Session: {e:?}"));
            return;
        }
    };
    // Misma fachada que api/torrent/list.rs (API estable en rqbit 9).
    let api = librqbit::Api::new(session.clone(), None);

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
                    let s = session.clone();
                    tokio::spawn(async move {
                        let add = librqbit::AddTorrent::from_url(magnet);
                        let opts = librqbit::AddTorrentOptions::default();
                        let _ = s.add_torrent(add, Some(opts)).await;
                    });
                }
                Err(std::sync::mpsc::TryRecvError::Empty) => break,
                Err(std::sync::mpsc::TryRecvError::Disconnected) => return,
            }
        }

        // 2) evictar los atascados
        let ahora = Instant::now();
        pendientes.retain(|_, t| ahora.duration_since(*t) < PENDING_TIMEOUT);

        // 3) cosechar metadatos listos: la lista trae name solo cuando
        // ya resolvió metadatos; total_bytes viene en stats.
        let mut cosechados: Vec<Hallado> = Vec::new();
        let list = api.api_torrent_list_ext(ApiTorrentListOpts { with_stats: true });
        for t in list.torrents {
            if !pendientes.contains_key(&t.info_hash) {
                continue;
            }
            let nombre = t.name.clone().unwrap_or_default();
            if nombre.is_empty() {
                continue;
            }
            let tamano = t
                .stats
                .as_ref()
                .map(|st| st.total_bytes)
                .unwrap_or_default();
            cosechados.push(Hallado {
                info_hash: t.info_hash.clone(),
                nombre: nombre.chars().take(200).collect(),
                tamano,
                archivos: 0,
                fecha_ms: ahora_ms(),
            });
            pendientes.remove(&t.info_hash);
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
        // el conteo fino de la tabla vive dentro de rqbit; reportamos
        // pendientes/resueltos que es lo accionable en UI
        let nodos = 0usize;
        {
            let mut st = stats.lock().unwrap_or_else(|e| e.into_inner());
            st.nodos_tabla = nodos;
            st.resueltos = indice.lock().unwrap_or_else(|e| e.into_inner()).hallados.len();
            st.pendientes = pendientes.len();
            st.capturados = vistos_meta.load(Ordering::Relaxed);
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
