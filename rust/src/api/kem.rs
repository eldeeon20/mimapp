/// KEM post-cuántico (libcrux) — portado de Gtool `kem_godot.rs` sin Godot.
///
/// Algoritmos: X25519, Secp256r1, ML-KEM 512/768/1024 (FIPS 203) e
/// híbridos X25519+ML-KEM768 / X-Wing.
use libcrux_kem::{self, Algorithm, Ct, PrivateKey, PublicKey};

fn parse_algorithm(name: &str) -> Option<Algorithm> {
    match name {
        "X25519" => Some(Algorithm::X25519),
        "Secp256r1" => Some(Algorithm::Secp256r1),
        "MlKem512" => Some(Algorithm::MlKem512),
        "MlKem768" => Some(Algorithm::MlKem768),
        "MlKem1024" => Some(Algorithm::MlKem1024),
        "X25519MlKem768Draft00" => Some(Algorithm::X25519MlKem768Draft00),
        "XWingKemDraft06" => Some(Algorithm::XWingKemDraft06),
        _ => None,
    }
}

/// Lista de algoritmos disponibles (para llenar un dropdown).
#[flutter_rust_bridge::frb]
pub fn kem_list_algorithms() -> Vec<String> {
    vec![
        "X25519".into(),
        "Secp256r1".into(),
        "MlKem512".into(),
        "MlKem768".into(),
        "MlKem1024".into(),
        "X25519MlKem768Draft00".into(),
        "XWingKemDraft06".into(),
    ]
}

/// Par de claves KEM codificadas.
#[flutter_rust_bridge::frb]
pub struct KemKeyPair {
    pub private_key: Vec<u8>,
    pub public_key: Vec<u8>,
}

/// Resultado de encapsulación.
#[flutter_rust_bridge::frb]
pub struct KemEncapsulation {
    pub shared_secret: Vec<u8>,
    pub ciphertext: Vec<u8>,
}

/// Genera par de claves para el algoritmo dado.
#[flutter_rust_bridge::frb]
pub fn kem_key_gen(algorithm: String) -> Result<KemKeyPair, String> {
    let alg = parse_algorithm(&algorithm)
        .ok_or_else(|| format!("algoritmo desconocido: {algorithm}"))?;

    use rand::rngs::OsRng;
    use rand::TryRngCore;
    let mut os_rng = OsRng;
    let mut rng = os_rng.unwrap_mut();

    let (sk, pk) =
        libcrux_kem::key_gen(alg, &mut rng).map_err(|e| format!("key_gen error: {e:?}"))?;
    Ok(KemKeyPair {
        private_key: sk.encode(),
        public_key: pk.encode(),
    })
}

/// Encapsula contra una clave pública: shared secret + ciphertext.
#[flutter_rust_bridge::frb]
pub fn kem_encapsulate(
    algorithm: String,
    public_key: Vec<u8>,
) -> Result<KemEncapsulation, String> {
    let alg = parse_algorithm(&algorithm)
        .ok_or_else(|| format!("algoritmo desconocido: {algorithm}"))?;
    let pk = PublicKey::decode(alg, &public_key)
        .map_err(|e| format!("error decodificando public key: {e:?}"))?;

    use rand::rngs::OsRng;
    use rand::TryRngCore;
    let mut os_rng = OsRng;
    let mut rng = os_rng.unwrap_mut();

    let (ss, ct) = pk.encapsulate(&mut rng).map_err(|e| format!("encapsulate error: {e:?}"))?;
    Ok(KemEncapsulation {
        shared_secret: ss.encode(),
        ciphertext: ct.encode(),
    })
}

/// Desencapsula con la clave privada → mismo shared secret.
#[flutter_rust_bridge::frb]
pub fn kem_decapsulate(
    algorithm: String,
    ciphertext: Vec<u8>,
    private_key: Vec<u8>,
) -> Result<Vec<u8>, String> {
    let alg = parse_algorithm(&algorithm)
        .ok_or_else(|| format!("algoritmo desconocido: {algorithm}"))?;
    let ct =
        Ct::decode(alg, &ciphertext).map_err(|e| format!("error decodificando ciphertext: {e:?}"))?;
    let sk = PrivateKey::decode(alg, &private_key)
        .map_err(|e| format!("error decodificando private key: {e:?}"))?;
    let ss = ct.decapsulate(&sk).map_err(|e| format!("decapsulate error: {e:?}"))?;
    Ok(ss.encode())
}
