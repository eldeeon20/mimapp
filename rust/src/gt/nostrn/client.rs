use anyhow::{anyhow, Context, Result};
use nostr::prelude::*;
use nostr_sdk::prelude::*;
use std::sync::Arc;
use std::time::Duration;
use tokio::runtime::Runtime;
use tokio::sync::{broadcast, Mutex};

use super::relays::{compose_write_relays, connect_relays};
use crate::gt::eventlog::EventLog;

/// Estructura que almacena la configuración del cliente Nostr para reutilización.
/// No usa threads ni channels - todas las operaciones son síncronas desde la perspectiva del llamador.
pub struct NostrClient {
    client: Client,
    keys: Keys,
    peer_pk: PublicKey,
    runtime: Arc<Runtime>,
    /// Registro de eventos visible desde la UI (take_logs).
    pub logs: EventLog,
    subscription_id: Option<SubscriptionId>,
    notifications: Arc<Mutex<Option<broadcast::Receiver<RelayPoolNotification>>>>,
    pub n_seconds: u64,
    pub n_limit: usize,
    pub poll_timeout: u64,
}

impl NostrClient {
    /// Crea un nuevo cliente Nostr con las claves y el destinatario especificados.
    /// 
    /// # Argumentos
    /// * `nsec` - Clave secreta en formato nsec (opcional, se generará una si es None)
    /// * `recipient_npub` - Clave pública del destinatario en formato npub
    pub fn new(nsec: Option<&str>, recipient_npub: &str) -> Result<Self> {
        // Parsear o generar claves
        let keys = if let Some(s) = nsec {
            Keys::parse(&s).context("Failed to parse provided secret key")?
        } else {
            Keys::generate()
        };

        // Parsear destinatario
        let peer_pk = PublicKey::from_bech32(recipient_npub)
            .context("Failed to parse recipient npub")?;

        // Crear cliente
        let client = Client::builder()
            .signer(keys.clone())
            .build();

        // Crear runtime de Tokio
        let runtime = Arc::new(
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .context("Failed to create Tokio runtime")?
        );

        let logs = EventLog::new();
        logs.push(if nsec.is_some() {
            "cliente creado (nsec propio)"
        } else {
            "cliente creado (nsec GENERADA nueva)"
        });
        logs.push(format!(
            "yo: {} · peer: {}",
            keys.public_key().to_bech32().unwrap_or_default(),
            peer_pk.to_bech32().unwrap_or_default()
        ));

        Ok(Self {
            client,
            keys,
            peer_pk,
            runtime,
            logs,
            subscription_id: None,
            notifications: Arc::new(Mutex::new(None)),
            n_seconds: 3600,
            n_limit: 10,
            poll_timeout: 2,
        })
    }

    /// Agrega y conecta a los relays especificados.
    /// 
    /// # Argumentos
    /// * `dm_relays` - Lista de relays DM del destinatario
    /// * `read_relays` - Lista de relays de lectura (opcional, usa dm_relays si está vacío)
    pub fn add_relays(&mut self, dm_relays: Vec<String>, read_relays: Option<Vec<String>>) -> Result<()> {
        if dm_relays.is_empty() {
            self.logs.push("✗ sin relays DM: se requiere al menos uno");
            return Err(anyhow!(
                "Strict NIP-17 mode requires at least one DM relay"
            ));
        }
        for r in &dm_relays {
            self.logs.push(format!("DM relay: {r}"));
        }

        // Determinar relays de lectura
        let read = if let Some(r) = read_relays {
            if r.is_empty() {
                dm_relays.clone()
            } else {
                r
            }
        } else {
            dm_relays.clone()
        };

        // Componer relays de escritura (DM + fallbacks)
        let write = compose_write_relays(&dm_relays);

        // Conectar usando el runtime
        self.logs.push("connect(): conectando relays…");
        self.runtime.block_on(async {
            connect_relays(&self.client, &read, &write).await
        })?;
        self.logs.push(format!(
            "✓ relays conectados (lectura:{}, escritura:{})",
            read.len(),
            write.len()
        ));

        Ok(())
    }

