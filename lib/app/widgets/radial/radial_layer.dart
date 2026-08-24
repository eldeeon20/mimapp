import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'radial_item.dart';

/// Especificación del botón central de una capa ([+] cambiar anillo,
/// [×] cerrar, etc.).
class RadialCenterSpec {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const RadialCenterSpec({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// UNA capa del menú radial: hasta 8 botones alrededor del centro.
/// La geometría y la animación escalonada son las originales del menú
/// único (extraídas tal cual).
class RadialLayerView extends StatelessWidget {
  final List<RadialMenuItem> items;
  final AnimationController ctrl;
  final RadialCenterSpec center;
  final String hint;
  /// Se llama tras cerrar el overlay cuando tocan un botón del anillo.
  final void Function(RadialMenuItem item) onPick;

  const RadialLayerView({
    super.key,
    required this.items,
    required this.ctrl,
    required this.center,
    required this.hint,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Adaptativo a orientación: en landscape el radio sale de la altura
    // (si no, los botones se van fuera de pantalla).
    final isLandscape = size.width > size.height;
    final radius = isLandscape
        ? math.max(90.0, size.height * 0.5 - 95)
        : size.width * 0.34;
    final centerY = size.height * (isLandscape ? 0.5 : 0.42);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < items.length; i++)
          _buildButton(context, items[i], i, items.length, radius, centerY),
        Positioned(
          left: size.width / 2 - 36,
          top: centerY - 36,
          child: ScaleTransition(
            scale:
                CurvedAnimation(parent: ctrl, curve: Curves.easeOutBack),
            child: Column(children: [
              InkWell(
                onTap: center.onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF111A46),
                    border: Border.all(color: center.color, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: center.color.withValues(alpha: .45),
                        blurRadius: 25,
                      ),
                    ],
                  ),
                  child: Icon(center.icon, size: 38, color: center.color),
                ),
              ),
              const SizedBox(height: 6),
              Text(center.label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: center.color.withValues(alpha: .9))),
            ]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Text(hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildButton(BuildContext context, RadialMenuItem item, int i,
      int total, double radius, double centerY) {
    final angle = (-90 + (360 / total) * i) * math.pi / 180; // 0 = arriba
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = centerY;
    final bx = cx + radius * math.cos(angle);
    final by = cy + radius * math.sin(angle);

    final anim = CurvedAnimation(
      parent: ctrl,
      curve: Interval(i * 0.08, 1.0, curve: Curves.easeOutBack),
    );

    return Positioned(
      left: bx - 40,
      top: by - 46,
      child: FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: anim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => onPick(item),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.color.withValues(alpha: .14),
                    border:
                        Border.all(color: item.color.withValues(alpha: .7)),
                    boxShadow: [
                      BoxShadow(
                        color: item.color.withValues(alpha: .3),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Icon(item.icon, color: item.color, size: 30),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: item.color.withValues(alpha: .9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
