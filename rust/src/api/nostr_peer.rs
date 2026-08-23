/// Chat Nostr CON observador (clave compartida ECDH, patrón Mostro).
///
/// Wrapper FRB fino sobre `gt::nostrpeer::SharedKeyChat` (lógica portada
/// de `nostrpeer.rs` de Gtool sin Godot).
/// - Participantes: init_participant(mi_nsec, npub_otro) → ambos derivan
///   la misma shared key.
/// - Observador: init_observer(shared_key_hex) → lee todo, no puede enviar.
use anyhow::{anyhow, Result};

use crate::gt::nostrpeer::SharedKeyChat;

/// Mensaje recibido (serializable a Dart).
#[flutter_rust_bridge::frb]
pub struct PeerMessage {
    pub pubkey: String,
    pub content: String,
    pub created_at_ms: i64,
}

#[flutter_rust_bridge::frb(opaque)]
pub struct NostrPeerChat {
    inner: SharedKeyChat,
    n_seconds: i64,
}

impl NostrPeerChat {
    /// Ventana de frescura para el poll: mensajes más viejos se descartan.
    pub fn set_window(&mut self, n_seconds: i64) {
        self.n_seconds = n_seconds.max(1);
    }

    /// Participante: deriva la shared key y se suscribe.
    /// Retorna la shared key en hex → pasásela al observador por otro canal.
    /// since/until en epoch segundos; 0 = sin límite.
    pub fn init_participant(
        &self,
        sender_secret: String,
        receiver_pubkey: String,
        relays: Vec<String>,
        n_limit: i64,
        since: i64,
        until: i64,
    ) -> Result<String> {
        self.inner.init_participant(
            sender_secret,
            receiver_pubkey,
            relays,
            n_limit.max(1) as usize,
            since.max(0) as u64,
            until.max(0) as u64,
        )
            .map_err(|e| anyhow!("init_participant: {e:#}"))
    }

    /// Observador: solo necesita la shared key (hex) + relays.
    pub fn init_observer(
        &self,
        shared_key_hex: String,
        relays: Vec<String>,
        n_limit: i64,
        since: i64,
        until: i64,
    ) -> Result<()> {
        self.inner
            .init_observer(
                shared_key_hex,
                relays,
                n_limit.max(1) as usize,
                since.max(0) as u64,
                until.max(0) as u64,
            )
            .map_err(|e| anyhow!("init_observer: {e:#}"))
    }

    /// Enviar mensaje. El observador recibe error (no tiene sender keys).
    pub fn send(&self, message: String) -> Result<()> {
        self.inner
            .send_message(&message)
            .map_err(|e| anyhow!("Error enviando: {e:#}"))
    }

    /// Poll no bloqueante de mensajes nuevos desencriptados.
    pub fn poll(&self) -> Result<Vec<PeerMessage>> {
        let msgs = self
            .inner
            .poll_messages(self.n_seconds as u64)
            .map_err(|e| anyhow!("Error en poll: {e:#}"))?;
        Ok(msgs
            .into_iter()
            .map(|m| PeerMessage {
                pubkey: m.pubkey,
                content: m.content,
                created_at_ms: m.created_at as i64 * 1000,
            })
            .collect())
    }

    pub fn disconnect(&self) {
        self.inner.disconnect();
    }

    /// Drena el registro de eventos (init/relays/subscribe/send/poll).
    pub fn take_logs(&self) -> Vec<String> {
        self.inner.take_logs()
    }
}

/// Constructor libre (el codegen expone las clases opacas como abstractas).
#[flutter_rust_bridge::frb]
pub fn nostr_peer_new() -> Result<NostrPeerChat> {
    Ok(NostrPeerChat {
        inner: SharedKeyChat::new()
            .map_err(|e| anyhow!("Error creando chat: {e:#}"))?,
        n_seconds: 600,
    })
}
