import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../media/media_player.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours > 0 ? '${d.inHours}:$m' : m}:$s';
}

/// Pantalla standalone de Media: player con video y barra de progreso.
class MediaScreen extends StatefulWidget {
  final MediaPlayer mediaPlayer;
  const MediaScreen({super.key, required this.mediaPlayer});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  bool _hasVideo = false;
  bool _playing = false;
  double? _dragValue;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    widget.mediaPlayer.onChanged = () {
      if (mounted) setState(() {});
    };
    // Estado inicial REAL del player (el audio/video sigue en segundo plano).
    _hasVideo = widget.mediaPlayer.hasVideo;
    _playing = widget.mediaPlayer.isPlaying;
    _subs.add(widget.mediaPlayer.widthStream.listen((w) {
      if (mounted) setState(() => _hasVideo = (w ?? 0) > 0);
    }));
    _subs.add(widget.mediaPlayer.playingStream.listen((p) {
      if (mounted) setState(() => _playing = p);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mp = widget.mediaPlayer;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasVideo)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(controller: mp.videoController),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.music_note, size: 56, color: Colors.grey),
            ),
          const SizedBox(height: 8),
          Text(mp.status,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          if (mp.current.isNotEmpty)
            Text(mp.current,
                style: const TextStyle(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          StreamBuilder<Duration>(
            stream: mp.durationStream,
            initialData: mp.duration,
            builder: (context, durSnap) {
              final dur = durSnap.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: mp.positionStream,
                initialData: mp.position,
                builder: (context, posSnap) {
                  final posMs = _dragValue ??
                      (posSnap.data ?? Duration.zero).inMilliseconds
                          .toDouble();
                  final durMs =
                      dur.inMilliseconds > 0 ? dur.inMilliseconds : 1;
                  return Column(
                    children: [
                      Slider(
                        min: 0,
                        max: durMs.toDouble(),
                        value: posMs.clamp(0, durMs.toDouble()),
                        onChanged: durMs <= 1
                            ? null
                            : (v) => setState(() => _dragValue = v),
                        onChangeEnd: (v) async {
                          await mp.seek(Duration(milliseconds: v.round()));
                          if (mounted) setState(() => _dragValue = null);
                        },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_fmt(Duration(milliseconds: posMs.round())),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                          Text(_fmt(dur),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => mp.pickAndPlay(),
                icon: const Icon(Icons.folder_open),
                label: const Text('Abrir lista'),
              ),
              const SizedBox(width: 12),
              if (mp.queueLength > 1) ...[
                IconButton(
                  onPressed: () => mp.previous(),
                  icon: const Icon(Icons.skip_previous, size: 32),
                ),
                Text('${mp.queueIndex + 1}/${mp.queueLength}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.grey)),
                IconButton(
                  onPressed: () => mp.next(),
                  icon: const Icon(Icons.skip_next, size: 32),
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                onPressed: () => mp.playOrPause(),
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                    size: 32),
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
