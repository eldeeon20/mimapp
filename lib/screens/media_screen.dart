import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../media/media_player.dart';

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours > 0 ? '${d.inHours}:$m' : m}:$s';
}

/// Pantalla de Media con 3 vistas: Ahora / Historial / Favoritos.
///
/// - Ahora: player con video, progreso y controles (igual que antes).
/// - Historial: últimas reproducciones (cifrado en disco), con buscador;
///   tocar reproduce, la estrella marca favorito, deslizar borra.
/// - Favoritos: solo los marcados, con buscador y limpieza.
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
  final _searchCtrl = TextEditingController();
  String _query = '';

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
    // Biblioteca (historial + favoritos) desde disco cifrado.
    widget.mediaPlayer.library.load().then((_) {
      if (mounted) setState(() {});
    });
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _query = _searchCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, String>> _filter(List<Map<String, String>> items) {
    if (_query.isEmpty) return items;
    final q = _query.toLowerCase();
    return items
        .where((e) =>
            (e['title'] ?? '').toLowerCase().contains(q) ||
            (e['uri'] ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.play_circle), text: 'Ahora'),
              Tab(icon: Icon(Icons.history), text: 'Historial'),
              Tab(icon: Icon(Icons.star), text: 'Favoritos'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(child: _buildNow()),
                _buildHistory(),
                _buildFavorites(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Vista AHORA (player)
  // ===========================================================================

  Widget _buildNow() {
    final mp = widget.mediaPlayer;
    final fav = mp.isCurrentFavorite;
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
            Row(
              children: [
                Expanded(
                  child: Text(mp.current,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: fav ? 'Quitar de favoritos' : 'Marcar favorito',
                  onPressed: () async {
                    await mp.toggleCurrentFavorite();
                    if (mounted) setState(() {});
                  },
                  icon: Icon(fav ? Icons.star : Icons.star_border,
                      color: fav ? Colors.amber : Colors.grey),
                ),
              ],
            ),
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

  // ===========================================================================
  // Vista HISTORIAL
  // ===========================================================================

  Widget _buildHistory() {
    final mp = widget.mediaPlayer;
    final items = _filter(mp.library.history);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar en historial y favoritos...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (mp.library.history.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await mp.library.clearHistory();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('Borrar historial'),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('Sin reproducciones todavía',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      _mediaTile(items[i], showDate: true),
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // Vista FAVORITOS
  // ===========================================================================

  Widget _buildFavorites() {
    final mp = widget.mediaPlayer;
    final items = _filter(mp.library.favorites);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar en historial y favoritos...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (mp.library.favorites.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await mp.library.clearFavorites();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('Borrar favoritos'),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text('Sin favoritos: marcá la estrella al reproducir',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      _mediaTile(items[i], showDate: false),
                ),
        ),
      ],
    );
  }

  /// Fila de historial/favorito: tocar reproduce, estrella alterna favorito,
  /// deslizar quita de la lista.
  Widget _mediaTile(Map<String, String> e, {required bool showDate}) {
    final mp = widget.mediaPlayer;
    final uri = e['uri'] ?? '';
    final title = e['title'] ?? uri;
    final fav = mp.library.isFavorite(uri);
    final isCurrent = mp.current == uri;
    return Dismissible(
      key: ValueKey('media-$showDate-$uri'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red[900],
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) async {
        if (showDate) {
          await mp.library.removeHistory(uri);
        } else {
          await mp.library.toggleFavorite(uri);
        }
        if (mounted) setState(() {});
      },
      child: ListTile(
        leading: Icon(
          isCurrent ? Icons.play_circle_fill : Icons.music_note,
          color: isCurrent ? Colors.greenAccent : Colors.grey,
        ),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight:
                    isCurrent ? FontWeight.bold : FontWeight.normal)),
        subtitle: Text(uri,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: fav ? 'Quitar de favoritos' : 'Marcar favorito',
          onPressed: () async {
            await mp.library.toggleFavorite(uri, title: title);
            if (mounted) setState(() {});
          },
          icon: Icon(fav ? Icons.star : Icons.star_border,
              color: fav ? Colors.amber : Colors.grey),
        ),
        onTap: () => mp.openPath(uri),
      ),
    );
  }
}
