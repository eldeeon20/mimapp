/// Chat Nostr NIP-17 (DM privado 1-a-1, SIN observador).
///
/// Wrapper FRB fino sobre el módulo puro `gt::nostrn::NostrClient`
/// (copiado tal cual de Gtool). Misma mecánica que el demo
/// `nostr_demo1.gd`: init → add_relays → subscribe → send/poll.
use anyhow::{anyhow, Result};
use nostr_sdk::ToBech32;

use crate::gt::nostrn::NostrClient;

/// Mensaje recibido del peer (serializable a Dart).
#[flutter_rust_bridge::frb]
pub struct DmMessage {
    pub sender: String,
    pub content: String,
    pub timestamp_ms: i64,
}

#[flutter_rust_bridge::frb(opaque)]
pub struct NostrDm {
    client: NostrClient,
}

impl NostrDm {
    /// Relays de DM y de lectura. Requiere al menos un DM relay.
    pub fn add_relays(&mut self, dm_relays: Vec<String>, read_relays: Vec<String>) -> Result<()> {
        let read = if read_relays.is_empty() { None } else { Some(read_relays) };
        self.client
            .add_relays(dm_relays, read)
            .map_err(|e| anyhow!("Error agregando relays: {e:#}"))
    }

    /// Ventana de búsqueda y límite, luego se suscribe.
    /// Ambos SIEMPRE activos; los setea Dart (campos Desde / Límite).
    pub fn subscribe(&mut self, n_seconds: i64, n_limit: i64) -> Result<()> {
        self.client.n_seconds = n_seconds.max(1) as u64;
        self.client.n_limit = n_limit.max(1) as usize;
        self.client
            .subscribe()
            .map_err(|e| anyhow!("Error suscribiendo: {e:#}"))
    }

    /// Envía un mensaje privado al peer.
    pub fn send(&self, content: String) -> Result<()> {
        self.client
            .send_message(&content)
            .map_err(|e| anyhow!("Error enviando: {e:#}"))
    }

    /// Poll de mensajes nuevos (bloquea hasta poll_timeout segundos).
    pub fn poll(&mut self, poll_timeout_secs: i64) -> Result<Vec<DmMessage>> {
        self.client.poll_timeout = poll_timeout_secs.max(1) as u64;
        let msgs = self
            .client
            .poll_messages()
            .map_err(|e| anyhow!("Error en poll: {e:#}"))?;
        Ok(msgs
            .into_iter()
            .map(|m| DmMessage {
                sender: m.sender.to_bech32().unwrap_or_else(|_| m.sender.to_string()),
                content: m.content,
                timestamp_ms: m.timestamp.as_u64() as i64 * 1000,
            })
            .collect())
    }

    /// Mi npub (bech32).
    pub fn public_key(&self) -> Result<String> {
        self.client
            .get_public_key()
            .map_err(|e| anyhow!("{e:#}"))
    }

    /// Cierra conexiones con los relays.
    pub fn disconnect(&mut self) -> Result<()> {
        self.client.disconnect().map_err(|e| anyhow!("{e:#}"))
    }

    /// Drena el registro de eventos (init/relays/subscribe/send/poll).
    pub fn take_logs(&mut self) -> Vec<String> {
        self.client.take_logs()
    }
}

/// Constructor libre (el codegen expone las clases opacas como abstractas).
/// nsec vacío/None = genera identidad nueva.
#[flutter_rust_bridge::frb]
pub fn nostr_dm_new(nsec: Option<String>, peer_npub: String) -> Result<NostrDm> {
    let client = NostrClient::new(nsec.as_deref(), &peer_npub)
        .map_err(|e| anyhow!("Error inicializando cliente Nostr: {e:#}"))?;
    Ok(NostrDm { client })
}
