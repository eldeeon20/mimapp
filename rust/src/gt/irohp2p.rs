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
use iroh::protocol::{ProtocolHandler, Router};
use iroh::Endpoint;
use iroh_tickets::endpoint::EndpointTicket;
use iroh_blobs::ticket::BlobTicket;
use iroh_blobs::store::mem::MemStore;
use iroh_blobs::BlobsProtocol;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::sync::mpsc as tmpsc;

use crate::gt::eventlog::EventLog;

struct Vivo {
    endpoint: Endpoint,
    router: Router,
    _store: Arc<MemStore>,
}

/// ALPN del chat de prueba: eco bidireccional simple.
pub const ALPN_CHAT: &[u8] = b"mimapp/chat/1";

/// Mensaje de chat entrante listo para la UI.
#[derive(Clone, Debug)]
pub struct LineaChat {
    pub de: String,
    pub texto: String,
}

/// Handler del lado que RECIBE la conexión: canal vivo de líneas.
/// Ambos lados quedan iguales tras el handshake: cualquiera manda.
#[derive(Debug)]
struct ChatNodo {
    entrantes: Arc<Mutex<Vec<LineaChat>>>,
    salidas: Arc<Mutex<Vec<tmpsc::UnboundedSender<String>>>>,
}

impl ChatNodo {
    fn cablear(
        &self,
        mut w: iroh::endpoint::SendStream,
        mut r: iroh::endpoint::RecvStream,
    ) {
        let (otx, mut orx) = tmpsc::unbounded_channel::<String>();
        self.salidas
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(otx);
        let salidas = self.salidas.clone();
        let mut escritor = tokio::spawn(async move {
            while let Some(txt) = orx.recv().await {
                if w.write_all(format!("{txt}\n").as_bytes())
                    .await
                    .is_err()
                {
                    break;
                }
            }
            let _ = w.finish();
        });
        let entrantes = self.entrantes.clone();
        let mut lector = tokio::spawn(async move {
            let mut buf = vec![0u8; 4096];
            loop {
                match r.read(&mut buf).await {
                    Err(_) | Ok(None) | Ok(Some(0)) => break,
                    Ok(Some(n)) => {
                        let trozo = String::from_utf8_lossy(&buf[..n]);
                        for linea in trozo.split('\n').filter(|l| !l.is_empty()) {
                            entrantes
                                .lock()
                                .unwrap_or_else(|e| e.into_inner())
                                .push(LineaChat {
                                    de: "par".into(),
                                    texto: linea.to_string(),
                                });
                        }
                    }
                }
            }
        });
        // al cerrar el par limpiamos nuestra salida
        let salidas2 = self.salidas.clone();
        tokio::spawn(async move {
            let _ = &mut escritor;
            let _ = &mut lector;
            tokio::time::sleep(std::time::Duration::from_secs(3600 * 6)).await;
            salidas2.lock().unwrap_or_else(|e| e.into_inner()).clear();
        });
    }
}

impl ProtocolHandler for ChatNodo {
    async fn accept(
        &self,
        connection: iroh::endpoint::Connection,
    ) -> Result<(), iroh::protocol::AcceptError> {
        // best effort: si el par corta antes del stream, igual cerramos bien
        if let Ok((w, r)) = connection.accept_bi().await {
            self.cablear(w, r);
            let _ = connection.closed().await;
        } else {
            let _ = connection.closed().await;
        }
        Ok(())
    }
}

/// Limpia un ticket pegado/escrito a mano: fuera TODOS los espacios y
/// saltos (el teclado y WhatsApp los meten siempre). Devuelve el string
/// listo para parsear.
fn limpiar_ticket(s: &str) -> String {
    s.chars().filter(|c| !c.is_whitespace()).collect()
}

/// Error legible cuando el ticket no parsea: dice qué llegó.
fn error_ticket(llego: &str, e: impl std::fmt::Debug) -> anyhow::Error {
    let n = llego.chars().count();
    let head: String = llego.chars().take(12).collect();
    anyhow!(
        "ticket inválido ({e:?}) · llegaron {n} chars empezando '{head}…'"
    )
}

