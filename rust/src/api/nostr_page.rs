/// Páginas Lua publicadas en Nostr — transporte del PageRouter.
///
/// Convención: la página es el content de un evento kind 30023 (NIP-23
/// long-form) con tag `d = <nombre>`. El router pide
/// `nostrn://<npub|hex>/<nombre>` y acá se consulta a los relays.
use anyhow::{anyhow, Result};
use nostr_sdk::prelude::*;
use std::str::FromStr;
use tokio::runtime::Runtime;

pub const DEFAULT_RELAYS: &[&str] = &[
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://relay.nostr.wine",
];

/// Busca el evento kind 30023 de [author] con tag d=[name] y retorna su
/// content (el código Lua). [relays] vacío o None = usa los defaults.
/// Timeout 8s; error si no aparece.
#[flutter_rust_bridge::frb]
pub fn nostr_page_fetch(
    npub_or_hex: String,
    name: String,
    relays: Option<Vec<String>>,
) -> Result<String> {
    // acepta bech32 o hex
    let author = if npub_or_hex.starts_with("npub") {
        PublicKey::from_bech32(&npub_or_hex)
            .map_err(|e| anyhow!("npub inválida: {e}"))?
    } else {
        PublicKey::from_str(&npub_or_hex)
            .map_err(|e| anyhow!("pubkey hex inválida: {e}"))?
    };

    // Default SOLO si no pasaron nada o la lista vino vacía.
    let relay_list: Vec<String> = match relays {
        Some(r) if !r.is_empty() => r,
        _ => DEFAULT_RELAYS.iter().map(|s| s.to_string()).collect(),
    };

    let rt = Runtime::new().map_err(|e| anyhow!("runtime: {e}"))?;
    rt.block_on(async move {
        let client = Client::new(Keys::generate());
        for r in relay_list {
            let _ = client.add_relay(r).await;
        }
        client.connect().await;

        let filter = Filter::new()
            .author(author)
            .kind(Kind::Custom(30023))
            .identifier(name.clone())
            .limit(1);

        let events = client
            .fetch_events(filter, std::time::Duration::from_secs(8))
            .await
            .map_err(|e| anyhow!("fetch_events: {e}"))?;

        match events.into_iter().next() {
            Some(ev) => Ok(ev.content),
            None => Err(anyhow!(
                "página nostr no encontrada: {name} (autor {})",
                author.to_hex()
            )),
        }
    })
}
