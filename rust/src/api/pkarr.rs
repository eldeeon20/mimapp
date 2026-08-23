/// PKARR (DNS descentralizado) — portado de Gtool `pkarrgodot.rs` sin Godot.
///
/// Claves ed25519 de 32 bytes; paquetes firmados con registro TXT;
/// publicación/resolución por relays HTTPS y/o DHT (Mainline).
use std::convert::TryInto;

use pkarr::{Keypair, SignedPacket};
use pkarr::dns::{rdata::TXT, Name};

pub const DEFAULT_RELAYS: &[&str] = &["https://relay.pkarr.org", "https://pkarr.pubky.org"];

enum Mode {
    Dht,
    Relays,
    Both,
}

fn parse_mode(mode: &str) -> Mode {
    match mode.to_lowercase().as_str() {
        "dht" => Mode::Dht,
        "relays" => Mode::Relays,
        _ => Mode::Both,
    }
}

fn build_client(mode: &str, relays: &[String]) -> Result<pkarr::Client, String> {
    let mut builder = pkarr::Client::builder();
    match parse_mode(mode) {
        Mode::Dht => {
            builder.no_relays();
        }
        Mode::Relays => {
            builder.no_dht();
            builder
                .relays(relays)
                .map_err(|e| format!("Error al configurar relays: {e:?}"))?;
        }
        Mode::Both => {}
    }
    builder.build().map_err(|e| format!("Error al construir cliente: {e:?}"))
}

fn keypair_from_secret(secret: &[u8]) -> Result<Keypair, String> {
    if secret.len() != 32 {
        return Err(format!(
            "La clave debe tener exactamente 32 bytes, pero tiene {}",
            secret.len()
        ));
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(secret);
    Ok(Keypair::from_secret_key(&arr))
}

/// Secreto aleatorio (32 bytes).
#[flutter_rust_bridge::frb]
pub fn pkarr_key_rand() -> Vec<u8> {
    Keypair::random().secret_key().to_vec()
}

/// Secreto determinístico desde una semilla textual (SHA256 → 32 bytes).
#[flutter_rust_bridge::frb]
pub fn pkarr_seed_to_key(seed: String) -> Vec<u8> {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.finalize().to_vec()
}

/// Clave pública zbase32 a partir del secreto. Vacío si es inválido.
#[flutter_rust_bridge::frb]
pub fn pkarr_public_key(secret: Vec<u8>) -> String {
    match keypair_from_secret(&secret) {
        Ok(kp) => kp.public_key().to_string(),
        Err(_) => String::new(),
    }
}

/// Firma un TXT (`name` = `value`) con el secreto y lo publica.
/// mode: "dht" | "relays" | "both".
#[flutter_rust_bridge::frb]
pub async fn pkarr_publish(
    secret: Vec<u8>,
    name: String,
    value: String,
    mode: String,
    relays: Vec<String>,
    ttl: u32,
) -> bool {
    let keypair = match keypair_from_secret(&secret) {
        Ok(kp) => kp,
        Err(e) => {
            eprintln!("pkarr_publish: {e}");
            return false;
        }
    };
    let converted: Name = match name.as_str().try_into() {
        Ok(n) => n,
        Err(e) => {
            eprintln!("pkarr_publish: nombre inválido {e:?}");
            return false;
        }
    };
    let txt: TXT = match value.as_str().try_into() {
        Ok(t) => t,
        Err(e) => {
            eprintln!("pkarr_publish: valor TXT inválido {e:?}");
            return false;
        }
    };
    let client = match build_client(&mode, &relays) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("pkarr_publish: {e}");
            return false;
        }
    };
    let signed_packet = match SignedPacket::builder()
        .txt(converted, txt, ttl)
        .sign(&keypair)
    {
        Ok(p) => p,
        Err(e) => {
            eprintln!("pkarr_publish: error al firmar {e:?}");
            return false;
        }
    };

    let result = client.publish(&signed_packet, None).await;
    match result {
        Ok(()) => {
            eprintln!("pkarr_publish: publicado {}", keypair.public_key());
            true
        }
        Err(err) => {
            eprintln!(
                "pkarr_publish: falló la publicación de {}\n{err}",
                keypair.public_key()
            );
            false
        }
    }
}

/// Resuelve la clave pública (zbase32) → paquete como texto. Vacío si falla.
#[flutter_rust_bridge::frb]
pub async fn pkarr_resolve(
    pubkey_zbase32: String,
    mode: String,
    relays: Vec<String>,
) -> String {
    let public_key = match pubkey_zbase32.as_str().try_into() {
        Ok(pk) => pk,
        Err(_) => {
            eprintln!("pkarr_resolve: clave zbase32 inválida");
            return String::new();
        }
    };
    let client = match build_client(&mode, &relays) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("pkarr_resolve: {e}");
            return String::new();
        }
    };
    match client.resolve(&public_key).await {
        Some(packet) => packet.to_string(),
        None => {
            eprintln!("pkarr_resolve: falló la resolución de {pubkey_zbase32}");
            String::new()
        }
    }
}
