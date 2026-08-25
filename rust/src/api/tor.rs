/// Tor embebido vía arti: cliente completo en el dispositivo que expone un
/// proxy SOCKS5 en localhost. Cualquier HttpClient de la app (o socket crudo)
/// puede salir por ahí, incluyendo páginas comunes, descargas de CDN y
/// git smart-http, además de servicios .onion.
///
/// Porte del plugin Foundation-Devices/tor (MIT), adaptado:
/// - TokioRustlsRuntime en vez de TokioNativeTlsRuntime (cero OpenSSL;
///   reutiliza el rustls+ring que ya trae la app).
/// - Estado en estáticos del crate (patrón needle/ipfs) en vez de handles
///   cruzando el FFI.
/// - Errores como String legible (convención ok/error del proyecto).
use std::sync::{Arc, Mutex, OnceLock};

use arti::proxy;
use arti_client::config::CfgPath;
use arti_client::{DormantMode, TorClient, TorClientConfig};
use tokio::runtime::{Builder, Runtime};
use tokio::task::JoinHandle;
use tor_config::Listen;
// OJO: el tipo vive en el módulo tokio (no "rustls"); la feature rustls de
// tor-rtcompat es la que hace que este runtime use TLS puro Rust.
use tor_rtcompat::tokio::TokioRustlsRuntime;
use tor_rtcompat::ToplevelBlockOn;

type Client = Arc<TorClient<TokioRustlsRuntime>>;

static CLIENT: Mutex<Option<Client>> = Mutex::new(None);
static PROXY: Mutex<Option<JoinHandle<anyhow::Result<()>>>> = Mutex::new(None);
static PORT: Mutex<u16> = Mutex::new(0);

fn runtime() -> &'static Result<Runtime, String> {
    static RT: OnceLock<Result<Runtime, String>> = OnceLock::new();
    RT.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .build()
            .map_err(|e| format!("runtime tokio: {e}"))
    })
}

fn port_now() -> u16 {
    match PORT.lock() {
        Ok(g) => *g,
        Err(_) => 0,
    }
}

fn set_port(p: u16) {
    if let Ok(mut g) = PORT.lock() {
        *g = p;
    }
}

#[flutter_rust_bridge::frb]
pub fn tor_is_running() -> bool {
    // El cliente existe Y la tarea del proxy sigue viva. Si algo mató la
    // tarea por fuera (Android en segundo plano, pánico), acá nos enteramos:
    // is_finished() true = la tarea ya terminó aunque no llamemos tor_stop().
    let client_ok = matches!(CLIENT.lock(), Ok(g) if g.is_some());
    let proxy_ok = match PROXY.lock() {
        Ok(g) => g.as_ref().map(|h| !h.is_finished()).unwrap_or(false),
        Err(_) => false,
    };
    client_ok && proxy_ok
}

/// Puerto SOCKS5 activo, o None si Tor está apagado.
///
/// FIX: antes era `*PORT.lock().unwrap_or(&mut 0)`, que no compila: lock()
/// devuelve Result<MutexGuard<u16>, PoisonError<_>>, así que unwrap_or
/// esperaría un MutexGuard (no un `&mut u16`), y además fabricar un guard
/// temporario para descartarlo es imposible por diseño. El match tipa bien,
/// lee el valor solo con el candado sano y cae a 0 si el mutex quedó
/// envenenado: función infalible, sin unwrap() que pueda paniquear.
#[flutter_rust_bridge::frb]
pub fn tor_socks_port() -> Option<u16> {
    let p = port_now();
    if tor_is_running() && p != 0 {
        Some(p)
    } else {
        None
    }
}

