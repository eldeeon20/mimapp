/// Archivos y peers como JSON (evita quirks de tipos de FRB).
use librqbit::http_api_types::PeerStatsFilter;

/// Archivos con su estado de inclusión actual (torrent_details).
pub fn torrent_files(id: u32) -> Result<String, String> {
    let a = super::api()?;
    let d = a
        .api_torrent_details(super::idx(id)?)
        .map_err(|e| e.to_string())?;
    let files: Vec<serde_json::Value> = d
        .files
        .unwrap_or_default()
        .into_iter()
        .enumerate()
        .map(|(i, f)| {
            serde_json::json!({
                "index": i, "name": f.name,
                "length": f.length, "included": f.included,
            })
        })
        .collect();
    serde_json::to_string(&files).map_err(|e| e.to_string())
}

/// Peers vivos con nombre de cliente y bytes transferidos.
pub fn torrent_peers(id: u32) -> Result<String, String> {
    let a = super::api()?;
    let snap = a
        .api_peer_stats(super::idx(id)?, PeerStatsFilter::default())
        .map_err(|e| e.to_string())?;
    let peers: Vec<serde_json::Value> = snap
        .peers
        .into_iter()
        .map(|(addr, p)| {
            serde_json::json!({
                "addr": addr, "client": p.client_name,
                "state": p.state.to_string(),
                "downloaded": p.counters.fetched_bytes,
                "uploaded": p.counters.uploaded_bytes,
            })
        })
        .collect();
    serde_json::to_string(&peers).map_err(|e| e.to_string())
}
