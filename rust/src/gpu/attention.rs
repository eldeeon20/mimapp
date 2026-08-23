//! Attention SDPA mono-head: out = softmax(Q·Kᵀ/√d)·V.
//! Q,K,V:(s,d) row-major. El thread (i,d) recalcula la fila de scores
//! (simple y suficiente para tests; f16 real en buffers).

const ATTN_F32: &str = r#"
struct P { s: u32, d: u32, p1: u32, p2: u32 }
@group(0) @binding(0) var<storage, read> q_in: array<f32>;
@group(0) @binding(1) var<storage, read> k_in: array<f32>;
@group(0) @binding(2) var<storage, read> v_in: array<f32>;
@group(0) @binding(3) var<storage, read_write> out: array<f32>;
@group(0) @binding(4) var<uniform> p: P;
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) g: vec3<u32>) {
    let i = g.x;
    let d = g.y;
    if (i >= p.s || d >= p.d) { return; }
    let scale: f32 = inverseSqrt(f32(p.d));
    var mx: f32 = -3.4e38;
    for (var j: u32 = 0u; j < p.s; j = j + 1u) {
        var dot: f32 = 0.0;
        for (var t: u32 = 0u; t < p.d; t = t + 1u) {
            dot = dot + q_in[i * p.d + t] * k_in[j * p.d + t];
        }
        mx = max(mx, dot * scale);
    }
    var sum: f32 = 0.0;
    var accv: f32 = 0.0;
    for (var j: u32 = 0u; j < p.s; j = j + 1u) {
        var dot: f32 = 0.0;
        for (var t: u32 = 0u; t < p.d; t = t + 1u) {
            dot = dot + q_in[i * p.d + t] * k_in[j * p.d + t];
        }
        let e = exp(dot * scale - mx);
        sum = sum + e;
        accv = accv + e * v_in[j * p.d + d];
    }
    out[i * p.d + d] = accv / sum;
}
"#;

/// Corre SDPA. `use_f16` = buffers f16.
pub fn run(
    q: &[f32],
    k: &[f32],
    v: &[f32],
    s: usize,
    d: usize,
    use_f16: bool,
) -> Result<(Vec<f32>, f64), String> {
    let need = s * d;
    if q.len() < need || k.len() < need || v.len() < need {
        return Err(format!(
            "tamaños: q {}, k {}, v {} (necesitan s*d={need})",
            q.len(),
            k.len(),
            v.len()
        ));
    }
    let (device, queue) = super::ctx()?;

    let conv = |arr: &[f32]| -> Vec<u8> {
        if use_f16 {
            super::u16_bytes(&super::to_u16_bits(arr))
        } else {
            super::f32_bytes(arr)
        }
    };
    let elem = if use_f16 { 2usize } else { 4usize };

    let buf_q = super::storage_buf(&device, &conv(&q[..need]), true);
    let buf_k = super::storage_buf(&device, &conv(&k[..need]), true);
    let buf_v = super::storage_buf(&device, &conv(&v[..need]), true);
    let buf_out = super::storage_buf(&device, &vec![0u8; need * elem], false);
    let ubo = super::uniform_buf(
        &device,
        &super::params_bytes([s as u32, d as u32, 0, 0]),
    );

    let (layout, pipeline) = super::build_pipeline(
        &device,
        ATTN_F32,
        &[(0, false), (1, false), (2, false), (3, false), (4, true)],
    )?;

    let start = std::time::Instant::now();
    super::dispatch(
        &device,
        &queue,
        &pipeline,
        &layout,
        vec![
            (0, buf_q.as_entire_binding()),
            (1, buf_k.as_entire_binding()),
            (2, buf_v.as_entire_binding()),
            (3, buf_out.as_entire_binding()),
            (4, ubo.as_entire_binding()),
        ],
        (((s as u32) + 7) / 8, ((d as u32) + 7) / 8, 1),
    );
    let raw = super::read_back(&device, &queue, &buf_out, (need * elem) as u64)?;
    let ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok((super::bytes_to_f32(&raw, use_f16), ms))
}
