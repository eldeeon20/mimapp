import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Menú circular que se abre al tocar el logo central del home.
/// Botones dispuestos en círculo con animación de escala/fade escalonada.
class RadialMenu extends StatefulWidget {
  final void Function(String key) onSelect;

  const RadialMenu({super.key, required this.onSelect});

  @override
  State<RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<RadialMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const _items = [
    (key: 'dm', label: 'Nostr DM', icon: Icons.chat_bubble_rounded,
        color: Colors.cyanAccent),
    (key: 'obs', label: 'Nostr Obs', icon: Icons.visibility_rounded,
        color: Colors.deepPurpleAccent),
    (key: 'shamir', label: 'Shamir', icon: Icons.call_split_rounded,
        color: Colors.orangeAccent),
    (key: 'kem', label: 'KEM', icon: Icons.enhanced_encryption_rounded,
        color: Colors.greenAccent),
    (key: 'hf', label: 'HuggingFace', icon: Icons.hub_rounded,
        color: Colors.lightBlueAccent),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380))
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final radius = size.width * 0.34;
    final centerY = size.height * 0.42;

    return Material(
      color: Colors.black.withValues(alpha: .82),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
            ),
          ),
          for (var i = 0; i < _items.length; i++)
            _buildButton(i, _items.length, radius, centerY),
          Positioned(
            left: size.width / 2 - 36,
            top: centerY - 36,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF111A46),
                  border: Border.all(color: Colors.deepPurpleAccent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurpleAccent.withValues(alpha: .45),
                      blurRadius: 25,
                    ),
                  ],
                ),
                child: const Icon(Icons.lock_rounded,
                    size: 38, color: Color(0xFFB57CFF)),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Text('tocá afuera para cerrar',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(int i, int total, double radius, double centerY) {
    final item = _items[i];
    final angle = (-90 + (360 / total) * i) * math.pi / 180; // 0 = arriba
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = centerY;
    final bx = cx + radius * math.cos(angle);
    final by = cy + radius * math.sin(angle);

    final anim = CurvedAnimation(
      parent: _ctrl,
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
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onSelect(item.key);
                },
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