/// Arranca el cliente Tor y el proxy SOCKS5 local. Bloquea varios segundos
/// mientras bootstrapea (llamar desde un isolate/future de UI aparte).
#[flutter_rust_bridge::frb]
pub fn tor_start(socks_port: u16, state_dir: String, cache_dir: String) -> Result<String, String> {
    if tor_is_running() {
        return Err("Tor ya está corriendo".into());
    }

    // Los FDs por defecto de Android son bajos y arti abre varios sockets.
    #[cfg(not(target_os = "windows"))]
    {
        let _ = rlimit::increase_nofile_limit(4096);
    }

    let rt = TokioRustlsRuntime::create().map_err(|e| format!("runtime TLS: {e}"))?;

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

    let client = rt
        .block_on(async {
            TorClient::with_runtime(rt.clone())
                .config(cfg)
                .create_bootstrapped()
                .await
        })
        .map_err(|e| format!("bootstrap falló: {e}"))?;
    let client: Client = Arc::new(client);

    // Proxy SOCKS5 en localhost:puerto, tarea propia del runtime global.
    let handle = {
        let rt_inner = runtime().map_err(|e| e.clone())?;
        let c = client.clone();
        rt_inner.spawn(proxy::run_proxy(
            client.runtime().clone(),
            (*c).clone(),
            Listen::new_localhost(socks_port),
            None,
        ))
    };

    if let Ok(mut g) = PROXY.lock() {
        *g = Some(handle);
    }
    if let Ok(mut g) = CLIENT.lock() {
        *g = Some(client);
    }
    set_port(socks_port);
    Ok(format!("Tor listo · SOCKS5 en 127.0.0.1:{socks_port}"))
}

/// Corta el proxy y suelta el cliente. Idempotente.
#[flutter_rust_bridge::frb]
pub fn tor_stop() -> Result<(), String> {
    if let Ok(mut g) = PROXY.lock() {
        if let Some(h) = g.take() {
            h.abort();
        }
    }
    if let Ok(mut g) = CLIENT.lock() {
        *g = None;
    }
    set_port(0);
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

// ------------------------------------------------- HTTP por el túnel (Rust)

fn socks_url() -> Option<String> {
    let p = port_now();
    if tor_is_running() && p != 0 {
        // socks5h: el DNS TAMBIÉN resuelve dentro del circuito, así que
        // funcionan dominios comunes y direcciones .onion desde Rust.
        Some(format!("socks5h://127.0.0.1:{p}"))
    } else {
        None
    }
}

/// URL del proxy para que CUALQUIER cliente Rust de la app salga por Tor:
/// `reqwest::Proxy::all(tor_proxy_url())`. None si Tor está apagado.
/// Con esto, git smart-http / CDNs / APIs pueden tunelar sin cambiar código:
/// basta armar el cliente con ese proxy.
#[flutter_rust_bridge::frb]
pub fn tor_proxy_url() -> Option<String> {
    socks_url()
}

fn tor_http_client() -> Result<reqwest::blocking::Client, String> {
    let url = socks_url().ok_or("Tor no está corriendo")?;
    let proxy = reqwest::Proxy::all(&url).map_err(|e| format!("proxy: {e}"))?;
    reqwest::blocking::Client::builder()
        .proxy(proxy)
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .map_err(|e| format!("cliente HTTP: {e}"))
}

/// GET por el circuito Tor (CDNs, APIs, git smart-http): devuelve
/// "HTTP <status>\n\n<cuerpo>".
#[flutter_rust_bridge::frb]
pub fn tor_http_get(url: String) -> Result<String, String> {
    let c = tor_http_client()?;
    let r = c
        .get(&url)
        .send()
        .and_then(|r| r.error_for_status())
        .map_err(|e| format!("GET {url}: {e}"))?;
    let status = r.status();
    let body = r.text().map_err(|e| format!("cuerpo: {e}"))?;
    Ok(format!("HTTP {status}\n\n{body}"))
}

/// Descarga streaming a archivo por el circuito; retorna bytes escritos.
/// Útil para modelos/CDN grandes sin cargar todo en memoria. Recomendado
/// siempre con https:// (TLS extremo a extremo sobre el túnel).
#[flutter_rust_bridge::frb]
pub fn tor_download(url: String, dest_path: String) -> Result<u64, String> {
    use std::io::{copy, Write};
    let c = tor_http_client()?;
    let mut r = c
        .get(&url)
        .send()
        .and_then(|r| r.error_for_status())
        .map_err(|e| format!("GET {url}: {e}"))?;
    let mut f = std::fs::File::create(&dest_path)
        .map_err(|e| format!("crear {dest_path}: {e}"))?;
    let n = copy(&mut r, &mut f).map_err(|e| format!("descarga: {e}"))?;
    f.flush().map_err(|e| format!("flush: {e}"))?;
    Ok(n)
}
