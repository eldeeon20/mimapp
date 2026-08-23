//! Linear Y = X·Wᵀ + b (X:(m,k), W:(n,k) row-major, b:(n)).
//! f16 real en buffers; acumulación en f32 dentro del kernel.

const LINEAR_F32: &str = r#"
struct Params { m: u32, n: u32, k: u32, pad: u32 }
@group(0) @binding(0) var<storage, read> a_in: array<f32>;
@group(0) @binding(1) var<storage, read> w_in: array<f32>;
@group(0) @binding(2) var<storage, read> bias: array<f32>;
@group(0) @binding(3) var<storage, read_write> out: array<f32>;
@group(0) @binding(4) var<uniform> p: Params;
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) g: vec3<u32>) {
    let row = g.x;
    let col = g.y;
    if (row >= p.m || col >= p.n) { return; }
    var acc: f32 = 0.0;
    for (var i: u32 = 0u; i < p.k; i = i + 1u) {
        acc = acc + a_in[row * p.k + i] * w_in[col * p.k + i];
    }
    out[row * p.n + col] = acc + bias[col];
}
"#;

const LINEAR_F16: &str = r#"
enable shader-f16;
struct Params { m: u32, n: u32, k: u32, pad: u32 }
@group(0) @binding(0) var<storage, read> a_in: array<f16>;
@group(0) @binding(1) var<storage, read> w_in: array<f16>;
@group(0) @binding(2) var<storage, read> bias: array<f16>;
@group(0) @binding(3) var<storage, read_write> out: array<f16>;
@group(0) @binding(4) var<uniform> p: Params;
@compute @workgroup_size(8, 8)
fn main(@builtin(global_invocation_id) g: vec3<u32>) {
    let row = g.x;
    let col = g.y;
    if (row >= p.m || col >= p.n) { return; }
    var acc: f32 = 0.0;
    for (var i: u32 = 0u; i < p.k; i = i + 1u) {
        acc = acc + f32(a_in[row * p.k + i]) * f32(w_in[col * p.k + i]);
    }
    out[row * p.n + col] = f16(acc + f32(bias[col]));
}
"#;

/// Corre Linear. `use_f16` = buffers f16 (mitad de memoria).
pub fn run(
    input: &[f32],
    weights: &[f32],
    bias: &[f32],
    m: usize,
    n: usize,
    k: usize,
    use_f16: bool,
) -> Result<(Vec<f32>, f64), String> {
    if input.len() < m * k || weights.len() < n * k || bias.len() < n {
        return Err(format!(
            "tamaños: input {} (necesita m*k={}), weights {} (n*k={}), bias {} (n={})",
            input.len(), m * k, weights.len(), n * k, bias.len(), n
        ));
    }
    let (device, queue) = super::ctx()?;

    let conv = |v: &[f32]| -> Vec<u8> {
        if use_f16 {
            super::u16_bytes(&super::to_u16_bits(v))
        } else {
            super::f32_bytes(v)
        }
    };
    let out_len = m * n;
    let elem = if use_f16 { 2usize } else { 4usize };

    let buf_a = super::storage_buf(&device, &conv(&input[..m * k]), true);
    let buf_w = super::storage_buf(&device, &conv(&weights[..n * k]), true);
    let buf_b = super::storage_buf(&device, &conv(&bias[..n]), true);
    let buf_out = super::storage_buf(&device, &vec![0u8; out_len * elem], false);
    let ubo = super::uniform_buf(
        &device,
        &super::params_bytes([m as u32, n as u32, k as u32, 0]),
    );

    let code = if use_f16 { LINEAR_F16 } else { LINEAR_F32 };
    let (layout, pipeline) = super::build_pipeline(
        &device,
        code,
        &[(0, false), (1, false), (2, false), (3, false), (4, true)],
    )?;

    let start = std::time::Instant::now();
    super::dispatch(
        &device,
        &queue,
        &pipeline,
        &layout,
        vec![
            (0, buf_a.as_entire_binding()),
            (1, buf_w.as_entire_binding()),
            (2, buf_b.as_entire_binding()),
            (3, buf_out.as_entire_binding()),
            (4, ubo.as_entire_binding()),
        ],
        (((m as u32) + 7) / 8, ((n as u32) + 7) / 8, 1),
    );
    let raw = super::read_back(&device, &queue, &buf_out, (out_len * elem) as u64)?;
    let ms = start.elapsed().as_secs_f64() * 1000.0;
    Ok((super::bytes_to_f32(&raw, use_f16), ms))
}
