import 'package:flutter/material.dart';

import '../models.dart';

/// Visor de estados fullscreen con barras de progreso (estilo Telegram/IG).
class StoryViewerScreen extends StatefulWidget {
  final Story story;
  const StoryViewerScreen({super.key, required this.story});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) {
    final items = widget.story.items;
    if (items.isEmpty) {
      return const Scaffold(body: Center(child: Text('Sin estados')));
    }
    final item = items[_idx];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx < w / 2) {
            _anterior(items);
          } else {
            _siguiente(items);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [item.color.claro.withValues(alpha: .85), item.color.oscuro],
            ),
          ),
          child: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: i < _idx
                            ? Colors.white
                            : Colors.white24,
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18)),
                  const SizedBox(width: 8),
                  Text(item.titulo,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]),
              ),
              Expanded(
                child: Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(item.icono ?? Icons.auto_awesome_rounded,
                        size: 90, color: Colors.white70),
                    const SizedBox(height: 18),
                    Text(item.titulo,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _siguiente(List<StoryItem> items) {
    if (_idx < items.length - 1) setState(() => _idx++);
    else Navigator.of(context).pop();
  }

  void _anterior(List<StoryItem> items) {
    if (_idx > 0) setState(() => _idx--);
  }
}
