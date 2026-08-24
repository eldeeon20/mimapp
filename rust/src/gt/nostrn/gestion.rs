//! Gestión de cuentas nostrn ("Nostrn+"):
//! - crear/cargar identidad guardada en el celular (PIN cifrado AES-GCM/
//!   PBKDF2, o plano si el PIN viene vacío para pruebas rápidas)
//! - perfil kind 0 propio (editar y ver el de otros)
//! - bandeja de entrada SIN peer configurado: escucha todo lo dirigido a
//!   mi pubkey; quién mandó se descubre dentro del giftwrap (NIP-59/NIP-17,
//!   cifrado NIP-44)
//! - chat 1-a-1 fijando peer y usando NIP-17 (send_private_msg)
//!
//! Misma mecánica NO bloqueante que NostrClient: subscribe() bufferiza en
//! canal broadcast y poll drena con try_recv() en microsegundos.

use anyhow::{anyhow, Context, Result};
use nostr::prelude::*;
use nostr_sdk::prelude::*;
use std::path::Path;
use std::sync::Arc;
use tokio::runtime::Runtime;
use tokio::sync::{broadcast, Mutex};

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use pbkdf2::pbkdf2_hmac;
use sha2::Sha256;

use crate::gt::eventlog::EventLog;
use crate::gt::nostrn::relays::{compose_write_relays, connect_relays};

/// Formato del archivo de cuenta cifrada:
/// "NRN1" || salt[16] || nonce[12] || ciphertext(JSON {nombre,npub,nsec})
const CUENTA_MAGIC: &[u8; 4] = b"NRN1";
const PBKDF2_ITERS: u32 = 200_000;

// ---------------------------------------------------------------- crypto

fn derive_pin_key(pin: &str, salt: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    pbkdf2_hmac::<Sha256>(pin.as_bytes(), salt, PBKDF2_ITERS, &mut out);
    out
}

fn encrypt_payload(pin: &str, payload: &[u8]) -> Result<Vec<u8>> {
    let mut salt = [0u8; 16];
    rand_bytes(&mut salt);
    let nonce_bytes: [u8; 12] = rand::random();
    let cipher = Aes256Gcm::new_from_slice(&derive_pin_key(pin, &salt)[..])
        .map_err(|e| anyhow!("AES init: {e:?}"))?;
    let ct = cipher
        .encrypt(Nonce::from_slice(&nonce_bytes), payload)
        .map_err(|e| anyhow!("AES encrypt: {e:?}"))?;
    let mut blob = Vec::with_capacity(CUENTA_MAGIC.len() + 28 + ct.len());
    blob.extend_from_slice(CUENTA_MAGIC);
    blob.extend_from_slice(&salt);
    blob.extend_from_slice(&nonce_bytes);
    blob.extend_from_slice(&ct);
    Ok(blob)
}

fn decrypt_payload(pin: &str, blob: &[u8]) -> Result<Vec<u8>> {
    if blob.len() < CUENTA_MAGIC.len() + 28 {
        return Err(anyhow!("archivo de cuenta truncado"));
    }
    if &blob[..CUENTA_MAGIC.len()] != CUENTA_MAGIC {
        return Err(anyhow!("archivo de cuenta con formato desconocido"));
    }
    let salt = &blob[CUENTA_MAGIC.len()..CUENTA_MAGIC.len() + 16];
    let nonce = &blob[CUENTA_MAGIC.len() + 16..CUENTA_MAGIC.len() + 28];
    let ct = &blob[CUENTA_MAGIC.len() + 28..];
    let cipher = Aes256Gcm::new_from_slice(&derive_pin_key(pin, salt)[..])
        .map_err(|e| anyhow!("AES init: {e:?}"))?;
    cipher
        .decrypt(Nonce::from_slice(nonce), ct)
        .map_err(|_| anyhow!("PIN incorrecto o archivo corrupto"))
}

