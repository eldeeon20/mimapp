import '../../src/rust/api/gpu.dart' as rust;

/// Linear Y = X·Wᵀ + b en GPU: X:(m,k), W:(n,k), bias:(n).
/// f16 real en buffers (mitad de memoria), acumulación f32.
class GpuLinear {
  Future<GpuOpResult> run({
    required List<double> input,
    required List<double> weights,
    required List<double> bias,
    required int m,
    required int n,
    required int k,
    bool f16 = false,
  }) {
    return rust.gpuLinear(
      input: input,
      weights: weights,
      bias: bias,
      dims: rust.LinearDims(m: m, n: n, k: k),
      useF16: f16,
    );
  }
}
