//! Iroh P2P: cliente y servidor de blobs sobre QUIC (n0-computer).
//!
//! Flujo probado según los ejemplos oficiales (transfer.rs / docs):
//!   SERVIDOR:  Endpoint::bind(N0) → MemStore → BlobsProtocol →
//!              Router::accept(ALPN) → add_path(archivo) → BlobTicket
//!   CLIENTE:   ticket.parse() → store.downloader(&ep).download(hash) →
//!              store.blobs().export(hash, destino)
//!
//! El mismo nodo sirve Y descarga: un solo Endpoint hace ambos roles.
//! Almacén en memoria (v1): archivos ofrecidos quedan en RAM.

use anyhow::{anyhow, Context, Result};
use iroh::endpoint::presets;
use iroh::protocol::Router;
use iroh::Endpoint;
use iroh_blobs::ticket::BlobTicket;
use iroh_blobs::{BlobsProtocol, MemStore};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use crate::gt::eventlog::EventLog;

struct Vivo {
    endpoint: Endpoint,
    router: Router,
    _store: Arc<MemStore>,
}

/// Nodo iroh completo: servidor de blobs + cliente de descarga.
pub struct IrohPar {
    runtime: Arc<tokio::runtime::Runtime>,
    vivo: Arc<Mutex<Option<Vivo>>>,
    logs: EventLog,
}

impl IrohPar {
    pub fn new() -> Result<Self> {
        Ok(Self {
            runtime: Arc::new(
                tokio::runtime::Builder::new_multi_thread()
                    .worker_threads(2)
                    .enable_all()
                    .build()
                    .context("runtime tokio")?,
            ),
            vivo: Arc::new(Mutex::new(None)),
            logs: EventLog::new(),
        })
    }

    /// Arranca el nodo (servidor de blobs listo para ofrecer).
    /// Devuelve el id del endpoint (hex 64) para compartir.
    pub fn start_servidor(&self) -> Result<String> {
        let mut g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
        if g.is_some() {
            return Err(anyhow!("el nodo ya está corriendo"));
        }
        self.logs.push("conectando a la red iroh…".into());
        let endpoint = self.runtime.block_on(async {
            let ep = Endpoint::bind(presets::N0)
                .await
                .context("bind endpoint")?;
            ep.online()
                .await
                .context("esperando relay/online")?;
            Ok::<_, anyhow::Error>(ep)
        })?;
        let id = endpoint.id().to_string();

        let store = Arc::new(
            MemStore::new().context("creando almacén de blobs")?,
        );
        let blobs = BlobsProtocol::new(&store, None);
        let router = Router::builder(endpoint.clone())
            .accept(iroh_blobs::ALPN, blobs)
            .spawn();
        *g = Some(Vivo { endpoint, router, _store: store });
        self.logs
            .push(format!("✓ nodo iroh arriba · id {id}"));
        Ok(id)
    }

    /// Ofrece un archivo: lo agrega al almacén y devuelve el ticket
    /// copiable. Quien tenga el ticket puede bajarlo de este nodo.
    pub fn ofrecer(&self, ruta: &str) -> Result<String> {
        let g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
        let vivo = g.as_ref().ok_or_else(|| anyhow!("nodo apagado"))?;
        let abs = PathBuf::from(ruta);
        let abs = if abs.is_absolute() {
            abs
        } else {
            std::fs::canonicalize(&abs).context("resolviendo ruta")?
        };
        if !abs.is_file() {
            return Err(anyhow!("no es un archivo: {}", abs.display()));
        }
        let nombre = abs
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let ticket = self.runtime.block_on(async {
            let tag = vivo
                ._store
                .blobs()
                .add_path(abs.clone())
                .await
                .context("hasheando archivo")?;
            let t = BlobTicket::new(vivo.endpoint.addr(), tag.hash, tag.format);
            Ok::<_, anyhow::Error>(t.to_string())
        })?;
        self.logs
            .push(format!("✓ ofreciendo '{nombre}' · ticket generado"));
        Ok(ticket)
    }

    /// Baja un blob desde el ticket a [dir_destino]/[nombre].
    /// Devuelve la ruta final escrita.
    pub fn bajar(&self, ticket_str: &str, dir_destino: &str, nombre: &str) -> Result<String> {
        let g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
        let vivo = g.as_ref().ok_or_else(|| anyhow!("nodo apagado"))?;
        if nombre.trim().is_empty() {
            return Err(anyhow!("poné un nombre de destino"));
        }
        let destino = Path::new(dir_destino).join(nombre.trim());
        let ticket: BlobTicket = ticket_str
            .trim()
            .parse()
            .map_err(|e| anyhow!("ticket inválido: {e:?}"))?;
        self.logs.push(format!(
            "bajando {} bytes-desde {:?}…",
            ticket.hash(),
            ticket.addr().id
        ));
        self.runtime.block_on(async {
            let downloader = vivo._store.downloader(&vivo.endpoint);
            downloader
                .download(ticket.hash(), Some(ticket.addr().id))
                .await
                .context("descarga del blob")?;
            std::fs::create_dir_all(dir_destino).context("creando destino")?;
            vivo._store
                .blobs()
                .export(ticket.hash(), &destino)
                .await
                .context("exportando archivo")?;
            Ok::<_, anyhow::Error>(())
        })?;
        let out = destino.to_string_lossy().into_owned();
        self.logs.push(format!("✓ guardado en {out}"));
        Ok(out)
    }

    /// Id del endpoint si está corriendo.
    pub fn node_id(&self) -> Option<String> {
        let g = self.vivo.lock().ok()?;
        g.as_ref().map(|v| v.endpoint.id().to_string())
    }

    pub fn esta_corriendo(&self) -> bool {
        self.vivo.lock().map(|g| g.is_some()).unwrap_or(false)
    }

    /// Apaga router + endpoint.
    pub fn stop(&self) -> Result<()> {
        let mut g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
        let vivo = g.take().ok_or_else(|| anyhow!("no está corriendo"))?;
        self.runtime.block_on(async {
            let _ = vivo.router.shutdown().await;
            vivo.endpoint.close().await;
        });
        self.logs.push("■ nodo iroh apagado".into());
        Ok(())
    }

    pub fn take_logs(&self) -> Vec<String> {
        self.logs.drain()
    }
}

impl Drop for IrohPar {
    fn drop(&mut self) {
        if self.esta_corriendo() {
            let _ = self.stop();
        }
    }
}