fn rand_bytes(out: &mut [u8]) {
    let rnd: Vec<u8> = (0..out.len()).map(|_| rand::random::<u8>()).collect();
    out.copy_from_slice(&rnd);
}

// --------------------------------------------------------------- cuenta

#[derive(Clone)]
pub struct CuentaGuardada {
    pub nombre: String,
    pub npub: String,
    pub nsec: String,
}

impl CuentaGuardada {
    fn to_json(&self) -> Result<Vec<u8>> {
        Ok(serde_json::to_vec(&serde_json::json!({
            "nombre": self.nombre,
            "npub": self.npub,
            "nsec": self.nsec,
        }))?)
    }

    fn from_json(bytes: &[u8]) -> Result<Self> {
        let j: serde_json::Value =
            serde_json::from_slice(bytes).context("JSON de cuenta ilegible")?;
        Ok(Self {
            nombre: j["nombre"].as_str().unwrap_or_default().to_string(),
            npub: j["npub"].as_str().unwrap_or_default().to_string(),
            nsec: j["nsec"].as_str().unwrap_or_default().to_string(),
        })
    }
}

fn cuenta_path(dir: &str) -> String {
    Path::new(dir)
        .join("nostrn_cuenta.bin")
        .to_string_lossy()
        .into_owned()
}

/// Genera identidad nueva y la guarda. PIN vacío = archivo plano (solo
/// pruebas); con PIN queda cifrada AES-GCM/PBKDF2 igual que pkarr.
pub fn crear_cuenta(pin: &str, dir: &str, nombre: &str) -> Result<CuentaGuardada> {
    let keys = Keys::generate();
    let cuenta = CuentaGuardada {
        nombre: nombre.to_string(),
        npub: keys.public_key().to_bech32()?,
        nsec: keys.secret_key().to_bech32()?,
    };
    guardar_cuenta(pin, dir, &cuenta)?;
    Ok(cuenta)
}

/// Guarda una cuenta existente con ese PIN.
pub fn guardar_cuenta(pin: &str, dir: &str, cuenta: &CuentaGuardada) -> Result<()> {
    let path = cuenta_path(dir);
    let json = cuenta.to_json()?;
    let blob = if pin.is_empty() {
        json // plano: arranca con '{' y cargar lo detecta
    } else {
        encrypt_payload(pin, &json)?
    };
    std::fs::write(&path, blob).map_err(|e| anyhow!("escribiendo {}: {e}", path))
}

/// Carga la cuenta guardada con ese PIN.
pub fn cargar_cuenta(pin: &str, dir: &str) -> Result<CuentaGuardada> {
    let path = cuenta_path(dir);
    let blob = std::fs::read(&path)
        .map_err(|e| anyhow!("leyendo {}: {e} (¿creá una cuenta primero?)", path))?;
    let json = if blob.first() == Some(&b'{') {
        blob
    } else if pin.is_empty() {
        return Err(anyhow!("la cuenta está cifrada: ingresá tu PIN"));
    } else {
        decrypt_payload(pin, &blob)?
    };
    CuentaGuardada::from_json(&json)
}

/// ¿Existe cuenta guardada?
pub fn hay_cuenta(dir: &str) -> bool {
    Path::new(&cuenta_path(dir)).exists()
}

// -------------------------------------------------------------- cliente

/// Mensaje recibido en la bandeja (de cualquier remitente).
#[derive(Clone)]
pub struct MsgIn {
    pub sender: PublicKey,
    pub content: String,
    pub timestamp: Timestamp,
}

/// Cliente vivo sin peer obligatorio: bandeja primero, chat después.
pub struct GestionNostrn {
    client: Client,
    keys: Keys,
    peer_pk: Option<PublicKey>,
    runtime: Arc<Runtime>,
    subscription_id: Option<SubscriptionId>,
    notifications: Arc<Mutex<Option<broadcast::Receiver<RelayPoolNotification>>>>,
    pub n_seconds: u64,
    pub n_limit: usize,
    pub logs: EventLog,
}

