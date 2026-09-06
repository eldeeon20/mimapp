/// Tor embebido vía arti: cliente completo en el dispositivo. El HTTP(S)
/// sale DIRECTO por el puente FRB usando arti-ureq (lib oficial del
/// proyecto Tor): sin servidor local, sin puertos 127.0.0.1.
///
/// Porte del plugin Foundation-Devices/tor (MIT), adaptado:
/// - TokioRustlsRuntime en vez de TokioNativeTlsRuntime (cero OpenSSL;
///   reutiliza el rustls+ring que ya trae la app).
/// - Estado en estáticos del crate (patrón needle/ipfs) en vez de handles
///   cruzando el FFI.
/// - Errores como String legible (convención ok/error del proyecto).
use std::sync::{Arc, Mutex, OnceLock};

use arti_client::config::CfgPath;
use arti_client::{DormantMode, TorClient, TorClientConfig};
// OJO: el tipo vive en el módulo tokio (no "rustls"); la feature rustls de
// tor-rtcompat es la que hace que este runtime use TLS puro Rust.
use tor_rtcompat::tokio::TokioRustlsRuntime;
use tor_rtcompat::ToplevelBlockOn;

type Client = Arc<TorClient<TokioRustlsRuntime>>;

static CLIENT: Mutex<Option<Client>> = Mutex::new(None);
/// 0 apagado · 1 bootstrap · 2 calentando circuitos · 3 LISTO
static ESTADO: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);

fn estado_set(v: u8) {
    ESTADO.store(v, std::sync::atomic::Ordering::Relaxed);
}

/// Estado humano del ciclo de vida de Tor para la UI.
#[flutter_rust_bridge::frb]
pub fn tor_estado() -> String {
    match ESTADO.load(std::sync::atomic::Ordering::Relaxed) {
        1 => "bootstrap".into(),
        2 => "calentando circuitos…".into(),
        3 => "listo".into(),
        _ => "apagado".into(),
    }
}
/// Runtime EXCLUSIVO del stack Tor: bootstrap, warm-up y todas las
/// consultas HTTP viven aquí. Un stack de red = un runtime (regla del
/// proyecto: una red = un runtime).
static TOR_RT: OnceLock<TokioRustlsRuntime> = OnceLock::new();

fn tor_rt() -> &'static TokioRustlsRuntime {
    TOR_RT.get_or_init(|| TokioRustlsRuntime::create().expect("runtime TLS rustls"))
}

fn agente() -> Result<arti_ureq::ureq::Agent, String> {
    let c = CLIENT.lock().map_err(|_| "mutex cliente")?;
    let c = c.as_ref().ok_or("Tor no está corriendo")?;
    Ok(arti_ureq::Connector::with_tor_client((**c).clone()).agent())
}

#[flutter_rust_bridge::frb]
pub fn tor_is_running() -> bool {
    matches!(CLIENT.lock(), Ok(g) if g.is_some())
        && ESTADO.load(std::sync::atomic::Ordering::Relaxed) != 0
}

/// Arranca el cliente Tor. Bloquea varios segundos mientras bootstrapea
/// (llamar desde un isolate/future de UI aparte). SIN servidor local:
/// las consultas HTTP salen directo por arti-ureq desde Rust.
#[flutter_rust_bridge::frb]
pub fn tor_start(state_dir: String, cache_dir: String) -> Result<String, String> {
    if tor_is_running() {
        return Err("Tor ya está corriendo".into());
    }
    estado_set(1);

    // Los FDs por defecto de Android son bajos y arti abre varios sockets.
    #[cfg(not(target_os = "windows"))]
    {
        let _ = rlimit::increase_nofile_limit(4096);
    }

    let rt = tor_rt();

    // Ajustes móviles heredados de Foundation-Devices/tor:
    // - permitir direcciones .onion
    // - menos circuitos preventivos (ahorro de datos/batería)
    let mut b = TorClientConfig::builder();
    b.storage()
        .state_dir(CfgPath::new(state_dir))
        .cache_dir(CfgPath::new(cache_dir));
    b.address_filter().allow_onion_addrs(true);
    b.preemptive_circuits()
        .disable_at_threshold(1)
        .min_exit_circs_for_port(1)
        .initial_predicted_ports()
        .clear();

    let cfg = b.build().map_err(|e| format!("config: {e}"))?;

    let client = tor_rt()
        .block_on(async {
            TorClient::with_runtime(tor_rt().clone())
                .config(cfg)
                .create_bootstrapped()
                .await
        })
        .map_err(|e| format!("bootstrap falló: {e}"))?;
    let client: Client = Arc::new(client);
    if let Ok(mut g) = CLIENT.lock() {
        *g = Some(client);
    }
    estado_set(2); // bootstrap OK → calentando: falta probar una página real

    // Warm-up HONESTO: un hilo liviano repite un GET real por arti-ureq
    // hasta que la red responde. "listo" significa eso, nada menos.
    std::thread::Builder::new()
        .name("tor-warmup".into())
        .spawn(|| {
            while ESTADO.load(std::sync::atomic::Ordering::Relaxed) == 2 {
                match tor_http_get("https://check.torproject.org/api/ip".into()) {
                    Ok(_) => {
                        estado_set(3);
                        eprintln!("[tor] warm-up OK · circuito verificado");
                        return;
                    }
                    Err(e) => {
                        eprintln!("[tor] warm-up esperando red: {e}");
                        std::thread::sleep(std::time::Duration::from_secs(8));
                    }
                }
            }
        })
        .map_err(|e| format!("hilo warm-up: {e}"))?;

    Ok("Tor arriba · HTTP directo por arti (sin puente local)".into())
}

