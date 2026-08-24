/// Port del Unarc de Gtool (unarc_godot.rs) sin Godot: extracción universal
/// de archives vía unarc-rs. Todo devuelve JSON strings (patrón torrent/).
///
/// Soporta: 7z, ZIP, RAR5, tar/gz/bz2/z, arj, lha, zoo, ha, hyp... y
/// multi-volumen (.7z.001/.002, .zip.001, .z01+.zip) con password opcional.
use std::fs::File;
use std::io::{Read, Seek, Write};
use std::path::{Path, PathBuf};

use unarc_rs::unified::{
    is_supported_archive, ArchiveEntry, ArchiveFormat, ArchiveOptions, UnifiedArchive,
};

/// Opciones de apertura: password solo si no está vacía.
fn opciones(password: &str) -> ArchiveOptions {
    if password.is_empty() {
        ArchiveOptions::new()
    } else {
        ArchiveOptions::new().with_password(password)
    }
}

/// Volúmenes que componen el archive: si [p] es `x.7z.001` / `x.zip.001`
/// junta los hermanos consecutivos; split zip clásico `.z01..zNN + .zip`.
fn volumenes(p: &Path) -> Vec<PathBuf> {
    let s = p.to_string_lossy().to_string();

    // foo.7z.001 / foo.zip.001 → foo.NNN consecutivos desde .001
    if let Some(pos) = s.rfind(".001") {
        let base = &s[..pos];
        let mut out = Vec::new();
        let mut i: u32 = 1;
        loop {
            let cand = format!("{base}.{i:03}");
            if Path::new(&cand).exists() {
                out.push(PathBuf::from(cand));
                i += 1;
            } else {
                break;
            }
        }
        if !out.is_empty() {
            return out;
        }
    }

    // split zip clásico: foo.z01..foo.zNN + foo.zip final
    if s.len() >= 4 && s[s.len() - 4..].to_lowercase() == ".zip" {
        let stem = &s[..s.len() - 4];
        let mut parts: Vec<PathBuf> = Vec::new();
        let mut i: u32 = 1;
        loop {
            let cand = format!("{stem}.z{i:02}");
            if Path::new(&cand).exists() {
                parts.push(PathBuf::from(cand));
                i += 1;
            } else {
                break;
            }
        }
        if !parts.is_empty() {
            parts.push(p.to_path_buf());
            return parts;
        }
    }

    vec![p.to_path_buf()]
}

/// true si los volúmenes corresponden a un split ZIP (no 7z).
fn es_split_zip(vols: &[PathBuf]) -> bool {
    match vols.first() {
        Some(p) => {
            let s = p.to_string_lossy().to_lowercase();
            s.ends_with("z01") || s.contains(".zip.")
        }
        None => false,
    }
}

/// Evita zip-slip: componentes vacíos, "." y ".." fuera; siempre relativa.
fn ruta_segura(base: &Path, nombre: &str) -> Option<PathBuf> {
    let norm = nombre.replace('\\', "/");
    let rel: PathBuf = norm
        .split('/')
        .filter(|c| !c.is_empty() && *c != "." && *c != "..")
        .collect();
    if rel.as_os_str().is_empty() {
        None
    } else {
        Some(base.join(rel))
    }
}

fn es_dir(nombre: &str) -> bool {
    nombre.ends_with('/') || nombre.ends_with('\\')
}

/// Abre single o multi-volumen y corre [f] sobre el archive ya abierto.
/// [f] se pasa por nombre (fn genérica): cada rama infiere su T y así
/// nunca nombramos UnifiedArchive<BufReader<File>> vs <MultiVolumeReader>.
macro_rules! con_archive {
    ($path:expr, $password:expr, $f:path $(, $arg:expr)*) => {{
        let vols = volumenes($path);
        let opts = opciones($password);
        if vols.len() > 1 && es_split_zip(&vols) {
            match ArchiveFormat::open_multi_volume_zip(&vols, opts) {
                Ok(mut a) => $f(&mut a $(, $arg)*),
                Err(e) => Err(format!("multi-volumen zip: {e:?}")),
            }
        } else if vols.len() > 1 {
            match ArchiveFormat::open_multi_volume_7z(&vols, opts) {
                Ok(mut a) => $f(&mut a $(, $arg)*),
                Err(e) => Err(format!("multi-volumen 7z: {e:?}")),
            }
        } else {
            match ArchiveFormat::open_path_with_options($path, opts) {
                Ok(mut a) => $f(&mut a $(, $arg)*),
                Err(e) => Err(format!("abrir {}: {e:?}", $path.display())),
            }
        }
    }};
}

