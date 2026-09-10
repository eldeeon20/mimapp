import 'package:flutter/material.dart';

import 'bottom_bar.dart';

/// Menú inferior del home: Chat / Media / Laurelia IA / Config / Web.
class HomeBottomMenu extends StatelessWidget {
  final VoidCallback onChat;
  final VoidCallback onMedia;
  final VoidCallback onLaurelia;
  final VoidCallback onConfig;
  final VoidCallback onWeb;

  const HomeBottomMenu({
    super.key,
    required this.onChat,
    required this.onMedia,
    required this.onLaurelia,
    required this.onConfig,
    required this.onWeb,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          BottomButton(
            icon: Icons.chat_bubble_rounded,
            title: 'Chat',
            color: Colors.cyanAccent,
            onTap: onChat,
          ),
          BottomButton(
            icon: Icons.play_arrow_rounded,
            title: 'Media',
            color: Colors.purpleAccent,
            onTap: onMedia,
          ),
          BottomButton(
            icon: Icons.psychology_rounded,
            title: 'Laurelia IA',
            color: Colors.cyanAccent,
            onTap: onLaurelia,
          ),
          BottomButton(
            icon: Icons.settings_rounded,
            title: 'Config',
            color: Colors.orangeAccent,
            onTap: onConfig,
          ),
          BottomButton(
            icon: Icons.language,
            title: 'Web',
            color: Colors.lightBlueAccent,
            onTap: onWeb,
          ),
        ],
      ),
    );
  }
}
