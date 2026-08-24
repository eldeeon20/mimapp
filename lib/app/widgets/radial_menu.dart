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
    (key: 'gpu', label: 'GPU', icon: Icons.memory_rounded,
        color: Colors.pinkAccent),
    (key: 'dl', label: 'Descargas', icon: Icons.download_rounded,
        color: Colors.tealAccent),
    (key: 'bt', label: 'Torrent', icon: Icons.bolt_rounded,
        color: Colors.amberAccent),
    (key: 'ag', label: 'Agentes IA', icon: Icons.psychology_rounded,
        color: Colors.lightGreenAccent),
    (key: 'rv', label: 'Voto BLSAG', icon: Icons.how_to_vote_rounded,
        color: Colors.green),
    (key: 'ip', label: 'IPFS', icon: Icons.hub_rounded,
        color: Colors.tealAccent),
    (key: 'ua', label: 'Unarc', icon: Icons.folder_zip_rounded,
        color: Colors.blueAccent),
    (key: 'ub', label: 'Nostr Busca', icon: Icons.search_rounded,
        color: Colors.indigoAccent),
  ];

  /// Botón central: abre las firmas ring de Nostringer.
  static const centerItem = (
    key: 'ring',
    label: 'Nostringer',
    icon: Icons.fingerprint_rounded,
    color: Color(0xFFB57CFF),
  );

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
    // Adaptativo a orientación: en landscape el radio sale de la altura
    // (si no, los botones se van fuera de pantalla).
    final isLandscape = size.width > size.height;
    final radius = isLandscape
        ? math.max(90.0, size.height * 0.5 - 95)
        : size.width * 0.34;
    final centerY = size.height * (isLandscape ? 0.5 : 0.42);

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
              child: Column(children: [
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onSelect(centerItem.key);
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF111A46),
                      border:
                          Border.all(color: centerItem.color, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: centerItem.color.withValues(alpha: .45),
                          blurRadius: 25,
                        ),
                      ],
                    ),
                    child: Icon(centerItem.icon,
                        size: 38, color: centerItem.color),
                  ),
                ),
                const SizedBox(height: 6),
                Text(centerItem.label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: centerItem.color.withValues(alpha: .9))),
              ]),
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
