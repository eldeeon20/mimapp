use librqbit::api::ApiTorrentListOpts;

/// Lista completa con stats (equivalente a torrents_list?withStats=true).
/// Retorna JSON para evitar quirks del mapeo de tipos de FRB.
pub fn torrent_list() -> Result<String, String> {
    let a = super::api()?;
    let list = a.api_torrent_list_ext(ApiTorrentListOpts { with_stats: true });
    let items: Vec<serde_json::Value> = list
        .torrents
        .into_iter()
        .map(|t| {
            let s = t.stats.as_ref();
            json_item(
                t.id.map(|i| i as u32),
                &t.info_hash,
                t.name.as_deref().unwrap_or(&t.info_hash),
                s.map(|st| st.state.to_string()).unwrap_or_default(),
                s.map(|st| st.progress_bytes).unwrap_or(0),
                s.map(|st| st.total_bytes).unwrap_or(0),
                s.map(|st| st.uploaded_bytes).unwrap_or(0),
                s.and_then(|st| st.error.clone()),
                s.map(|st| st.finished).unwrap_or(false),
                s.and_then(|st| st.live.as_ref())
                    .map(|l| l.download_speed.as_bytes())
                    .unwrap_or(0),
                s.and_then(|st| st.live.as_ref())
                    .map(|l| l.upload_speed.as_bytes())
                    .unwrap_or(0),
            )
        })
        .collect();
    serde_json::to_string(&items).map_err(|e| e.to_string())
}

#[allow(clippy::too_many_arguments)]
fn json_item(
    id: Option<u32>,
    info_hash: &str,
    name: &str,
    state: String,
    progress_bytes: u64,
    total_bytes: u64,
    uploaded_bytes: u64,
    error: Option<String>,
    finished: bool,
    down_bps: u64,
    up_bps: u64,
) -> serde_json::Value {
    serde_json::json!({
        "id": id, "info_hash": info_hash, "name": name, "state": state,
        "progress_bytes": progress_bytes, "total_bytes": total_bytes,
        "uploaded_bytes": uploaded_bytes, "error": error,
        "finished": finished, "down_bps": down_bps, "up_bps": up_bps,
    })
}
