/// Archivo del torrent para selección múltiple (update_only_files).
pub struct TorrentFile {
    pub index: usize,
    pub name: String,
    pub length: u64,
    pub included: bool,
}

/// Peer vivo con contadores (peer_stats?state=live).
pub struct TorrentPeer {
    pub addr: String,
    pub client: Option<String>,
    /// estado textual del peer
    pub state: String,
    pub downloaded: u64,
    pub uploaded: u64,
}

/// Archivos con su estado de inclusión actual (torrent_details).
pub fn torrent_files(id: u32) -> Result<Vec<TorrentFile>, String> {
    let a = super::api()?;
    let d = a
        .api_torrent_details(super::idx(id)?)
        .map_err(|e| e.to_string())?;
    Ok(d.files
        .unwrap_or_default()
        .into_iter()
        .enumerate()
        .map(|(i, f)| TorrentFile {
            index: i,
            name: f.name,
            length: f.length,
            included: f.included,
        })
        .collect())
}

/// Peers vivos con nombre de cliente y bytes transferidos.
pub fn torrent_peers(id: u32) -> Result<Vec<TorrentPeer>, String> {
    let a = super::api()?;
    let snap = a
        .api_peer_stats(
            super::idx(id)?,
            librqbit::torrent_state::live::peer::stats::snapshot::PeerStatsFilter::default(),
        )
        .map_err(|e| e.to_string())?;
    Ok(snap
        .peers
        .into_iter()
        .map(|(addr, p)| TorrentPeer {
            addr,
            client: p.client_name,
            state: p.state.to_string(),
            downloaded: p.counters.fetched_bytes,
            uploaded: p.counters.uploaded_bytes,
        })
        .collect())
}