    /// Inicia la suscripción para recibir mensajes.
    /// Debe llamarse después de add_relays() y antes de poll_messages().
    pub fn subscribe(&mut self) -> Result<()> {
        // Fetch messages based on n_seconds
        // Filter 1: Messages sent TO me (any kind)
        let filter_to_me = Filter::new()
            .pubkey(self.keys.public_key())
            .limit(self.n_limit)
            .since(Timestamp::from(Timestamp::now().as_u64().saturating_sub(self.n_seconds)));
            
        // Filter 2: Messages FROM the peer (any kind)
        let filter_from_peer = Filter::new()
            .author(self.peer_pk)
            .limit(self.n_limit)
            .since(Timestamp::from(Timestamp::now().as_u64().saturating_sub(self.n_seconds)));

        self.logs.push(format!(
            "subscribe: para mí={} · del peer={}",
            self.keys.public_key().to_bech32()?,
            self.peer_pk.to_bech32()?
        ));

        let sub_id = self.runtime.block_on(async {
            // Subscribe to messages TO me
            let id1 = self
                .client
                .subscribe(filter_to_me, None)
                .await
                .map_err(|e| anyhow!("subscribe(to_me): {e}"))?;
            let id2 = self
                .client
                .subscribe(filter_from_peer, None)
                .await
                .map_err(|e| anyhow!("subscribe(from_peer): {e}"))?;
            Ok::<_, anyhow::Error>(id1)
        })?;

        self.subscription_id = Some(sub_id.id().clone());

        // Inicializar el receiver de notificaciones UNA VEZ
        let notifications_receiver = self.client.notifications();
        self.runtime.block_on(async {
            *self.notifications.lock().await = Some(notifications_receiver);
        });
        self.logs.push("✓ suscripto (2 filtros) · receiver listo");

        Ok(())
    }

    /// Drena el registro de eventos para mostrarlo en la UI.
    pub fn take_logs(&self) -> Vec<String> {
        self.logs.drain()
    }
    /// Envía un mensaje privado al destinatario.
    /// 
    /// # Argumentos
    /// * `message` - Contenido del mensaje a enviar
    pub fn send_message(&self, message: &str) -> Result<()> {
        self.logs
            .push(format!("send NIP-17: {} chars…", message.len()));
        let logs = self.logs.clone();
        self.runtime.block_on(async {
            self.client
                .send_private_msg(self.peer_pk, message, [])
                .await
                .context("Failed to send private message")?;
            logs.push("✓ enviado al relay");
            Ok::<(), anyhow::Error>(())
        })?;
        Ok(())
    }

