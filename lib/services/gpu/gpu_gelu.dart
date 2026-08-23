import '../../src/rust/api/gpu.dart' as rust;

/// GELU tanh-approx en GPU. Con [f16]=true corre el kernel con array<f16>
/// real (requiere Features::SHADER_F16 en el chip).
class GpuGelu {
  Future<GpuOpResult> run(List<double> input, {bool f16 = false}) {
    return rust.gpuGelu(input: input, useF16: f16);
  }
}
