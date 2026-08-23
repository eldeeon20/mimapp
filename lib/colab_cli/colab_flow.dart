import 'colab_runtime.dart';

/// Un paso de un flujo automático: código Python con nombre descriptivo.
class FlowStep {
  final String name;
  final String code;

  const FlowStep(this.name, this.code);
}

/// Resultado completo de un flujo.
class FlowResult {
  FlowResult({required this.totalSteps});

  final int totalSteps;
  int executed = 0;
  final List<(String, ColabExecResult)> outputs = [];
  bool get success => outputs.every((o) => !o.$2.isError);

  /// Salida consolidada paso a paso.
  String get log => outputs
      .map((o) => '── ${o.$1} ──\n${o.$2.output}')
      .join('\n\n');
}

/// Ejecutor de flujos ida y vuelta: la app manda pasos Python al kernel
/// de Colab automáticamente (ej.: montar GPU → descargar modelo → correr).
///
/// Uso futuro (botón único):
///   final flow = ColabFlows.t4Model('...url...');
///   await ColabFlowExecutor().run(runtime: rt, steps: flow, onStepStart: ..., onStepDone: ...);
class ColabFlowExecutor {
  /// Ejecuta los pasos en orden sobre el [runtime].
  ///
  /// [onStepStart] = ida (paso enviado), [onStepDone] = vuelta (resultado).
  /// Con [stopOnError] se corta al primer paso que falle (default true).
  Future<FlowResult> run({
    required ColabRuntime runtime,
    required List<FlowStep> steps,
    void Function(int index, FlowStep step)? onStepStart,
    void Function(int index, FlowStep step, ColabExecResult result)?
        onStepDone,
    bool stopOnError = true,
  }) async {
    final out = FlowResult(totalSteps: steps.length);

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      onStepStart?.call(i, step);
      final res = await runtime.execute(step.code);
      out.outputs.add((step.name, res));
      out.executed = i + 1;
      onStepDone?.call(i, step, res);
      if (stopOnError && res.isError) break;
    }
    return out;
  }
}

/// Biblioteca de flujos prearmados (se van agregando).
class ColabFlows {
  ColabFlows._();

  static const _checkGpu = '''
import tensorflow as tf
print("GPU:", tf.config.list_physical_devices('GPU'))''';

  static const _checkTorchGpu = '''
import torch
print("CUDA disponible:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))''';

  /// Flujo básico: verificar GPU (Torch y TF).
  static List<FlowStep> gpuCheck() => const [
        FlowStep('Verificar Torch GPU', _checkTorchGpu),
        FlowStep('Verificar TF GPU', _checkGpu),
      ];
}
