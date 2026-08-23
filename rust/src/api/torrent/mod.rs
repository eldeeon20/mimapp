// pub: frb_generated referencia funciones cruzando módulos por ruta.
pub mod actions;
pub mod add;
pub mod detail;
pub mod list;
pub mod session;

pub use actions::{torrent_action, torrent_set_only_files};
pub use add::{torrent_add_bytes, torrent_add_url};
pub use detail::{torrent_files, torrent_peers};
pub use list::torrent_list;
pub use session::{torrent_session_running, torrent_session_start};

use std::num::NonZeroU32;
use std::sync::{Arc, OnceLock};

use librqbit::limits::LimitsConfig;
use librqbit::Api;

/// Puente rqbit Tauri→Flutter (Camino B: FFI directa vía FRB, sin HTTP).
/// La sesión vive en el proceso: el servicio en primer plano la mantiene
/// viva al minimizar o salir de la app.
static API: OnceLock<Arc<Api>> = OnceLock::new();

pub(super) fn api() -> Result<Arc<Api>, String> {
    API.get()
        .cloned()
        .ok_or_else(|| "sesión no iniciada".to_string())
}

/// id numérico o info-hash hex de 40 → handle.
pub(super) fn idx(id: u32) -> Result<librqbit::api::TorrentIdOrHash, String> {
    librqbit::api::TorrentIdOrHash::parse(&id.to_string())
        .map_err(|e| format!("id inválido: {e:#}"))
}

pub(super) fn bps(v: Option<u32>) -> Option<NonZeroU32> {
    v.and_then(NonZeroU32::new)
}

/// Límites en bytes/s (None = ilimitado). Sirve para global y por torrent.
pub(super) fn limits(down_bps: Option<u32>, up_bps: Option<u32>) -> LimitsConfig {
    LimitsConfig {
        upload_bps: bps(up_bps),
        download_bps: bps(down_bps),
    }
}