/// Nodo iroh completo: servidor de blobs + cliente de descarga.
pub struct IrohPar {
    runtime: Arc<tokio::runtime::Runtime>,
    vivo: Arc<Mutex<Option<Vivo>>>,
    chat_salidas: Arc<Mutex<Vec<tmpsc::UnboundedSender<String>>>>,
    chat_entrantes: Arc<Mutex<Vec<LineaChat>>>,
    chat_conn: Mutex<Option<iroh::endpoint::Connection>>,
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
            chat_salidas: Arc::new(Mutex::new(Vec::new())),
            chat_entrantes: Arc::new(Mutex::new(Vec::new())),
            chat_conn: Mutex::new(None),
            logs: EventLog::new(),
        })
    }

    /// Ejecuta [fut] en NUESTRO runtime y espera el resultado por canal.
    /// NUNCA usamos block_on: si el hilo llamador ya es un worker tokio
    /// (FRB), block_on entra en pánico con "Cannot start a runtime from
    /// within a runtime". El canal evita eso por completo.
    fn bloquea<T: Send + 'static>(
        &self,
        fut: impl std::future::Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T> {
        let (tx, rx) = std::sync::mpsc::channel();
        self.runtime.spawn(async move {
            let _ = tx.send(fut.await);
        });
        rx.recv().map_err(|_| anyhow!("runtime interno caído"))?
    }

    /// Arranca el nodo (servidor de blobs listo para ofrecer).
    /// Devuelve el id del endpoint (hex 64) para compartir.
    pub fn start_servidor(&self) -> Result<String> {
        let mut g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
        if g.is_some() {
            return Err(anyhow!("el nodo ya está corriendo"));
        }
        self.logs.push("conectando a la red iroh…");
        let endpoint = self.bloquea(async {
            let ep = Endpoint::bind(presets::N0)
                .await
                .context("bind endpoint")?;
            ep.online().await;
            Ok::<_, anyhow::Error>(ep)
        })?;
        let id = endpoint.id().to_string();

        let store = Arc::new(MemStore::new());
        let blobs = BlobsProtocol::new(&store, None);
        let router = Router::builder(endpoint.clone())
            .accept(iroh_blobs::ALPN, blobs)
            .accept(
                ALPN_CHAT,
                ChatNodo {
                    entrantes: self.chat_entrantes.clone(),
                    salidas: self.chat_salidas.clone(),
                },
            )
            .spawn();
        *g = Some(Vivo { endpoint, router, _store: store });
        self.logs
            .push(format!("✓ nodo iroh arriba · id {id}"));
        Ok(id)
    }

    /// Ofrece un archivo: lo agrega al almacén y devuelve el ticket
    /// copiable. Quien tenga el ticket puede bajarlo de este nodo.
    pub fn ofrecer(&self, ruta: &str) -> Result<String> {
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
        let (store, endpoint) = {
            let g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
            let v = g.as_ref().ok_or_else(|| anyhow!("nodo apagado"))?;
            (v._store.clone(), v.endpoint.clone())
        };
        let ticket = self.bloquea(async move {
            let tag = store
                .blobs()
                .add_path(abs.clone())
                .await
                .context("hasheando archivo")?;
            let t = BlobTicket::new(endpoint.addr(), tag.hash, tag.format);
            Ok::<_, anyhow::Error>(t.to_string())
        })?;
        self.logs
            .push(format!("✓ ofreciendo '{nombre}' · ticket generado"));
        Ok(ticket)
    }

    /// Baja un blob desde el ticket a [dir_destino]/[nombre].
    /// Devuelve la ruta final escrita.
    pub fn bajar(&self, ticket_str: &str, dir_destino: &str, nombre: &str) -> Result<String> {
        if nombre.trim().is_empty() {
            return Err(anyhow!("poné un nombre de destino"));
        }
        let (store, endpoint) = {
            let g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
            let v = g.as_ref().ok_or_else(|| anyhow!("nodo apagado"))?;
            (v._store.clone(), v.endpoint.clone())
        };
        let dir = std::path::PathBuf::from(dir_destino);
        let destino = dir.join(nombre.trim());
        let destino_en_hilo = destino.clone();
        let limpio = limpiar_ticket(ticket_str);
        let ticket: BlobTicket = limpio
            .parse()
            .map_err(|e| error_ticket(&limpio, e))?;
        self.logs.push(format!(
            "bajando {} desde {:?}…",
            ticket.hash(),
            ticket.addr().id
        ));
        self.bloquea(async move {
            let downloader = store.downloader(&endpoint);
            downloader
                .download(ticket.hash(), Some(ticket.addr().id))
                .await
                .context("descarga del blob")?;
            std::fs::create_dir_all(&dir).context("creando destino")?;
            store
                .blobs()
                .export(ticket.hash(), &destino_en_hilo)
                .await
                .context("exportando archivo")?;
            Ok::<_, anyhow::Error>(())
        })?;
        let out = destino.to_string_lossy().into_owned();
        self.logs.push(format!("✓ guardado en {out}"));
        Ok(out)
    }

    /// Ticket de CONEXIÓN (no de blob): con esto otro nodo abre un canal
    /// directo de chat contra este dispositivo.
    pub fn chat_ticket(&self) -> Result<String> {
        let g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
        let vivo = g.as_ref().ok_or_else(|| anyhow!("nodo apagado"))?;
        Ok(EndpointTicket::new(vivo.endpoint.addr()).to_string())
    }

    /// Conecta como CLIENTE al ticket del otro y queda en modo chat vivo.
    pub fn chat_conectar(&self, ticket_str: &str) -> Result<()> {
        let endpoint = {
            let g = self.vivo.lock().map_err(|_| anyhow!("mutex"))?;
            g.as_ref()
                .ok_or_else(|| anyhow!("nodo apagado"))?
                .endpoint
                .clone()
        };
        let dueño = limpiar_ticket(ticket_str);
        let nodo = ChatNodo {
            entrantes: self.chat_entrantes.clone(),
            salidas: self.chat_salidas.clone(),
        };
        let conn = self.bloquea(async move {
            let t: EndpointTicket = dueño
                .parse()
                .map_err(|e| error_ticket(&dueño, e))?;
            let c = endpoint
                .connect(t.endpoint_addr().clone(), ALPN_CHAT)
                .await
                .context("conectando al par")?;
            let (w, r) = c.open_bi().await.context("abriendo stream")?;
            nodo.cablear(w, r);
            Ok::<_, anyhow::Error>(c)
        })?;
        *self.chat_conn.lock().unwrap_or_else(|e| e.into_inner()) = Some(conn);
        self.logs.push("✓ chat conectado");
        Ok(())
    }

    /// Manda una línea por el canal vivo.
    pub fn chat_mandar(&self, texto: &str) -> Result<()> {
        if texto.trim().is_empty() {
            return Err(anyhow!("mensaje vacío"));
        }
        let salidas = self.chat_salidas.lock().unwrap_or_else(|e| e.into_inner());
        let primera = salidas
            .first()
            .ok_or_else(|| {
                anyhow!("sin canal: pegá el ticket del host y tocá CONECTAR")
            })?;
        primera
            .send(texto.to_string())
            .map_err(|_| anyhow!("el par se fue"))
    }

    /// Textos recibidos desde la última lectura (todos son del par;
    /// los propios los agrega la UI al enviarlos).
    pub fn chat_leer(&self) -> Vec<String> {
        std::mem::take(
            &mut *self.chat_entrantes.lock().unwrap_or_else(|e| e.into_inner()),
        )
        .into_iter()
        .map(|l| l.texto)
        .collect()
    }

    pub fn chat_activo(&self) -> bool {
        !self
            .chat_salidas
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_empty()
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
        drop(g); // soltar el lock antes de esperar el shutdown
        self.bloquea(async move {
            let _ = vivo.router.shutdown().await;
            vivo.endpoint.close().await;
            Ok::<_, anyhow::Error>(())
        })?;
        self.logs.push("■ nodo iroh apagado");
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
