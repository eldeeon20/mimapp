use std::net::SocketAddr;
use std::path::PathBuf;

use librqbit::dht::DhtPersistenceConfig;
use librqbit::{
    Api, DhtSessionConfig, ListenerMode, ListenerOptions, Session, SessionOptions,
    SessionPersistenceConfig,
};

use super::{api, limits};

/// Arranca la sesión rqbit. `data_dir` DEBE estar dentro del sandbox de la
/// app. Receta del desktop (`api_from_config`) + fix issue #518:
/// persistencia sesión = CARPETA, DHT Kademlia = ARCHIVO dht.json.
/// UPnP = port forwarding del puerto de escucha. Límites globales bytes/s.
pub async fn torrent_session_start(
    data_dir: String,
    enable_dht: bool,
    enable_upnp: bool,
    down_bps: Option<u32>,
    up_bps: Option<u32>,
) -> Result<String, String> {
    if let Ok(a) = crate::api::torrent::api() {
        return Ok(format!(
            "ya activa ({} torrents)",
            a.api_torrent_list().torrents.len()
        ));
    }
    let dir = PathBuf::from(&data_dir);
    let dl = dir.join("downloads");
    std::fs::create_dir_all(&dl).map_err(|e| e.to_string())?;

    let mut opts = SessionOptions::default();
    opts.persistence = Some(SessionPersistenceConfig::Json {
        folder: Some(dir.clone()),
    });
    opts.dht = if enable_dht {
        Some(DhtSessionConfig {
            persistence: Some(DhtPersistenceConfig {
                config_filename: Some(dir.join("dht.json")),
                ..Default::default()
            }),
            ..Default::default()
        })
    } else {
        None // sin Kademlia
    };
    opts.listen = Some(ListenerOptions {
        mode: ListenerMode::TcpAndUtp,
        listen_addr: "[::]:0".parse::<SocketAddr>().unwrap(),
        enable_upnp_port_forwarding: enable_upnp,
        utp_opts: None,
        announce_port: None,
        ipv4_only: false,
        max_pending_incoming_handshake_checks: 256,
    });
    opts.fastresume = true;
    opts.ratelimits = limits(down_bps, up_bps);

    let session =
        Session::new_with_opts(dl, opts)
            .await
            .map_err(|e| format!("session: {e:#}"))?;
    let a = std::sync::Arc::new(Api::new(session, None));
    super::API.set(a)
        .map_err(|_| "la sesión ya estaba inicializada".to_string())?;
    Ok(format!(
        "sesión lista en {} (dht:{}, upnp:{})",
        dir.display(),
        enable_dht,
        enable_upnp
    ))
}

pub fn torrent_session_running() -> bool {
    api().is_ok()
}
