//! Nostr Busca: perfiles (kind 0) y búsqueda de usuarios (NIP-50).
//!
//! Cliente EFÍMERO read-only: se crea por consulta y se tira. No comparte
//! nada con nostrn (DM NIP-17) ni nostrpeer (observador) — módulos
//! independientes por regla del proyecto.
use anyhow::{Context, Result};
use nostr_sdk::prelude::*;
use std::time::Duration;
use tokio::runtime::Runtime;

/// Perfil resuelto de un usuario Nostr.
pub struct Perfil {
    pub npub: String,
    pub name: String,
    pub display_name: String,
    pub about: String,
    pub picture: String,
    pub nip05: String,
}

fn nuevo_runtime() -> Result<Runtime> {
    Ok(tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .context("creando runtime tokio")?)
}

/// Cliente efímero read-only conectado a los relays dados (best-effort:
/// un relay caído no mata la consulta).
async fn cliente_readonly(relays: &[String]) -> Client {
    let client = Client::builder()
        .signer(Keys::generate())
        .build();
    for r in relays {
        if let Err(e) = client.add_read_relay(r).await {
            eprintln!("nostrbusca: relay {r} rechazado: {e:?}");
        }
    }
    client.connect().await;
    client
}

fn parsear_npub(npub: &str) -> Result<PublicKey> {
    // Acepta bech32 (npub1...) o hex de 64.
    PublicKey::from_bech32(npub)
        .or_else(|_| npub.parse::<PublicKey>().map_err(|e| anyhow::anyhow!("{e:?}")))
        .context(format!("clave inválida: {npub}"))
}

fn metadata_a_perfil(ev: &Event) -> Result<Perfil> {
    let md =
        Metadata::from_json(ev.content.clone()).context("kind 0 con JSON ilegible")?;
    Ok(Perfil {
        npub: ev.pubkey.to_bech32().unwrap_or_default(),
        name: md.name.unwrap_or_default(),
        display_name: md.display_name.unwrap_or_default(),
        about: md.about.unwrap_or_default(),
        picture: md.picture.map(|u| u.to_string()).unwrap_or_default(),
        nip05: md.nip05.unwrap_or_default(),
    })
}

fn perfil_vacio(pk: &PublicKey) -> Perfil {
    Perfil {
        npub: pk.to_bech32().unwrap_or_default(),
        name: String::new(),
        display_name: String::new(),
        about: String::new(),
        picture: String::new(),
        nip05: String::new(),
    }
}

/// B1: trae el kind 0 más reciente de un npub concreto.
/// Si no encuentra el evento devuelve perfil con campos vacíos (el npub
/// existe como identidad aunque no tenga metadata).
pub fn perfil_fetch(
    npub: &str,
    relays: &[String],
    timeout_secs: u64,
) -> Result<Perfil> {
    let pk = parsear_npub(npub)?;
    let rt = nuevo_runtime()?;
    let filtro = Filter::new()
        .author(pk)
        .kind(Kind::Metadata)
        .limit(1);

    let client = rt.block_on(cliente_readonly(relays));
    let res: Result<Option<Perfil>> = rt.block_on(async {
        let events = client
            .fetch_events(filtro, Duration::from_secs(timeout_secs))
            .await
            .context("consulta al relays falló")?;
        Ok(events
            .iter()
            .max_by_key(|ev| ev.created_at.as_u64())
            .and_then(|ev| metadata_a_perfil(ev).ok()))
    });
    let _ = rt.block_on(client.disconnect());

    match res? {
        Some(p) => Ok(p),
        None => Ok(perfil_vacio(&pk)),
    }
}

/// B2: búsqueda por texto sobre kind 0 (NIP-50 — depende del relay).
/// Ordena por nombre (case-insensitive); sin resultados = vec vacío.
pub fn buscar_usuarios(
    query: &str,
    relays: &[String],
    limite: usize,
    timeout_secs: u64,
) -> Result<Vec<Perfil>> {
    if query.trim().is_empty() {
        return Ok(vec![]);
    }
    let rt = nuevo_runtime()?;
    let filtro = Filter::new()
        .kind(Kind::Metadata)
        .search(query.to_string())
        .limit(limite.max(1) as _);

    let client = rt.block_on(cliente_readonly(relays));
    let res: Result<Vec<Perfil>> = rt.block_on(async {
        let events = client
            .fetch_events(filtro, Duration::from_secs(timeout_secs))
            .await
            .context("consulta a relays falló")?;
        let mut out: Vec<Perfil> = Vec::new();
        for ev in events.iter() {
            match metadata_a_perfil(ev) {
                Ok(p) => out.push(p),
                Err(e) => eprintln!("nostrbusca: evento kind0 ilegible: {e:#}"),
            }
        }
        out.sort_by(|a, b| {
            let ka = if a.display_name.is_empty() { &a.name } else { &a.display_name };
            let kb = if b.display_name.is_empty() { &b.name } else { &b.display_name };
            ka.to_lowercase().cmp(&kb.to_lowercase())
        });
        Ok(out)
    });
    let _ = rt.block_on(client.disconnect());
    res
}

