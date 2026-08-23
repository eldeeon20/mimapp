//! Chat Nostr con clave compartida (patrón Mostro) — portado de Gtool
//! `nostrpeer.rs` sin dependencias de Godot.
//!
//! Dos participantes derivan la misma shared key por ECDH:
//!   shared = ECDH(sk_mía, pk_del_otro)
//! El observador solo necesita esa shared key (hex) para LEER todo,
//! pero no puede enviar (no tiene sender keys).
//!
//! Mensajes: inner text_note firmado → NIP-44 hacia la pública de la
//! shared key → GiftWrap con PoW y timestamp tweakado.

use anyhow::{anyhow, Result};
use nostr_sdk::prelude::*;
use std::str::FromStr;
use std::sync::{Arc, Mutex};
use tokio::runtime::Runtime;
use tokio::sync::broadcast;

const POW_DIFFICULTY: u8 = 2;

pub struct PeerMessage {
    pub pubkey: String,
    pub content: String,
    pub created_at: u64,
}

/// Núcleo puro del chat con observador (equivalente a NostrPeer de Godot).
pub struct SharedKeyChat {
    runtime: Arc<Runtime>,
    client: Arc<Mutex<Option<Client>>>,
    shared_keys: Arc<Mutex<Option<Keys>>>,
    sender_keys: Arc<Mutex<Option<Keys>>>,
    notifications: Arc<Mutex<Option<broadcast::Receiver<RelayPoolNotification>>>>,
}

impl SharedKeyChat {
    pub fn new() -> Result<Self> {
        Ok(Self {
            runtime: Arc::new(Runtime::new()?),
            client: Arc::new(Mutex::new(None)),
            shared_keys: Arc::new(Mutex::new(None)),
            sender_keys: Arc::new(Mutex::new(None)),
            notifications: Arc::new(Mutex::new(None)),
        })
    }

    /// Participante: deriva la shared key por ECDH y se suscribe.
    /// Retorna la shared key en hex (para dársela al observador).
    pub fn init_participant(
        &self,
        sender_secret: String,
        receiver_pubkey: String,
        relay_urls: Vec<String>,
        n_limit: usize,
        since: u64,
        until: u64,
    ) -> Result<String> {
        let sk = Keys::parse(&sender_secret)
            .map_err(|e| anyhow!("Invalid sender secret: {}", e))?;
        let receiver = PublicKey::from_str(&receiver_pubkey)
            .map_err(|e| anyhow!("Invalid receiver pubkey: {}", e))?;

        let shared_key_bytes =
            nostr_sdk::util::generate_shared_key(sk.secret_key(), &receiver)
                .map_err(|e| anyhow!("Error generating shared key: {}", e))?;
        let shared_secret_key = SecretKey::from_slice(&shared_key_bytes)
            .map_err(|e| anyhow!("Invalid shared key bytes: {}", e))?;
        let shared_keys = Keys::new(shared_secret_key);

        let client = Client::new(Keys::generate());
        for url in &relay_urls {
            self.runtime.block_on(async {
                client.add_relay(url).await.map_err(|e| {
                    anyhow!("Failed to add relay {}: {}", url, e)
                })?;
                Ok::<(), anyhow::Error>(())
            })?;
        }
        self.runtime.block_on(client.connect());

        let mut filter = Filter::new()
            .kind(Kind::GiftWrap)
            .limit(n_limit)
            .pubkey(shared_keys.public_key());
        if since > 0 {
            filter = filter.since(Timestamp::from(since));
        }
        if until > 0 {
            filter = filter.until(Timestamp::from(until));
        }
        self.runtime.block_on(async {
            client.subscribe(filter, None).await.map_err(|e| {
                anyhow!("Failed to subscribe: {}", e)
            })?;
            *self.client.lock().unwrap() = Some(client.clone());
            *self.shared_keys.lock().unwrap() = Some(shared_keys);
            *self.sender_keys.lock().unwrap() = Some(sk);
            *self.notifications.lock().unwrap() = Some(client.notifications());
            Ok::<(), anyhow::Error>(())
        })?;

        Ok(self.shared_keys.lock().unwrap().as_ref().unwrap()
            .secret_key().to_secret_hex())
    }

    /// Observador: solo necesita la shared key (hex) para leer.
    pub fn init_observer(
        &self,
        shared_key_hex: String,
        relay_urls: Vec<String>,
        n_limit: usize,
        since: u64,
        until: u64,
    ) -> Result<()> {
        let shared_secret_key = SecretKey::from_str(&shared_key_hex)
            .map_err(|e| anyhow!("Invalid shared key: {}", e))?;
        let shared_keys = Keys::new(shared_secret_key);

        let client = Client::new(Keys::generate());
        for url in &relay_urls {
            self.runtime.block_on(async {
                client.add_relay(url).await.map_err(|e| {
                    anyhow!("Failed to add relay {}: {}", url, e)
                })?;
                Ok::<(), anyhow::Error>(())
            })?;
        }
        self.runtime.block_on(client.connect());

        let mut filter = Filter::new()
            .kind(Kind::GiftWrap)
            .limit(n_limit)
            .pubkey(shared_keys.public_key());
        if since > 0 {
            filter = filter.since(Timestamp::from(since));
        }
        if until > 0 {
            filter = filter.until(Timestamp::from(until));
        }
        self.runtime.block_on(async {
            client.subscribe(filter, None).await.map_err(|e| {
                anyhow!("Failed to subscribe: {}", e)
            })?;
            *self.client.lock().unwrap() = Some(client.clone());
            *self.shared_keys.lock().unwrap() = Some(shared_keys);
            *self.sender_keys.lock().unwrap() = None; // observador NO escribe
            *self.notifications.lock().unwrap() = Some(client.notifications());
            Ok::<(), anyhow::Error>(())
        })?;
        Ok(())
    }