impl GestionNostrn {
    /// nsec vacío/None = identidad nueva efímera (para probar la bandeja).
    pub fn new(nsec: Option<&str>) -> Result<Self> {
        let keys = match nsec.filter(|s| !s.trim().is_empty()) {
            Some(s) => Keys::parse(s.trim()).context("nsec inválido")?,
            None => Keys::generate(),
        };
        let client = Client::builder().signer(keys.clone()).build();
        let runtime = Arc::new(
            tokio::runtime::Builder::new_multi_thread()
                .enable_all()
                .build()
                .context("creando runtime tokio")?,
        );
        Ok(Self {
            client,
            keys,
            peer_pk: None,
            runtime,
            subscription_id: None,
            notifications: Arc::new(Mutex::new(None)),
            n_seconds: 3600,
            n_limit: 20,
            logs: EventLog::new(),
        })
    }

    /// Relays DM + lectura (idéntico contrato que NostrClient::add_relays).
    pub fn add_relays(
        &mut self,
        dm_relays: Vec<String>,
        read_relays: Option<Vec<String>>,
    ) -> Result<()> {
        if dm_relays.is_empty() {
            return Err(anyhow!("se requiere al menos un relay DM"));
        }
        let read = match read_relays {
            Some(r) if !r.is_empty() => r,
            _ => dm_relays.clone(),
        };
        let write = compose_write_relays(&dm_relays);
        self.logs.push("connect(): conectando relays…".to_string());
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

    /// Se suscribe SOLO a lo dirigido a mí: la bandeja atrapa mensajes de
    /// cualquiera; el remitente real viene dentro del giftwrap.
    /// n_seconds == 0 → SIN filtro de tiempo: NIP-59 recomienda timestamps
    /// randomizados en el envoltorio, así que "desde hace 1 hora" puede
    /// descartar mensajes recién enviados. Con 0 traemos TODO lo nuestro.
    pub fn subscribe(&mut self) -> Result<()> {
        let mut filtro = Filter::new()
            .pubkey(self.keys.public_key())
            .limit(self.n_limit);
        if self.n_seconds > 0 {
            filtro = filtro.since(Timestamp::from(
                Timestamp::now().as_u64().saturating_sub(self.n_seconds),
            ));
        }

        let sub_id = self
            .runtime
            .block_on(async { self.client.subscribe(filtro, None).await })
            .context("subscribe falló")?;

        self.subscription_id = Some(sub_id.id().clone());
        let receiver = self.client.notifications();
        self.runtime.block_on(async {
            *self.notifications.lock().await = Some(receiver);
        });
        self.logs.push(format!(
            "✓ bandeja suscripta · yo={}",
            self.keys.public_key().to_bech32()?
        ));
        Ok(())
    }

    /// Fija (o cambia) el peer del chat 1-a-1. Acepta bech32 o hex.
    pub fn set_peer(&mut self, npub: &str) -> Result<()> {
        let pk = PublicKey::from_bech32(npub)
            .or_else(|_| npub.parse::<PublicKey>().map_err(|e| anyhow!("{e:?}")))
            .context(format!("peer inválido: {npub}"))?;
        self.peer_pk = Some(pk);
        self.logs
            .push(format!("✓ peer fijado: {}", pk.to_bech32()?));
        Ok(())
    }

    pub fn get_peer(&self) -> Option<String> {
        self.peer_pk
            .as_ref()
            .and_then(|p| p.to_bech32().ok())
    }

    /// Mi npub (bech32).
    pub fn get_public_key(&self) -> Result<String> {
        Ok(self.keys.public_key().to_bech32()?)
    }

    /// Envía al peer fijado vía NIP-17 (que cifra con NIP-44 adentro).
    pub fn send_message(&self, message: &str) -> Result<()> {
        let peer = self
            .peer_pk
            .ok_or_else(|| anyhow!("sin peer: fijá uno desde la bandeja o a mano"))?;
        let logs = self.logs.clone();
        self.runtime.block_on(async {
            self.client
                .send_private_msg(peer, message, [])
                .await
                .context("send_private_msg falló")?;
            logs.push(format!("✓ enviado {} chars", message.len()));
            Ok::<(), anyhow::Error>(())
        })?;
        Ok(())
    }

    /// Drena la bandeja: TODO DM privado dirigido a mí, de quien sea.
    pub fn poll_messages(&self) -> Result<Vec<MsgIn>> {
        let mut messages = Vec::new();

        let mut guard = self.notifications.blocking_lock();
        let notifications = match guard.as_mut() {
            Some(n) => n,
            None => {
                drop(guard);
                return Err(anyhow!(
                    "poll sin receiver: llamá conectar+suscribir primero"
                ));
            }
        };

        loop {
            match notifications.try_recv() {
                Ok(RelayPoolNotification::Event { event, .. }) => {
                    if event.kind == Kind::GiftWrap {
                        let res = self.runtime.block_on(async {
                            self.client.unwrap_gift_wrap(&event).await
                        });
                        match res {
                            Ok(UnwrappedGift { sender, rumor }) => {
                                // Aceptamos CUALQUIER kind interno del
                                // giftwrap: otros clientes pueden envolver
                                // kinds que no son 14 y antes los tirábamos
                                // sin rastro.
                                let hex = sender.to_string();
                                self.logs.push(format!(
                                    "✓ bandeja: kind {} de {}…",
                                    rumor.kind,
                                    &hex[..8.min(hex.len())]
                                ));
                                messages.push(MsgIn {
                                    sender,
                                    content: rumor.content,
                                    timestamp: rumor.created_at,
                                });
                            }
                            Err(e) => {
                                self.logs
                                    .push(format!("✗ desencriptado falló: {e}"));
                            }
                        }
                    }
                }
                Ok(_) => {}
                Err(broadcast::error::TryRecvError::Empty) => break,
                Err(broadcast::error::TryRecvError::Lagged(n)) => {
                    self.logs
                        .push(format!("⚠ receiver lageado: perdidos {n}"));
                    continue;
                }
                Err(broadcast::error::TryRecvError::Closed) => break,
            }
        }
        drop(guard);

        self.logs
            .push(format!("poll bandeja: {} mensaje(s)", messages.len()));
        Ok(messages)
    }

    /// Publica MI perfil kind 0. Campos vacíos no se tocan; picture es
    /// una URL externa (https://...).
    pub fn set_perfil(
        &self,
        name: &str,
        display_name: &str,
        about: &str,
        picture: &str,
    ) -> Result<()> {
        let mut md = Metadata::new();
        if !name.is_empty() {
            md.name = Some(name.to_string());
        }
        if !display_name.is_empty() {
            md.display_name = Some(display_name.to_string());
        }
        if !about.is_empty() {
            md.about = Some(about.to_string());
        }
        if !picture.is_empty() {
            // validamos que sea URL bien formada; el campo guarda String
            let _ = Url::parse(picture)
                .map_err(|e| anyhow!("URL de foto inválida: {e:?}"))?;
            md.picture = Some(picture.to_string());
        }
        if md == Metadata::new() {
            return Err(anyhow!("todo vacío: no hay nada que publicar"));
        }
        let logs = self.logs.clone();
        self.runtime.block_on(async {
            self.client.set_metadata(&md).await.context("set_metadata")?;
            logs.push("✓ perfil kind 0 publicado".to_string());
            Ok::<(), anyhow::Error>(())
        })?;
        Ok(())
    }

    /// Drena el registro de eventos.
    pub fn take_logs(&self) -> Vec<String> {
        self.logs.drain()
    }

    /// Desconecta relays.
    pub fn disconnect(&mut self) -> Result<()> {
        if let Some(sub_id) = &self.subscription_id {
            self.runtime.block_on(async {
                self.client.unsubscribe(sub_id).await;
            });
            self.subscription_id = None;
        }
        self.logs.push("✓ desconectado".to_string());
        Ok(())
    }
}
