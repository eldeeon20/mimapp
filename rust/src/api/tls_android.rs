// Vacío a propósito: con el fork de rustls-platform-verifier (fallback
// WebPKI sin JNI, ver [patch.crates-io] en Cargo.toml) NO hace falta
// init en Android, igual que en Gtool. Se deja el módulo para no
// romper el `pub mod` si se quiere re-agregar un init más adelante.