/// Una publicación (nota kind 1) del muro de un usuario.
pub struct Post {
    pub id_hex: String,
    pub autor_npub: String,
    pub contenido: String,
    pub fecha_ms: u64,
}

/// Muro de un npub: sus notas kind 1, ordenadas fecha ↓.
/// [desde_secs] None = sin límite de tiempo; Some(s) = solo posteriores.
pub fn posts_fetch(
    npub: &str,
    relays: &[String],
    limite: usize,
    desde_secs: Option<u64>,
    timeout_secs: u64,
) -> Result<Vec<Post>> {
    let pk = parsear_npub(npub)?;
    let rt = nuevo_runtime()?;
    let mut filtro = Filter::new()
        .author(pk)
        .kind(Kind::TextNote)
        .limit(limite.max(1) as _);
    if let Some(d) = desde_secs {
        filtro = filtro.since(Timestamp::from(d));
    }

    let client = rt.block_on(cliente_readonly(relays));
    let res: Result<Vec<Post>> = rt.block_on(async {
        let events = client
            .fetch_events(filtro, Duration::from_secs(timeout_secs))
            .await
            .context("consulta a relays falló")?;
        let mut out: Vec<Post> = events
            .iter()
            .map(|ev| Post {
                id_hex: ev.id.to_hex(),
                autor_npub: ev.pubkey.to_bech32().unwrap_or_default(),
                contenido: ev.content.clone(),
                fecha_ms: ev.created_at.as_u64() * 1000,
            })
            .collect();
        out.sort_by(|a, b| b.fecha_ms.cmp(&a.fecha_ms));
        Ok(out)
    });
    let _ = rt.block_on(client.disconnect());
    res
}

/// Resultado de búsqueda de posts en la red (kind 1 vía NIP-50).
pub fn buscar_posts(
    query: &str,
    relays: &[String],
    limite: usize,
    timeout_secs: u64,
) -> Result<Vec<Post>> {
    if query.trim().is_empty() {
        return Ok(vec![]);
    }
    let rt = nuevo_runtime()?;
    let filtro = Filter::new()
        .kind(Kind::TextNote)
        .search(query.to_string())
        .limit(limite.max(1) as _);

    let client = rt.block_on(cliente_readonly(relays));
    let res: Result<Vec<Post>> = rt.block_on(async {
        let events = client
            .fetch_events(filtro, Duration::from_secs(timeout_secs))
            .await
            .context("búsqueda de posts falló")?;
        let mut out: Vec<Post> = events
            .iter()
            .map(|ev| Post {
                id_hex: ev.id.to_hex(),
                autor_npub: ev.pubkey.to_bech32().unwrap_or_default(),
                contenido: ev.content.clone(),
                fecha_ms: ev.created_at.as_u64() * 1000,
            })
            .collect();
        out.sort_by(|a, b| b.fecha_ms.cmp(&a.fecha_ms));
        Ok(out)
    });
    let _ = rt.block_on(client.disconnect());
    res
}

/// Notificaciones básicas: kind 1 dirigidos a mí (p tag) → respuestas
/// y menciones. Read-only con el npub alcanza; no necesita claves.
pub fn notificaciones_fetch(
    mi_npub: &str,
    relays: &[String],
    limite: usize,
    timeout_secs: u64,
) -> Result<Vec<Post>> {
    let pk = parsear_npub(mi_npub)?;
    let rt = nuevo_runtime()?;
    let filtro = Filter::new()
        .pubkey(pk)
        .kind(Kind::TextNote)
        .limit(limite.max(1) as _);

    let client = rt.block_on(cliente_readonly(relays));
    let res: Result<Vec<Post>> = rt.block_on(async {
        let events = client
            .fetch_events(filtro, Duration::from_secs(timeout_secs))
            .await
            .context("notificaciones falló")?;
        let mut out: Vec<Post> = events
            .iter()
            .filter(|ev| ev.pubkey != pk) // mis propios posts no cuentan
            .map(|ev| Post {
                id_hex: ev.id.to_hex(),
                autor_npub: ev.pubkey.to_bech32().unwrap_or_default(),
                contenido: ev.content.clone(),
                fecha_ms: ev.created_at.as_u64() * 1000,
            })
            .collect();
        out.sort_by(|a, b| b.fecha_ms.cmp(&a.fecha_ms));
        Ok(out)
    });
    let _ = rt.block_on(client.disconnect());
    res
}
