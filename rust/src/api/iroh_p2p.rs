//! Iroh P2P: wrapper FRB fino sobre `gt::irohp2p`. Nodo opaco con
//! patrón ok/error del proyecto (mismo estilo que MotorDht).

use crate::gt::irohp2p::IrohPar;
use std::sync::{Arc, Mutex};

/// Nodo iroh vivo (sirve Y descarga blobs).
pub struct IrohViva {
    inner: Arc<Mutex<IrohPar>>,
}

/// Crea el nodo apagado. Patrón gestionNew: ctor top-level para FRB.
#[flutter_rust_bridge::frb]
pub fn iroh_nuevo() -> anyhow::Result<IrohViva> {
    Ok(IrohViva {
        inner: Arc::new(Mutex::new(IrohPar::new()?)),
    })
}

impl IrohViva {
    /// Arranca endpoint + router de blobs. Devuelve el id del endpoint.
    pub async fn start_servidor(&self) -> Result<String, String> {
        self.con(|p| p.start_servidor().map_err(|e| format!("iroh start: {e:#}")))?
    }

    /// Ofrece un archivo y devuelve su ticket copiable.
    pub async fn ofrecer(&self, ruta: String) -> Result<String, String> {
        self.con(|p| p.ofrecer(&ruta).map_err(|e| format!("ofrecer: {e:#}")))?
    }

    /// Baja el blob del ticket a [dir]/[nombre]; devuelve la ruta final.
    pub async fn bajar(
        &self,
        ticket: String,
        dir_destino: String,
        nombre: String,
    ) -> Result<String, String> {
        self.con(|p| {
            p.bajar(&ticket, &dir_destino, &nombre)
                .map_err(|e| format!("bajar: {e:#}"))
        })?
    }

    /// Id del endpoint si está arriba (null si no).
    #[flutter_rust_bridge::frb(sync)]
    pub fn node_id(&self) -> Option<String> {
        self.con(|p| p.node_id()).unwrap_or(None)
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn corriendo(&self) -> bool {
        self.con(|p| p.esta_corriendo()).unwrap_or(false)
    }

    /// Apaga router + endpoint.
    pub async fn stop(&self) -> Result<(), String> {
        self.con(|p| p.stop().map_err(|e| format!("iroh stop: {e:#}")))?
    }

    pub async fn take_logs(&self) -> Vec<String> {
        self.con(|p| p.take_logs()).unwrap_or_default()
    }

    fn con<T>(&self, f: impl FnOnce(&IrohPar) -> T) -> Result<T, String> {
        let g = self.inner.lock().map_err(|_| "mutex envenenado")?;
        Ok(f(&g))
    }
}
