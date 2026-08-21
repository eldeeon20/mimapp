import 'package:flutter/material.dart';
import '../media/media_player.dart';

/// Pantalla standalone de Media: player sin dependencia de Lua.
class MediaScreen extends StatefulWidget {
  final MediaPlayer mediaPlayer;
  const MediaScreen({super.key, required this.mediaPlayer});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  @override
  void initState() {
    super.initState();
    widget.mediaPlayer.onChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    final mp = widget.mediaPlayer;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reproductor',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(mp.status,
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  if (mp.current.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(mp.current,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => mp.pickAndPlay(),
                icon: const Icon(Icons.folder_open),
                label: const Text('Abrir archivo'),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => mp.play(),
                icon: const Icon(Icons.play_arrow, size: 32),
              ),
              IconButton(
                onPressed: () => mp.pause(),
                icon: const Icon(Icons.pause, size: 32),
              ),
              IconButton(
                onPressed: () => mp.stop(),
                icon: const Icon(Icons.stop, size: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
