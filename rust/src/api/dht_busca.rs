//! DHT Busca: wrapper FRB fino sobre `gt::dhtbusca`. Motor opaco con
//! ciclo start/poll/buscar/stop y patrón ok/error del proyecto.

use crate::gt::dhtbusca::{DhtBusca, Hallado as HalladoInt, Stats as StatsInt};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Mutex};

/// Torrent hallado por el spider, serializable a Dart.
#[flutter_rust_bridge::frb]
#[derive(Clone)]
pub struct HalladoItem {
    pub info_hash: String,
    pub nombre: String,
    pub tamano: u64,
    pub archivos: usize,
    pub fecha_ms: i64,
    pub creation_date: String,
    pub comment: String,
}

/// Captura en vivo del spider: un info_hash interceptado, con estado de
/// resolución. La UI lo muestra en la lista de "hashes" (aparte de los
/// metadatos ya resueltos).
#[flutter_rust_bridge::frb]
#[derive(Clone)]
pub struct CapturaItem {
    pub info_hash: String,
    pub nombre: String,
    pub resuelto: bool,
}

#[flutter_rust_bridge::frb]
#[derive(Clone)]
pub struct DhtStats {
    pub nodos_tabla: usize,
    pub semillas_ok: u64,
    pub semillas_total: u64,
    pub capturados: u64,
    pub pedidos: u64,
    pub resueltos: usize,
    pub pendientes: usize,
    pub total_indice: usize,
}

fn mapear(h: HalladoInt) -> HalladoItem {
    HalladoItem {
        info_hash: h.info_hash,
        nombre: h.nombre,
        tamano: h.tamano,
        archivos: h.archivos,
        fecha_ms: h.fecha_ms,
        creation_date: h.creation_date,
        comment: h.comment,
    }
}

/// Motor vivo del spider. FRB lo ve como opaco; los métodos van async.
pub struct MotorDht {
    inner: Arc<Mutex<Option<DhtBusca>>>,
}

/// Crea el motor y carga la caché previa si existe. No conecta.
/// Patrón gestionNew: constructor top-level para FRB.
#[flutter_rust_bridge::frb]
pub fn motor_dht_new(dir_cache: String, max_meta: i32) -> anyhow::Result<MotorDht> {
    Ok(MotorDht {
        inner: Arc::new(Mutex::new(Some(DhtBusca::new(
            &dir_cache,
            max_meta.max(0) as usize,
        )?))),
    })
}

impl MotorDht {

    /// Arranca el nodo servidor + captura. pasivo/activo combinables.
    pub async fn start(&self, pasivo: bool, activo: bool) -> Result<(), String> {
        self.con_mut(|m| {
            m.start(pasivo, activo)
                .map_err(|e| format!("dht start: {e:#}"))
        })?
    }

    /// Para el spider y guarda índice.
    pub async fn stop(&self) -> Result<(), String> {
        self.con_mut(|m| m.stop().map_err(|e| format!("dht stop: {e:#}")))?
    }

    /// Nuevos hallazgos desde el poll anterior.
    pub async fn poll_nuevos(&self) -> Result<Vec<HalladoItem>, String> {
        self.con(|m| Ok(m.poll_nuevos().into_iter().map(mapear).collect()))?
    }

    /// Búsqueda de texto por nombre sobre el índice local.
    pub async fn buscar(&self, texto: String) -> Result<Vec<HalladoItem>, String> {
        self.con(|m| Ok(m.buscar(&texto).into_iter().map(mapear).collect()))?
    }

    /// Base de capturas en vivo: cada hash interceptado por el spider, con
    /// estado de resolución (resuelto = ya tiene metadato).
    pub async fn capturas(&self, limit: i32) -> Result<Vec<CapturaItem>, String> {
        self.con(|m| {
            Ok(m.capturas(limit)
                .into_iter()
                .map(|c| CapturaItem {
                    info_hash: c.hash,
                    nombre: c.nombre,
                    resuelto: c.resuelto,
                })
                .collect())
        })?
    }

