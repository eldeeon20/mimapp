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

// ------------------------------------------------- proxy CONNECT local

/// Proxy HTTP CONNECT en 127.0.0.1:puerto aleatorio que tuneliza por el
/// circuito Tor. El WebView lo usa con ProxyOverride: el navegar normal
/// pasa a salir por Tor en vez de directo. Solo loopback; sin auth.
static PROXY_PARAR: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);
static PROXY_PUERTO: std::sync::atomic::AtomicU16 =
    std::sync::atomic::AtomicU16::new(0);

/// "127.0.0.1:PUERTO" si el proxy está arriba, "" si no.
#[flutter_rust_bridge::frb]
pub fn tor_proxy_puerto() -> String {
    let p = PROXY_PUERTO.load(std::sync::atomic::Ordering::Relaxed);
    if p == 0 {
        String::new()
    } else {
        format!("127.0.0.1:{p}")
    }
}

/// Levanta el proxy (requiere Tor corriendo). Idempotente: si ya está,
/// devuelve el mismo host:puerto.
#[flutter_rust_bridge::frb]
pub fn tor_proxy_start() -> Result<String, String> {
    {
        let g = CLIENT.lock().map_err(|_| "mutex cliente")?;
        if g.is_none() {
            return Err("Tor no está corriendo: arrancalo primero".into());
        }
    }
    if PROXY_PUERTO.load(std::sync::atomic::Ordering::Relaxed) != 0 {
        return Ok(tor_proxy_puerto());
    }
    let listener = std::net::TcpListener::bind("127.0.0.1:0")
        .map_err(|e| format!("proxy bind: {e}"))?;
    listener
        .set_nonblocking(true)
        .map_err(|e| format!("proxy nonblock: {e}"))?;
    let puerto = listener
        .local_addr()
        .map_err(|e| format!("proxy addr: {e}"))?
        .port();
    PROXY_PARAR.store(false, std::sync::atomic::Ordering::Relaxed);
    PROXY_PUERTO.store(puerto, std::sync::atomic::Ordering::Relaxed);
    std::thread::Builder::new()
        .name("tor-proxy".into())
        .spawn(move || {
            while !PROXY_PARAR.load(std::sync::atomic::Ordering::Relaxed) {
                match listener.accept() {
                    Ok((s, _)) => {
                        std::thread::Builder::new()
                            .name("tor-proxy-conn".into())
                            .spawn(move || atender_proxy(s))
                            .ok();
                    }
                    Err(ref e)
                        if e.kind() == std::io::ErrorKind::WouldBlock =>
                    {
                        std::thread::sleep(std::time::Duration::from_millis(100))
                    }
                    Err(_) => break,
                }
            }
            PROXY_PUERTO.store(0, std::sync::atomic::Ordering::Relaxed);
        })
        .map_err(|e| format!("hilo proxy: {e}"))?;
    Ok(format!("127.0.0.1:{puerto}"))
}

/// Baja el proxy. Idempotente (el cliente Tor sigue corriendo).
#[flutter_rust_bridge::frb]
pub fn tor_proxy_stop() -> Result<(), String> {
    PROXY_PARAR.store(true, std::sync::atomic::Ordering::Relaxed);
    PROXY_PUERTO.store(0, std::sync::atomic::Ordering::Relaxed);
    Ok(())
}

/// Una conexión del WebView: CONNECT host:puerto o petición absoluta
/// (GET http://host/...). Todo lo demás → 405 y cierre.
fn atender_proxy(s: std::net::TcpStream) {
    use std::io::{Read, Write};
    let _ = s.set_read_timeout(Some(std::time::Duration::from_secs(15)));
    // Leer cabecera completa (\r\n\r\n, máx 32KB) en bloqueante.
    let mut head: Vec<u8> = Vec::new();
    let mut buf = [0u8; 4096];
    let mut sock = s;
    let _ = sock.set_nonblocking(false);
    loop {
        match sock.read(&mut buf) {
            Ok(0) => return,
            Ok(n) => {
                head.extend_from_slice(&buf[..n]);
                if head.len() > 32768 {
                    return;
                }
                if head.windows(4).any(|w| w == b"\r\n\r\n") {
                    break;
                }
            }
            Err(_) => return,
        }
    }
    let texto = String::from_utf8_lossy(&head);
    let primera = texto.lines().next().unwrap_or("");
    let mut partes = primera.split_whitespace();
    let metodo = partes.next().unwrap_or("");
    let objetivo = partes.next().unwrap_or("");
    // Destino + bytes ya leídos a reenviar (forma absoluta).
    let (destino, preenvio): (String, Vec<u8>) = if metodo == "CONNECT" {
        (objetivo.to_string(), Vec::new())
    } else if objetivo.starts_with("http://") || objetivo.starts_with("https://") {
        let sin_esquema = objetivo
            .split_once("://")
            .map(|(_, r)| r)
            .unwrap_or(objetivo);
        let host = sin_esquema.split('/').next().unwrap_or("");
        let es_https = objetivo.starts_with("https://");
        let d = if host.contains(':') {
            host.to_string()
        } else if es_https {
            format!("{host}:443")
        } else {
            format!("{host}:80")
        };
        (d, head.clone())
    } else {
        let _ = sock.write_all(b"HTTP/1.1 405 Solo proxy\r\nContent-Length: 0\r\n\r\n");
        return;
    };
    let (host, puerto) = match destino.rsplit_once(':') {
        Some((h, p)) => (h.to_string(), p.parse::<u16>().unwrap_or(443)),
        None => (destino.clone(), 443),
    };
    if host.is_empty() {
        return;
    }
    // Clonar el cliente arti para este hilo.
    let cliente: Client = match CLIENT.lock() {
        Ok(g) => match g.as_ref() {
            Some(c) => c.clone(),
            None => return,
        },
        Err(_) => return,
    };
    // Conectar por el circuito y tunelizar.
    let mut tor_stream = match tor_rt().block_on(cliente.connect((host.clone(), puerto))) {
        Ok(s) => s,
        Err(_) => {
            let _ = sock.write_all(b"HTTP/1.1 502 Tor no conecta\r\nContent-Length: 0\r\n\r\n");
            return;
        }
    };
    if metodo == "CONNECT" {
        if sock.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n").is_err() {
            return;
        }
    } else {
        // Forma absoluta: el TLS lo negocia el WebView contra el destino;
        // acá solo reenviamos los bytes ya leídos y tuneleamos.
        use tokio::io::AsyncWriteExt as _;
        if tor_rt()
            .block_on(async { tor_stream.write_all(&preenvio).await })
            .is_err()
        {
            return;
        }
    }
    let _ = sock.set_nonblocking(true);
    let mut tcp = match tokio::net::TcpStream::from_std(sock) {
        Ok(t) => t,
        Err(_) => return,
    };
    let _ = tor_rt().block_on(async {
        use tokio::io::AsyncWriteExt as _;
        let r = tokio::io::copy_bidirectional(&mut tcp, &mut tor_stream).await;
        let _ = tor_stream.shutdown().await;
        r
    });
}
