import 'package:flutter/material.dart';

/// Caja de log de WebK (solo muestra líneas).
class CajaLog extends StatelessWidget {
  final List<String> lineas;
  const CajaLog({super.key, required this.lineas});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[800]!),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: SelectableText(
          lineas.isEmpty ? '· log ·' : lineas.join('\n'),
          style:
              const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
