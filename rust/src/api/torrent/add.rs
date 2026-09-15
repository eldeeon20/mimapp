use std::sync::Arc;

use librqbit::{AddTorrent, AddTorrentOptions, Api};

use super::limits;

/// Agrega por magnet o URL de .torrent (torrent_create_from_url).
/// Límites por torrent en bytes/s además de los globales.
/// Cada torrent baja a SU subcarpeta (fase 1: nombre, fase 2: real).
pub async fn torrent_add_url(
    url: String,
    down_bps: Option<u32>,
    up_bps: Option<u32>,
) -> Result<Option<u32>, String> {
    let a = super::api()?;
    let sub = nombre_meta(&a, AddTorrent::Url(url.clone().into())).await;
    add_torrent_con(&a, AddTorrent::Url(url.into()), sub, down_bps, up_bps).await
}

/// Agrega desde un archivo .torrent local (equivale al base64 del desktop).
/// Cada torrent baja a SU subcarpeta (fase 1: nombre, fase 2: real).
pub async fn torrent_add_bytes(
    bytes: Vec<u8>,
    down_bps: Option<u32>,
    up_bps: Option<u32>,
) -> Result<Option<u32>, String> {
    let a = super::api()?;
    let sub = nombre_meta(&a, AddTorrent::TorrentFileBytes(bytes.clone().into())).await;
    add_torrent_con(
        &a,
        AddTorrent::TorrentFileBytes(bytes.into()),
        sub,
        down_bps,
        up_bps,
    )
    .await
}

/// Fase 1: agrega en modo solo-lista (sin bajar nada) para conocer el
/// nombre real, lo olvida y devuelve la subcarpeta saneada.
/// Si algo falla → None y el add real va sin subcarpeta (como antes).
async fn nombre_meta(a: &Arc<Api>, add: AddTorrent<'_>) -> Option<String> {
    let meta_opts = AddTorrentOptions {
        list_only: true,
        overwrite: true,
        ..Default::default()
    };
    let meta = a.api_add_torrent(add, Some(meta_opts)).await.ok()?;
    let nombre = meta.details.name?;
    if let Some(id) = meta.id {
        if let Ok(idx) = super::idx(id as u32) {
            let _ = a.api_torrent_action_forget(idx).await;
        }
    }
    Some(sanear_carpeta(&nombre))
}

/// Fase 2: el add real, con subcarpeta si la fase 1 dio nombre.
/// overwrite=true permite reanudar sobre datos ya descargados.
async fn add_torrent_con(
    a: &Arc<Api>,
    add: AddTorrent<'_>,
    sub: Option<String>,
    down_bps: Option<u32>,
    up_bps: Option<u32>,
) -> Result<Option<u32>, String> {
    // overwrite=true permite reanudar sobre datos ya descargados.
    let mut opts = AddTorrentOptions {
        overwrite: true,
        ratelimits: limits(down_bps, up_bps), // límites POR TORRENT
        ..Default::default()
    };
    if let Some(s) = sub {
        opts.sub_folder = Some(s);
    }
    let r = a
        .api_add_torrent(add, Some(opts))
        .await
        .map_err(|e| e.to_string())?;
    Ok(r.id.map(|i| i as u32))
}

/// Nombre a carpeta: solo letras/números/punto/guion/piso/espacio,
/// resto → _, máx 60. Vacío → "torrent".
fn sanear_carpeta(nombre: &str) -> String {
    let l: String = nombre
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '.' || c == '-' || c == '_' || c == ' ' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let t = l.trim();
    if t.is_empty() {
        return "torrent".to_string();
    }
    t.chars().take(60).collect()
}
