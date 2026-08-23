use std::collections::HashSet;

/// start | pause | forget | delete (delete borra también los archivos).
pub async fn torrent_action(id: u32, action: String) -> Result<(), String> {
    let a = super::api()?;
    let i = super::idx(id)?;
    match action.as_str() {
        "start" => a.api_torrent_action_start(i).await,
        "pause" => a.api_torrent_action_pause(i).await,
        "forget" => a.api_torrent_action_forget(i).await,
        "delete" => a.api_torrent_action_delete(i).await,
        _ => return Err(format!("acción desconocida: {action}")),
    }
    .map_err(|e| e.to_string())?;
    Ok(())
}

/// Selección múltiple de archivos a descargar (torrent_action_configure).
pub async fn torrent_set_only_files(id: u32, files: Vec<usize>) -> Result<(), String> {
    let a = super::api()?;
    let set: HashSet<usize> = files.into_iter().collect();
    a.api_torrent_action_update_only_files(super::idx(id)?, &set)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}
