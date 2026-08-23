use librqbit::{AddTorrent, AddTorrentOptions};

use super::limits;

/// Agrega por magnet o URL de .torrent (torrent_create_from_url).
/// Límites por torrent en bytes/s además de los globales.
pub async fn torrent_add_url(
    url: String,
    down_bps: Option<u32>,
    up_bps: Option<u32>,
) -> Result<Option<u32>, String> {
    add_torrent(
        AddTorrent::Url(url.into()),
        down_bps,
        up_bps,
    )
    .await
}

/// Agrega desde un archivo .torrent local (equivale al base64 del desktop).
pub async fn torrent_add_bytes(
    bytes: Vec<u8>,
    down_bps: Option<u32>,
    up_bps: Option<u32>,
) -> Result<Option<u32>, String> {
    add_torrent(
        AddTorrent::TorrentFileBytes(bytes.into()),
        down_bps,
        up_bps,
    )
    .await
}

async fn add_torrent(
    add: AddTorrent<'_>,
    down_bps: Option<u32>,
    up_bps: Option<u32>,
) -> Result<Option<u32>, String> {
    let a = super::api()?;
    // overwrite=true permite reanudar sobre datos ya descargados.
    let opts = AddTorrentOptions {
        overwrite: true,
        ratelimits: limits(down_bps, up_bps), // límites POR TORRENT
        ..Default::default()
    };
    let r = a
        .api_add_torrent(add, Some(opts))
        .await
        .map_err(|e| e.to_string())?;
    Ok(r.id.map(|i| i as u32))
}