/// Lista de entradas como JSON: [{name,size,isDir,encrypted}].
pub fn unarc_listar(archive_path: String, password: String) -> Result<String, String> {
    let p = Path::new(&archive_path);
    if !p.exists() {
        return Err(format!("no existe: {archive_path}"));
    }
    con_archive!(p, &password, listar)
}

fn listar<T: Read + Seek>(a: &mut UnifiedArchive<T>) -> Result<String, String> {
    let mut out = Vec::new();
    loop {
        match a.next_entry() {
            Ok(Some(entry)) => {
                let name = entry.name().to_string();
                out.push(serde_json::json!({
                    "name": name,
                    "size": entry.original_size(),
                    "isDir": es_dir(&name),
                    "encrypted": entry.is_encrypted(),
                }));
            }
            Ok(None) => break,
            Err(e) => return Err(format!("entrada: {e:?}")),
        }
    }
    serde_json::to_string(&out).map_err(|e| e.to_string())
}

/// Extrae TODO a output_dir. Devuelve JSON {"files":N,"bytes":M,"dir":"..."}.
pub fn unarc_extraer_todo(
    archive_path: String,
    output_dir: String,
    password: String,
) -> Result<String, String> {
    let p = Path::new(&archive_path);
    if !p.exists() {
        return Err(format!("no existe: {archive_path}"));
    }
    let out_dir = PathBuf::from(&output_dir);
    std::fs::create_dir_all(&out_dir)
        .map_err(|e| format!("crear {}: {e:?}", out_dir.display()))?;
    let res = con_archive!(p, &password, extraer_todo, &out_dir, &password)?;
    serde_json::to_string(
        &serde_json::json!({"files": res.0, "bytes": res.1, "dir": output_dir}),
    )
    .map_err(|e| e.to_string())
}

fn extraer_todo<T: Read + Seek>(
    a: &mut UnifiedArchive<T>,
    out_dir: &Path,
    password: &str,
) -> Result<(u32, u64), String> {
    let mut files: u32 = 0;
    let mut bytes: u64 = 0;
    loop {
        match a.next_entry() {
            Ok(Some(entry)) => {
                let name = entry.name().to_string();
                let target = match ruta_segura(out_dir, &name) {
                    Some(t) => t,
                    None => continue,
                };
                if es_dir(&name) {
                    std::fs::create_dir_all(&target)
                        .map_err(|e| format!("dir {}: {e:?}", target.display()))?;
                } else {
                    if let Some(parent) = target.parent() {
                        std::fs::create_dir_all(parent)
                            .map_err(|e| format!("padre {}: {e:?}", parent.display()))?;
                    }
                    let mut f = File::create(&target)
                        .map_err(|e| format!("crear {}: {e:?}", target.display()))?;
                    bytes += leer_a(a, &entry, &mut f, password)?;
                    files += 1;
                }
            }
            Ok(None) => break,
            Err(e) => return Err(format!("entrada: {e:?}")),
        }
    }
    Ok((files, bytes))
}

/// Lectura streaming con password; si read_to_with_options falla con password
/// (bug documentado en DIAGNOSTICO_MULTI_VOLUMEN.md), cae a memoria + write.
fn leer_a<T: Read + Seek, W: Write>(
    a: &mut UnifiedArchive<T>,
    entry: &ArchiveEntry,
    out: &mut W,
    password: &str,
) -> Result<u64, String> {
    if password.is_empty() {
        return a.read_to(entry, out).map_err(|e| format!("{e:?}"));
    }
    let opts = opciones(password);
    match a.read_to_with_options(entry, out, &opts) {
        Ok(n) => Ok(n),
        Err(_) => {
            let data = a
                .read_with_options(entry, &opts)
                .map_err(|e| format!("{e:?}"))?;
            out.write_all(&data).map_err(|e| e.to_string())?;
            Ok(data.len() as u64)
        }
    }
}

