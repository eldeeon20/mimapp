/// Nostr Busca: perfiles y búsqueda de usuarios (B1 npub→kind 0,
/// B2 NIP-50 por texto). Wrapper FRB fino sobre `gt::nostrbusca`.
use crate::gt::nostrbusca::{buscar_usuarios, perfil_fetch, Perfil};

/// Perfil de usuario Nostr serializable a Dart.
#[flutter_rust_bridge::frb]
#[derive(Clone)]
pub struct PerfilItem {
    pub npub: String,
    pub name: String,
    pub display_name: String,
    pub about: String,
    pub picture: String,
    pub nip05: String,
}

fn mapear(p: Perfil) -> PerfilItem {
    PerfilItem {
        npub: p.npub,
        name: p.name,
        display_name: p.display_name,
        about: p.about,
        picture: p.picture,
        nip05: p.nip05,
    }
}

fn a_relays(relays: Vec<String>) -> Vec<String> {
    if relays.is_empty() {
        vec![
            "wss://relay.damus.io".to_string(),
            "wss://nos.social".to_string(),
            "wss://relay.nostr.band".to_string(),
            "wss://search.nos.today".to_string(),
        ]
    } else {
        relays
    }
}

/// B1: perfil completo de un npub (bech32 o hex).
#[flutter_rust_bridge::frb]
pub fn nostr_perfil_fetch(
    npub: String,
    relays: Vec<String>,
    timeout_secs: i64,
) -> Result<PerfilItem, String> {
    perfil_fetch(
        &npub,
        &a_relays(relays),
        timeout_secs.max(1) as u64,
    )
    .map(mapear)
    .map_err(|e| format!("{e:#}"))
}

/// B2: búsqueda por texto (NIP-50; requiere relay que lo soporte).
/// Sin resultados = lista vacía.
#[flutter_rust_bridge::frb]
pub fn nostr_buscar_usuarios(
    query: String,
    relays: Vec<String>,
    limite: i64,
    timeout_secs: i64,
) -> Result<Vec<PerfilItem>, String> {
    buscar_usuarios(
        &query,
        &a_relays(relays),
        limite.max(1) as usize,
        timeout_secs.max(1) as u64,
    )
    .map(|v| v.into_iter().map(mapear).collect())
    .map_err(|e| format!("{e:#}"))
}
