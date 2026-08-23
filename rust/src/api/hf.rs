/// Cliente HuggingFace — portado de Gtool `hf_godot.rs` sin Godot.
///
/// Subir/bajar archivos, crear/borrar repos, buscar modelos, rangos HTTP
/// para leer porciones de archivos grandes (ej. checkpoints).
use std::path::PathBuf;

use hf_hub::{HFClientBuilder, HFClientSync};

#[flutter_rust_bridge::frb(opaque)]
pub struct HfClient {
    client: HFClientSync,
}

enum Rt {
    Model,
    Dataset,
    Space,
}

fn parse_rt(repo_type: &str) -> Rt {
    match repo_type.to_lowercase().as_str() {
        "dataset" => Rt::Dataset,
        "space" => Rt::Space,
        _ => Rt::Model,
    }
}

fn split_repo(repo_id: &str) -> (String, String) {
    let parts: Vec<&str> = repo_id.split('/').collect();
    if parts.len() == 2 {
        (parts[0].to_string(), parts[1].to_string())
    } else {
        (String::new(), repo_id.to_string())
    }
}

impl HfClient {
    /// Token de acceso HF (vacío = anónimo, solo lectura pública).
    pub fn new(token: String) -> Result<HfClient, String> {
        let mut b = HFClientBuilder::new();
        if !token.is_empty() {
            b = b.token(token);
        }
        let client = b.build_sync().map_err(|e| format!("HF client error: {e:?}"))?;
        Ok(HfClient { client })
    }

    fn with_repo<T>(
        &self,
        repo_id: &str,
        repo_type: &str,
        f: impl Fn(&hf_hub::repository::Repository) -> Result<T, hf_hub::RepoError>,
    ) -> Result<T, String> {
        let (ns, name) = split_repo(repo_id);
        let r = match parse_rt(repo_type) {
            Rt::Dataset => self.client.dataset(&ns, &name),
            Rt::Space => self.client.space(&ns, &name),
            Rt::Model => self.client.model(&ns, &name),
        };
        f(&r).map_err(|e| format!("HF op failed: {e:?}"))
    }

    /// Sube un archivo local al repo (requiere token con permiso write).
    pub fn upload_file(
        &self,
        repo_id: String,
        local_file_path: String,
        path_in_repo: String,
        commit_message: String,
        repo_type: String,
    ) -> Result<(), String> {
        let bytes = std::fs::read(&local_file_path)
            .map_err(|e| format!("no se pudo leer {local_file_path}: {e:?}"))?;
        self.with_repo(&repo_id, &repo_type, |r| {
            r.upload_file()
                .source(hf_hub::repository::AddSource::bytes(bytes.clone()))
                .path_in_repo(path_in_repo.clone())
                .commit_message(commit_message.clone())
                .send()
                .map(|_| ())
        })
    }

    /// Descarga un archivo del repo a local_dir; retorna el path final.
    pub fn download_file(
        &self,
        repo_id: String,
        filename: String,
        local_dir: String,
        repo_type: String,
    ) -> Result<String, String> {
        let path = self.with_repo(&repo_id, &repo_type, |r| {
            r.download_file()
                .filename(filename.clone())
                .local_dir(PathBuf::from(local_dir.clone()))
                .send()
        })?;
        Ok(path.to_string_lossy().to_string())
    }

    /// Baja un RANGO de bytes: usar la función libre `hf_download_file_range`.
    /// Borra un archivo del repo.
    pub fn delete_file(
        &self,
        repo_id: String,
        path_in_repo: String,
        repo_type: String,
    ) -> Result<(), String> {
        self.with_repo(&repo_id, &repo_type, |r| {
            r.delete_file()
                .path_in_repo(path_in_repo.clone())
                .send()
                .map(|_| ())
        })
    }

    /// Borra un repositorio entero (peligroso).
    pub fn delete_repository(&self, repo_id: String, repo_type: String) -> Result<(), String> {
        let rt = match parse_rt(&repo_type) {
            Rt::Dataset => hf_hub::RepoType::Dataset,
            Rt::Space => hf_hub::RepoType::Space,
            Rt::Model => hf_hub::RepoType::Model,
        };
        self.client
            .delete_repository()
            .repo_type(rt)
            .repo_id(repo_id.clone())
            .missing_ok(true)
            .send()
            .map_err(|e| format!("delete_repository falló ({repo_id}): {e:?}"))
    }