    /// Obtiene los mensajes recibidos desde el peer especificado.
    /// Espera hasta 2 segundos para que lleguen mensajes de los relays.
    /// 
    /// # Retorna
    /// Vector de mensajes recibidos (puede estar vacío si no hay mensajes nuevos)
    pub fn poll_messages(&self) -> Result<Vec<ReceivedMessage>> {
        let mut messages = Vec::new();
        let mut event_count = 0;
        let mut system_count = 0;
        let mut giftwrap_count = 0;
        let mut unwrap_errors = 0usize;
        let mut has_receiver = true;

        self.runtime.block_on(async {
            // Reutilizar el receiver de notificaciones existente
            let mut notifications_guard = self.notifications.lock().await;
            if notifications_guard.is_none() {
                // antes: silencio total. Ahora el host ve por qué no llega nada.
                has_receiver = false;
                return;
            }
            
            let notifications = notifications_guard.as_mut().unwrap();
            let timeout_duration = tokio::time::Duration::from_secs(self.poll_timeout);
            let deadline = tokio::time::Instant::now() + timeout_duration;
            

            
            // Esperar mensajes hasta el timeout
            loop {
                let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
                if remaining.is_zero() {
                    break;
                }
                
                match tokio::time::timeout(remaining, notifications.recv()).await {
                    Ok(Ok(notification)) => {
                        // Loguear qué tipo de notificación es
                        match &notification {
                            RelayPoolNotification::Event { relay_url, event, .. } => {
                                event_count += 1;
                                // Gtool anotaba TODOS los eventos; sin esta
                                // línea el log calla y parece que no consulta.
                                self.logs.push(format!(
                                    "ev kind {} vía {}",
                                    event.kind,
                                    relay_url.as_str()));
                                if event.kind == Kind::GiftWrap {
                                    giftwrap_count += 1;
                                    match self.client.unwrap_gift_wrap(&event).await {
                                        Ok(UnwrappedGift { sender, rumor }) => {
                                            // Solo mensajes del peer seleccionado
                                            if rumor.kind == Kind::PrivateDirectMessage && sender == self.peer_pk {
                                                messages.push(ReceivedMessage {
                                                    sender,
                                                    content: rumor.content,
                                                    timestamp: rumor.created_at,
                                                });
                                                self.logs.push(format!(
                                                    "✓ DM del peer vía {relay_url}"));
                                            } else {
                                                self.logs.push(format!(
                                                    "giftwrap de otro ({}, kind {}) descartado",
                                                    &sender.to_hex()[..8.min(sender.to_hex().len())],
                                                    rumor.kind));
                                            }
                                        }
                                        Err(e) => {
                                            unwrap_errors += 1;
                                            self.logs.push(format!(
                                                "✗ desencriptado falló: {e}"));
                                        }
                                    }
                                } else if event.kind == Kind::EncryptedDirectMessage {
                                    self.logs.push(
                                        "⚠ mensaje legado kind-4 (esperamos NIP-17)".to_string());
                                }
                            },
                            RelayPoolNotification::Message { relay_url, message } => {
                                system_count += 1;
                             //   println!("      [DEBUG] Mensaje de sistema de {}: {:?}", relay_url, message);
                            },
                            RelayPoolNotification::Shutdown => {
                                self.logs.push("⚠ relay pool shutdown".to_string());
                            },

                        }
                    }
                    Ok(Err(_)) | Err(_) => break, // Error o timeout
                }
            }
            
        });

        if !has_receiver {
            self.logs.push("✗ poll sin receiver: ¿llamaste a subscribe()?");
            return Err(anyhow!("sin receiver de notificaciones"));
        }
        // Resumen SIEMPRE (igual que el [DEBUG] Resumen de Gtool): si solo
        // logueamos cuando hay algo, un tick vacío es indistinguible de un
        // cliente muerto.
        self.logs.push(format!(
            "poll: {event_count} eventos · {giftwrap_count} giftwraps · {unwrap_errors} fallos · {} válidos",
            messages.len()
        ));

        Ok(messages)
    }

    /// Obtiene la clave pública del usuario.
    pub fn get_public_key(&self) -> Result<String> {
        Ok(self.keys.public_key().to_bech32()?)
    }

    /// Obtiene la clave pública del destinatario.
    pub fn get_peer_public_key(&self) -> Result<String> {
        Ok(self.peer_pk.to_bech32()?)
    }

    /// Desconecta del cliente y limpia recursos.
    pub fn disconnect(&mut self) -> Result<()> {
        if let Some(sub_id) = &self.subscription_id {
            self.runtime.block_on(async {
                self.client.unsubscribe(&sub_id).await;
            });
            self.subscription_id = None;
        }
        
        self.runtime.block_on(async {
            self.client.disconnect().await
        });
        
        Ok(())
    }
}

/// Representa un mensaje recibido
#[derive(Debug, Clone)]
pub struct ReceivedMessage {
    pub sender: PublicKey,
    pub content: String,
    pub timestamp: Timestamp,
}

impl Drop for NostrClient {
    fn drop(&mut self) {
        let _ = self.disconnect();
    }
}
