import 'dart:math';

String taskUid() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(99999)}';

/// Plantilla de tarea: el código Python se crea UNA vez.
class ColabTask {
  String id;
  String nombre;
  String code;
  bool hasArg; // con / sin argumento
  String lastArg; // último argumento usado (prefill del pocket)

  ColabTask({
    required this.id,
    this.nombre = '',
    this.code = '',
    this.hasArg = false,
    this.lastArg = '',
  });

  factory ColabTask.fromMap(Map<dynamic, dynamic> m) => ColabTask(
        id: (m['id'] ?? taskUid()).toString(),
        nombre: (m['nombre'] ?? '').toString(),
        code: (m['code'] ?? '').toString(),
        hasArg: m['hasArg'] == true,
        lastArg: (m['lastArg'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'code': code,
        'hasArg': hasArg,
        'lastArg': lastArg,
      };
}

/// Pocket = un envío/ejecución de una tarea con un argumento concreto.
class ColabPocket {
  String id;
  String taskId;
  String argumento;
  String status; // 'pendiente' | 'running' | 'ok' | 'error'
  String output;
  int updatedAt;

  ColabPocket({
    required this.id,
    required this.taskId,
    this.argumento = '',
    this.status = 'pendiente',
    this.output = '',
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  factory ColabPocket.fromMap(Map<dynamic, dynamic> m) => ColabPocket(
        id: (m['id'] ?? taskUid()).toString(),
        taskId: (m['taskId'] ?? '').toString(),
        argumento: (m['argumento'] ?? '').toString(),
        status: (m['status'] ?? 'pendiente').toString(),
        output: (m['output'] ?? '').toString(),
        updatedAt: (m['updatedAt'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'taskId': taskId,
        'argumento': argumento,
        'status': status,
        'output': output,
        'updatedAt': updatedAt,
      };
}