    /// Filtra la base de capturas por hash o nombre (substring, parcial).
    pub async fn capturas_filtradas(
        &self,
        texto: String,
        limit: i32,
    ) -> Result<Vec<CapturaItem>, String> {
        self.con(|m| {
            Ok(m.capturas_filtradas(&texto, limit)
                .into_iter()
                .map(|c| CapturaItem {
                    info_hash: c.hash,
                    nombre: c.nombre,
                    resuelto: c.resuelto,
                })
                .collect())
        })?
    }

    pub async fn stats(&self) -> Result<DhtStats, String> {
        self.con(|m| {
            let s: StatsInt = m.stats();
            Ok(DhtStats {
                nodos_tabla: s.nodos_tabla,
                semillas_ok: s.semillas_ok,
                semillas_total: s.semillas_total,
                capturados: s.capturados,
                pedidos: s.pedidos,
                resueltos: s.resueltos,
                pendientes: s.pendientes,
                total_indice: m.total(),
            })
        })?
    }

    /// Prueba manual: magnet completo o info_hash hex de 40.
    pub async fn probar(&self, texto: String) -> Result<(), String> {
        self.con(|m| m.probar(&texto).map_err(|e| format!("probar: {e:#}")))?
    }

    /// Índice completo de metadatos resueltos (incluidos los recargados del
    /// JSON al abrir). Puebla la lista RESUELTOS al iniciar.
    pub async fn resueltos(&self, limit: i32) -> Result<Vec<HalladoItem>, String> {
        self.con(|m| Ok(m.resueltos(limit).into_iter().map(mapear).collect()))?
    }

    /// Activa/desactiva el sondeo de hashes aleatorios (get_peers sobre ids
    /// random). El find_node de mantenimiento de tabla Kademlia sigue activo.
    pub async fn set_sondeo_aleatorio(&self, on: bool) -> Result<(), String> {
        self.con_mut(|m| {
            m.sondear_aleatorio.store(on, Ordering::SeqCst);
            Ok(())
        })?
    }

    /// Estado actual del sondeo de hashes aleatorios.
    pub async fn sondeo_aleatorio(&self) -> Result<bool, String> {
        self.con(|m| Ok(m.sondear_aleatorio.load(Ordering::SeqCst)))?
    }

    /// Guarda índice sin parar el spider.
    pub async fn guardar(&self) -> Result<(), String> {
        self.con(|m| {
            m.guardar_ahora()
                .map_err(|e| format!("guardar índice: {e:#}"))
        })?
    }

    pub async fn take_logs(&self) -> Vec<String> {
        self.con(|m| m.take_logs()).unwrap_or_default()
    }

    /// Magnet enriquecido (dn= nombre, xl= tamaño) para pegarlo en
    /// Torrents o donde sea.
    #[flutter_rust_bridge::frb(sync)]
    pub fn magnet(&self, hash: String, nombre: String, tamano: u64) -> String {
        let mut m = format!("magnet:?xt=urn:btih:{hash}");
        if !nombre.is_empty() {
            m.push_str(&format!(
                "&dn={}",
                urlencoding_simple(&nombre)
            ));
        }
        if tamano > 0 {
            m.push_str(&format!("&xl={tamano}"));
        }
        m
    }

    /// Ejecuta [f] con el motor vivo; error legible si está caído.
    fn con<T>(&self, f: impl FnOnce(&DhtBusca) -> T) -> Result<T, String> {
        let g = self.inner.lock().map_err(|_| "mutex envenenado")?;
        let m = g.as_ref().ok_or_else(|| "motor caído".to_string())?;
        Ok(f(m))
    }

    /// Variante mutable para operaciones de ciclo de vida.
    fn con_mut<T>(&self, f: impl FnOnce(&mut DhtBusca) -> T) -> Result<T, String> {
        let mut g = self.inner.lock().map_err(|_| "mutex envenenado")?;
        let m = g.as_mut().ok_or_else(|| "motor caído".to_string())?;
        Ok(f(m))
    }
}

/// Escape mínimo para dn= (espacios y &) sin dependencia extra.
fn urlencoding_simple(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            ' ' => out.push('.'),
            '&' | '%' | '+' | '#' | '?' => out.push_str(&format!("%{:02X}", c as u32)),
            _ => out.push(c),
        }
    }
    out
}
