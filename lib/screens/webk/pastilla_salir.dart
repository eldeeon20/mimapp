import 'package:flutter/material.dart';

/// Pastilla Salir overlay del modo completo (no toca el WebView).
class PastillaSalir extends StatelessWidget {
  final VoidCallback onSalir;
  const PastillaSalir({super.key, required this.onSalir});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text('Salir',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
          IconButton(
            tooltip: 'Salir (volver a ejemplos)',
            icon: const Icon(Icons.close_rounded,
                color: Colors.white, size: 20),
            onPressed: onSalir,
          ),
        ]),
      ),
    );
  }
}
