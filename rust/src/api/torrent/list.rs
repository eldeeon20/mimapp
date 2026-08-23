use librqbit::api::ApiTorrentListOpts;

use super::TorrentItem;

/// Lista completa con stats (equivalente a torrents_list?withStats=true).
pub fn torrent_list() -> Result<Vec<TorrentItem>, String> {
    let a = super::api()?;
    let list = a.api_torrent_list_ext(ApiTorrentListOpts { with_stats: true });
    Ok(list
        .torrents
        .into_iter()
        .map(|t| {
            let s = t.stats.as_ref();
            let state = s.map(|st| st.state.to_string()).unwrap_or_default();
            let down = s
                .and_then(|st| st.live.as_ref())
                .map(|l| l.download_speed.as_bytes())
                .unwrap_or(0);
            let up = s
                .and_then(|st| st.live.as_ref())
                .map(|l| l.upload_speed.as_bytes())
                .unwrap_or(0);
            TorrentItem {
                id: t.id.map(|i| i as u32),
                info_hash: t.info_hash.clone(),
                name: t.name.unwrap_or_else(|| t.info_hash.clone()),
                state,
                progress_bytes: s.map(|st| st.progress_bytes).unwrap_or(0),
                total_bytes: s.map(|st| st.total_bytes).unwrap_or(0),
                uploaded_bytes: s.map(|st| st.uploaded_bytes).unwrap_or(0),
                finished: s.map(|st| st.finished).unwrap_or(false),
                error: s.and_then(|st| st.error.clone()),
                down_bps: down,
                up_bps: up,
            }
        })
        .collect())
}