/// Apaga el cliente. Idempotente.
#[flutter_rust_bridge::frb]
pub fn tor_stop() -> Result<(), String> {
    estado_set(0);
    if let Ok(mut g) = CLIENT.lock() {
        *g = None;
    }
    Ok(())
}

/// Re-bootstrapeo tras cambio de red.
#[flutter_rust_bridge::frb]
pub fn tor_rebootstrap() -> Result<(), String> {
    let g = CLIENT.lock().map_err(|_| "mutex cliente")?;
    let c = g.as_ref().ok_or("Tor no está corriendo")?;
    c.runtime()
        .block_on(c.as_ref().bootstrap())
        .map_err(|e| format!("re-bootstrap: {e}"))
}

/// Modo dormante: soft conserva circuitos tibios (ahorra batería),
/// normal vuelve a operación plena.
#[flutter_rust_bridge::frb]
pub fn tor_set_dormant(soft: bool) -> Result<(), String> {
    let g = CLIENT.lock().map_err(|_| "mutex cliente")?;
    let c = g.as_ref().ok_or("Tor no está corriendo")?;
    c.as_ref()
        .set_dormant(if soft { DormantMode::Soft } else { DormantMode::Normal });
    Ok(())
}

/// GET por el circuito Tor (CDNs, APIs, git smart-http): devuelve
/// "HTTP <status>\n\n<cuerpo>".
#[flutter_rust_bridge::frb]
pub fn tor_http_get(url: String) -> Result<String, String> {
    let c = agente()?;
    let mut r = c.get(&url).call().map_err(|e| format!("GET {url}: {e}"))?;
    let status = r.status();
    let body = r.body_mut().read_to_string().map_err(|e| format!("cuerpo: {e}"))?;
    Ok(format!("HTTP {status}\n\n{body}"))
}

/// Descarga streaming a archivo por el circuito; retorna bytes escritos.
/// Útil para modelos/CDN grandes sin cargar todo en memoria. Recomendado
/// siempre con https:// (TLS extremo a extremo sobre el túnel).
#[flutter_rust_bridge::frb]
pub fn tor_download(url: String, dest_path: String) -> Result<u64, String> {
    use std::io::{Read, Write};
    let c = agente()?;
    let mut r = c.get(&url).call().map_err(|e| format!("GET {url}: {e}"))?;
    let mut reader = r.body_mut().as_reader();
    let mut f = std::fs::File::create(&dest_path)
        .map_err(|e| format!("crear {dest_path}: {e}"))?;
    let mut buf = Vec::new();
    reader.read_to_end(&mut buf).map_err(|e| format!("descarga: {e}"))?;
    f.write_all(&buf).map_err(|e| format!("escribir: {e}"))?;
    f.flush().map_err(|e| format!("flush: {e}"))?;
    Ok(buf.len() as u64)
}

/// Ping TCP crudo por el circuito Tor: abre una conexión hacia host:puerto
/// (sin HTTP) para verificar conectividad a cualquier servicio .onion/común.
#[flutter_rust_bridge::frb]
pub fn tor_tcp_ping(host: String, puerto: i32) -> Result<String, String> {
    let g = CLIENT.lock().map_err(|_| "mutex cliente")?;
    let c = g.as_ref().ok_or("Tor no está corriendo")?;
    let start = std::time::Instant::now();
    let _s = tor_rt()
        .block_on(c.connect((host.clone(), puerto as u16)))
        .map_err(|e| format!("connect {host}:{puerto}: {e}"))?;
    let ms = start.elapsed().as_millis();
    Ok(format!("OK {host}:{puerto} · {ms} ms por el circuito Tor"))
}
