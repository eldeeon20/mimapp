//! Init JNI del verificador TLS de plataforma en Android.
//!
//! hf-hub 1.x → reqwest 0.13 verifica certificados con
//! rustls-platform-verifier, que en Android EXIGE inicializarse con el
//! Context antes del primer uso. Sin esto, el primer upload a HF paniquea:
//! "Expect rustls-platform-verifier to be initialized".
//! (El parche de simple.rs instala el proveedor cripto ring: eso es otra
//! cosa y sigue igual.)
//!
//! Kotlin lo llama una vez al arrancar (MainActivity.onCreate):
//! `TlsInit` no hace falta: el método vive en MainActivity como
//! `private external fun initRustTls(ctx: Context)`.

// En desktop no hay nada que inicializar (módulo vacío a propósito:
// que compile igual en todos los targets).
#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn Java_com_example_pr_1app_MainActivity_initRustTls(
    mut env: jni::Env<'_>,
    _thiz: jni::objects::JObject<'_>,
    context: jni::objects::JObject<'_>,
) {
    // Idempotente (OnceCell): si ya se inicializó, no hace nada.
    // Se ignora el error a propósito: sin JVM no hay TLS de plataforma
    // y el upload fallará con su propio mensaje en vez de crashear.
    let _ = rustls_platform_verifier::android::init_with_env(&mut env, context);
}
