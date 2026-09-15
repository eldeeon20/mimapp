import 'package:flutter/material.dart';

/// Marco del WebView embebido (modo normal con borde, completo sin).
/// Recibe la vista ya creada: NO la reconstruye (si muere, queda en blanco).
class MarcoWeb extends StatelessWidget {
  final Widget vista;
  final bool borde;
  const MarcoWeb({super.key, required this.vista, this.borde = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          borde ? const EdgeInsets.fromLTRB(8, 0, 8, 0) : EdgeInsets.zero,
      decoration: borde
          ? BoxDecoration(
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(10),
              color: Colors.black,
            )
          : const BoxDecoration(color: Colors.black),
      clipBehavior: Clip.antiAlias,
      child: vista,
    );
  }
}
