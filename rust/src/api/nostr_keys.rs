/// Generador de claves Nostr — portado de Gtool `keytool.rs` sin Godot.
use nostr::prelude::*;
use std::str::FromStr;

/// Clave privada aleatoria (32 bytes).
#[flutter_rust_bridge::frb]
pub fn nostr_generate_key() -> Vec<u8> {
    let keys = Keys::generate();
    keys.secret_key().secret_bytes().to_vec()
}

/// Clave derivada de una semilla textual (SHA256 → 32 bytes).
#[flutter_rust_bridge::frb]
pub fn nostr_seed_to_key(seed: String) -> Vec<u8> {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.finalize().to_vec()
}

/// Bytes de clave privada → nsec (bech32). Vacío si son inválidos.
#[flutter_rust_bridge::frb]
pub fn nostr_to_nsec(secret: Vec<u8>) -> String {
    let Some(sk) = secret_from_bytes(&secret) else { return String::new() };
    let keys = Keys::new(sk);
    match keys.secret_key().to_bech32() {
        Ok(nsec) => nsec,
        Err(_) => String::new(),
    }
}

/// Bytes de clave privada → npub (bech32). Vacío si son inválidos.
#[flutter_rust_bridge::frb]
pub fn nostr_to_npub(secret: Vec<u8>) -> String {
    let Some(sk) = secret_from_bytes(&secret) else { return String::new() };
    let keys = Keys::new(sk);
    match keys.public_key().to_bech32() {
        Ok(npub) => npub,
        Err(_) => String::new(),
    }
}

/// npub (bech32 o hex) → hex. Vacío si es inválido.
#[flutter_rust_bridge::frb]
pub fn nostr_hex_npub(npub: String) -> String {
    match PublicKey::from_bech32(&npub) {
        Ok(pk) => pk.to_string(),
        Err(_) => String::new(),
    }
}

/// nsec (bech32 o hex) → hex. Vacío si es inválido.
#[flutter_rust_bridge::frb]
pub fn nostr_hex_nsec(nsec: String) -> String {
    match SecretKey::from_bech32(&nsec) {
        Ok(sk) => sk.to_secret_hex(),
        Err(_) => String::new(),
    }
}

/// Valida y normaliza un npub (acepta bech32 o hex, devuelve bech32).
#[flutter_rust_bridge::frb]
pub fn nostr_validate_npub(input: String) -> String {
    if let Ok(pk) = PublicKey::from_bech32(&input) {
        return pk.to_bech32().unwrap_or_default();
    }
    if let Ok(pk) = PublicKey::from_str(&input) {
        return pk.to_bech32().unwrap_or_default();
    }
    String::new()
}

/// Valida y normaliza un nsec (acepta bech32 o hex, devuelve bech32).
#[flutter_rust_bridge::frb]
pub fn nostr_validate_nsec(input: String) -> String {
    if let Ok(sk) = SecretKey::from_bech32(&input) {
        return sk.to_bech32().unwrap_or_default();
    }
    if let Ok(sk) = SecretKey::from_str(&input) {
        return sk.to_bech32().unwrap_or_default();
    }
    String::new()
}

/// Hex de la clave pública a partir de bytes del secreto.
#[flutter_rust_bridge::frb]
pub fn nostr_pubkey_hex_from_secret(secret: Vec<u8>) -> String {
    let Some(sk) = secret_from_bytes(&secret) else { return String::new() };
    Keys::new(sk).public_key().to_string()
}

fn secret_from_bytes(secret: &[u8]) -> Option<SecretKey> {
    let bytes: [u8; 32] = secret.try_into().ok()?;
    SecretKey::from_slice(&bytes).ok()
}