/// Extrae UNA entrada a dest_path (archivo destino completo).
/// Devuelve JSON {"bytes":N,"dest":"..."}.
pub fn unarc_extraer_entrada(
    archive_path: String,
    entry_name: String,
    dest_path: String,
    password: String,
) -> Result<String, String> {
    let p = Path::new(&archive_path);
    if !p.exists() {
        return Err(format!("no existe: {archive_path}"));
    }
    let dest = PathBuf::from(&dest_path);
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("crear {}: {e:?}", parent.display()))?;
    }
    let bytes = con_archive!(p, &password, extraer_una, &entry_name, &dest, &password)?;
    serde_json::to_string(&serde_json::json!({"bytes": bytes, "dest": dest_path}))
        .map_err(|e| e.to_string())
}

fn extraer_una<T: Read + Seek>(
    a: &mut UnifiedArchive<T>,
    entry_name: &str,
    dest: &Path,
    password: &str,
) -> Result<u64, String> {
    loop {
        match a.next_entry() {
            Ok(Some(entry)) => {
                if entry.name() == entry_name {
                    let mut f = File::create(dest)
                        .map_err(|e| format!("crear {}: {e:?}", dest.display()))?;
                    return leer_a(a, &entry, &mut f, password);
                }
            }
            Ok(None) => return Err(format!("entrada no encontrada: {entry_name}")),
            Err(e) => return Err(format!("entrada: {e:?}")),
        }
    }
}

/// Lee una entrada a memoria para preview, cortada a max_bytes.
pub fn unarc_leer_entrada(
    archive_path: String,
    entry_name: String,
    password: String,
    max_bytes: u32,
) -> Result<Vec<u8>, String> {
    let p = Path::new(&archive_path);
    if !p.exists() {
        return Err(format!("no existe: {archive_path}"));
    }
    con_archive!(p, &password, leer, &entry_name, &password, max_bytes)
}

fn leer<T: Read + Seek>(
    a: &mut UnifiedArchive<T>,
    entry_name: &str,
    password: &str,
    max_bytes: u32,
) -> Result<Vec<u8>, String> {
    loop {
        match a.next_entry() {
            Ok(Some(entry)) => {
                if entry.name() == entry_name {
                    let mut data = if password.is_empty() {
                        a.read(&entry).map_err(|e| format!("{e:?}"))?
                    } else {
                        let opts = opciones(password);
                        a.read_with_options(&entry, &opts)
                            .map_err(|e| format!("{e:?}"))?
                    };
                    data.truncate(max_bytes as usize);
                    return Ok(data);
                }
            }
            Ok(None) => return Err(format!("entrada no encontrada: {entry_name}")),
            Err(e) => return Err(format!("entrada: {e:?}")),
        }
    }
}

/// true si alguna entrada pide password (o no se pudo abrir sin ella),
/// igual que is_archive_encrypted de Gtool.
pub fn unarc_encriptado(archive_path: String) -> bool {
    let p = Path::new(&archive_path);
    if !p.exists() {
        return false;
    }
    con_archive!(p, "", encriptado).unwrap_or(true)
}

fn encriptado<T: Read + Seek>(a: &mut UnifiedArchive<T>) -> Result<bool, String> {
    loop {
        match a.next_entry() {
            Ok(Some(entry)) => {
                if entry.is_encrypted() {
                    return Ok(true);
                }
            }
            Ok(None) => break,
            Err(e) => return Err(format!("entrada: {e:?}")),
        }
    }
    Ok(false)
}

/// true si la extensión figura entre las soportadas por unarc-rs.
pub fn unarc_soportado(archive_path: String) -> bool {
    is_supported_archive(Path::new(&archive_path))
}

/// Nombre legible del formato detectado por extensión ('' si desconocido).
pub fn unarc_formato(archive_path: String) -> Result<String, String> {
    Ok(ArchiveFormat::from_path(Path::new(&archive_path))
        .map(|f| f.name().to_string())
        .unwrap_or_default())
}