    /// Crea un repositorio (exist_ok).
    pub fn create_repository(
        &self,
        repo_id: String,
        repo_type: String,
        private: bool,
    ) -> Result<(), String> {
        let rt = match parse_rt(&repo_type) {
            Rt::Dataset => hf_hub::RepoType::Dataset,
            Rt::Space => hf_hub::RepoType::Space,
            Rt::Model => hf_hub::RepoType::Model,
        };
        self.client
            .create_repository()
            .repo_type(rt)
            .repo_id(repo_id.clone())
            .private(private)
            .exist_ok(true)
            .send()
            .map_err(|e| format!("create_repository falló ({repo_id}): {e:?}"))
    }

    /// Busca modelos de un autor → ids ("autor/modelo").
    pub fn search_models(&self, author: String, limit: i64) -> Result<Vec<String>, String> {
        let models = self
            .client
            .list_models()
            .author(author)
            .limit(limit.max(1) as usize)
            .send()
            .map_err(|e| format!("search_models falló: {e:?}"))?;
        Ok(models.into_iter().map(|m| m.id).collect())
    }

    /// ¿Existe el repo?
    pub fn repo_exists(&self, repo_id: String, repo_type: String) -> bool {
        self.with_repo(&repo_id, &repo_type, |r| r.exists().send())
            .unwrap_or(false)
    }

    /// ¿Existe un archivo dentro del repo?
    pub fn file_exists(
        &self,
        repo_id: String,
        filename: String,
        repo_type: String,
    ) -> bool {
        self.with_repo(&repo_id, &repo_type, |r| {
            r.file_exists().filename(filename.clone()).send()
        })
        .unwrap_or(false)
    }

    /// Lista archivos del repo (recursive opcional).
    pub fn list_repo_files(
        &self,
        repo_id: String,
        recursive: bool,
        repo_type: String,
    ) -> Result<Vec<String>, String> {
        let entries = self.with_repo(&repo_id, &repo_type, |r| {
            r.list_tree().recursive(recursive).send()
        })?;
        Ok(entries
            .into_iter()
            .map(|entry| match entry {
                hf_hub::repository::RepoTreeEntry::File { path, .. } => path,
                hf_hub::repository::RepoTreeEntry::Directory { path, .. } => path,
            })
            .collect())
    }
}

/// Baja un RANGO de bytes de un archivo grande (HTTP Range directo).
/// No requiere cliente inicializado; usa el token pasado.
#[flutter_rust_bridge::frb]
pub fn hf_download_file_range(
    repo_id: String,
    filename: String,
    start: i64,
    end: i64,
    token: String,
    repo_type: String,
) -> Result<Vec<u8>, String> {
    range_download(repo_id, filename, start, end, token, repo_type)
}

fn range_download(
    repo_id: String,
    filename: String,
    start: i64,
    end: i64,
    token: String,
    repo_type: String,
) -> Result<Vec<u8>, String> {
    let base_url = match parse_rt(&repo_type) {
        Rt::Dataset => "https://huggingface.co/datasets",
        Rt::Space => "https://huggingface.co/spaces",
        Rt::Model => "https://huggingface.co",
    };
    let url = format!("{}/{}/resolve/main/{}", base_url, repo_id, filename);

    let mut req = reqwest::blocking::Client::builder()
        .user_agent("pr_app-hf/1.0")
        .build()
        .map_err(|e| format!("{e:?}"))?
        .get(&url)
        .header("Range", format!("bytes={}-{}", start, end));
    if !token.is_empty() {
        req = req.header("Authorization", format!("Bearer {}", token));
    }
    let response = req.send().map_err(|e| format!("request failed: {e:?}"))?;
    if !response.status().is_success() {
        return Err(format!("HTTP {} en {}", response.status(), url));
    }
    let data = response.bytes().map_err(|e| format!("read failed: {e:?}"))?;
    Ok(data.to_vec())
}