    /// Enviar mensaje (solo participantes; el observador no tiene sender keys).
    pub fn send_message(&self, message: &str) -> Result<()> {
        let client_guard = self.client.lock().unwrap();
        let sender_guard = self.sender_keys.lock().unwrap();
        let shared_guard = self.shared_keys.lock().unwrap();

        let (client, sender, shared) = match (
            client_guard.as_ref(),
            sender_guard.as_ref(),
            shared_guard.as_ref(),
        ) {
            (Some(c), Some(s), Some(sh)) => (c.clone(), s.clone(), sh.clone()),
            _ => return Err(anyhow!("Client, Sender or Shared keys not initialized")),
        };

        self.runtime.block_on(async move {
            let wrapped_event =
                mostro_wrap(&sender, shared.public_key(), message, vec![]).await
                    .map_err(|e| anyhow!("Error wrapping message: {}", e))?;
            client.send_event(&wrapped_event).await.map_err(|e| {
                anyhow!("Error sending event: {}", e)
            })?;
            Ok::<(), anyhow::Error>(())
        })
    }

    /// Poll no bloqueante de mensajes nuevos (los descarta si son viejos).
    pub fn poll_messages(&self, n_seconds: u64) -> Result<Vec<PeerMessage>> {
        let mut notifications_guard = self.notifications.lock().unwrap();
        let shared_guard = self.shared_keys.lock().unwrap();

        let mut messages = Vec::new();
        let shared_keys = match shared_guard.as_ref() {
            Some(k) => k.clone(),
            None => return Ok(messages),
        };
        let notifications = match notifications_guard.as_mut() {
            Some(n) => n,
            None => return Ok(messages),
        };

        loop {
            match notifications.try_recv() {
                Ok(notification) => {
                    if let RelayPoolNotification::Event { event, .. } = notification {
                        let res = self.runtime.block_on(async {
                            match mostro_unwrap(&shared_keys, *event).await {
                                Ok(inner_event) => {
                                    let now = Timestamp::now().as_u64();
                                    let msg_time = inner_event.created_at.as_u64();
                                    if now.saturating_sub(msg_time) > n_seconds {
                                        None
                                    } else {
                                        Some(inner_event)
                                    }
                                }
                                Err(_) => None,
                            }
                        });
                        if let Some(inner_event) = res {
                            messages.push(PeerMessage {
                                pubkey: inner_event.pubkey.to_string(),
                                content: inner_event.content,
                                created_at: inner_event.created_at.as_u64(),
                            });
                        }
                    }
                }
                Err(broadcast::error::TryRecvError::Empty) => break,
                Err(broadcast::error::TryRecvError::Lagged(_)) => continue,
                Err(broadcast::error::TryRecvError::Closed) => break,
            }
        }
        Ok(messages)
    }

    pub fn disconnect(&self) {
        if let Some(client) = self.client.lock().unwrap().as_ref() {
            self.runtime.block_on(client.disconnect());
        }
    }
}

async fn mostro_wrap(
    sender: &Keys,
    receiver: PublicKey,
    message: &str,
    extra_tags: Vec<Tag>,
) -> Result<Event, Box<dyn std::error::Error>> {
    let inner_event = EventBuilder::text_note(message)
        .build(sender.public_key())
        .sign(sender)
        .await?;

    let keys: Keys = Keys::generate();
    let encrypted_content: String = nip44::encrypt(
        keys.secret_key(),
        &receiver,
        inner_event.as_json(),
        nip44::Version::V2,
    )?;

    let mut tags = vec![Tag::public_key(receiver)];
    tags.extend(extra_tags);

    let wrapped_event = EventBuilder::new(Kind::GiftWrap, encrypted_content)
        .pow(POW_DIFFICULTY)
        .tags(tags)
        .custom_created_at(Timestamp::tweaked(nip59::RANGE_RANDOM_TIMESTAMP_TWEAK))
        .sign_with_keys(&keys)?;
    Ok(wrapped_event)
}

async fn mostro_unwrap(
    receiver: &Keys,
    event: Event,
) -> Result<Event, Box<dyn std::error::Error>> {
    let decrypted_content =
        nip44::decrypt(receiver.secret_key(), &event.pubkey, &event.content)?;
    let inner_event = Event::from_json(&decrypted_content)?;
    inner_event.verify()?;
    Ok(inner_event)
}
