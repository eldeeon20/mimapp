import '../../src/rust/api/gpu.dart' as rust;

/// Attention SDPA mono-head en GPU: softmax(Q·Kᵀ/√d)·V con Q,K,V:(s,d).
/// f16 real en buffers.
class GpuAttention {
  Future<GpuOpResult> run({
    required List<double> q,
    required List<double> k,
    required List<double> v,
    required int seq,
    required int dim,
    bool f16 = false,
  }) {
    return rust.gpuAttention(
      q: q,
      k: k,
      v: v,
      dims: rust.AttentionDims(s: seq, d: dim),
      useF16: f16,
    );
  }
}
