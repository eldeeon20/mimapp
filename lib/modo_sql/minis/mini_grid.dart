import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../media_server/media_server.dart';

/// Cuadrícula de vista previa con UN SOLO scroll libre (slivers).
///
/// Sin caja anidada: el grid ES el scroll de la pestaña, carga
/// perezoso lo visible y el dedo nunca se traba entre dos scrolls.
///
/// Imágenes: previa guardada (o mini al vuelo en moldes viejos).
/// Videos con previas: transición (cicla frames). Lo demás:
/// icono + formato + nombre (nunca cuadro vacío).
class MiniGrid extends StatelessWidget {
  /// Solo imágenes (txt/no_open quedan en la lista, no gastan preview).
  final List<FichaArchivo> imagenes;

  /// No-imágenes (videos, docs…): icono o transición, nunca vacío.
  final List<FichaArchivo> otros;

  /// Minis ya en RAM (por nombre).
  final Map<String, Uint8List> minis;

  /// Cuántas minis hay en RAM (para el contador del título).
  final int minisEnRam;

  /// Archivo seleccionado (borde teal).
  final String? selNombre;

  /// Encabezado arriba del grid (título + filtro).
  final Widget encabezado;

  /// Pide la mini de un archivo (memoizada en MiniCache).
  final Future<Uint8List?> Function(FichaArchivo f) miniDe;

  /// Tap en un cuadro (selecciona + abre Recuperar).
  final void Function(FichaArchivo f) onTap;

  /// Previas guardadas por nombre (memo del modo, se llena solo).
  final Map<String, List<Uint8List>> previas;

  /// Lee las previas guardadas de un archivo ([] = sin previas).
  final Future<List<Uint8List>> Function(FichaArchivo f) previasDe;

  /// ¿Es video? (transición si tiene frames, icono si no).
  final bool Function(FichaArchivo f) esVideo;

  /// Subcarpetas de la ruta actual (tap = entrar). Igual que lista.
  final List<String> dirs;
  final void Function(String d) onEntrarDir;

  const MiniGrid({
    super.key,
    required this.imagenes,
    this.otros = const [],
    required this.minis,
    required this.minisEnRam,
    required this.selNombre,
    required this.encabezado,
    required this.miniDe,
    required this.onTap,
    required this.previas,
    required this.previasDe,
    required this.esVideo,
    this.dirs = const [],
    required this.onEntrarDir,
  });

  static String _corto(String nombre) {
    final i = nombre.lastIndexOf('/');
    return i < 0 ? nombre : nombre.substring(i + 1);
  }

  /// Mini con previa primero: si el molde nuevo trae previas
  /// guardadas usa la primera (memoiza en el mapa del modo);
  /// si no, mini al vuelo (moldes viejos).
  Future<Uint8List?> _miniConPrevia(FichaArchivo f) async {
    try {
      final p = await previasDe(f);
      if (p.isNotEmpty) {
        previas[f.nombre] = p;
        return p.first;
      }
    } catch (_) {}
    return miniDe(f);
  }

  /// Marco común: borde selección + tap + nombre abajo.
  Widget _cuadro(FichaArchivo f, Widget hijo) {
    return InkWell(
      onTap: () => onTap(f),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
              color: selNombre == f.nombre
                  ? Colors.tealAccent
                  : Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            hijo,
            Positioned(
              left: 4,
              right: 4,
              bottom: 2,
              child: Text(
                _corto(f.nombre),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 9, backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                encabezado,
                const SizedBox(height: 4),
                Text(
                  'Vista previa · $minisEnRam/${imagenes.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        if (dirs.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            sliver: SliverGrid.builder(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.4,
              ),
              itemCount: dirs.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () => onEntrarDir(dirs[i]),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.amber),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_rounded,
                          size: 30, color: Colors.amber),
                      Text(
                        dirs[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          sliver: SliverGrid.builder(
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemCount: imagenes.length,
            itemBuilder: (_, i) {
              final f = imagenes[i];
              // Previas guardadas: transición si hay varias.
              final pv = previas[f.nombre];
              if (pv != null && pv.isNotEmpty) {
                return _cuadro(
                    f,
                    pv.length == 1
                        ? Image.memory(
                            pv.first,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            cacheWidth: 256,
                            cacheHeight: 256,
                          )
                        : _Cicla(frames: pv));
              }
              final mini = minis[f.nombre];
              final Widget hijo;
              if (mini != null) {
                hijo = Image.memory(
                  mini,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: 256,
                  cacheHeight: 256,
                );
              } else {
                // Cada cuadro carga su propia mini perezoso:
                // el FutureBuilder se redibuja solo al llegar.
                // (previa guardada primero, mini al vuelo después).
                hijo = FutureBuilder<Uint8List?>(
                  future: _miniConPrevia(f),
                  builder: (_, snap) {
                    if (snap.connectionState !=
                        ConnectionState.done) {
                      return const Icon(Icons.image_outlined,
                          size: 32, color: Colors.grey);
                    }
                    final b = snap.data;
                    if (b == null) {
                      return const Icon(
                          Icons.broken_image_outlined,
                          size: 32,
                          color: Colors.redAccent);
                    }
                    return Image.memory(
                      b,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: 256,
                      cacheHeight: 256,
                    );
                  },
                );
              }
              return _cuadro(f, hijo);
            },
          ),
        ),
        if (otros.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            sliver: SliverGrid.builder(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              itemCount: otros.length,
              itemBuilder: (_, i) {
                final f = otros[i];
                final pv = previas[f.nombre];
                if (pv != null) {
                  // Videos con frames: transición; sin frames: icono.
                  if (pv.isNotEmpty && esVideo(f)) {
                    return _cuadro(f, _Cicla(frames: pv));
                  }
                  return _cuadro(f, _TileIcono(f: f, esVideo: esVideo(f)));
                }
                return FutureBuilder<List<Uint8List>>(
                  future: previasDe(f),
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return _cuadro(
                          f, _TileIcono(f: f, esVideo: esVideo(f)));
                    }
                    final p = snap.data ?? const <Uint8List>[];
                    previas[f.nombre] = p;
                    if (p.isNotEmpty && esVideo(f)) {
                      return _cuadro(f, _Cicla(frames: p));
                    }
                    return _cuadro(
                        f, _TileIcono(f: f, esVideo: esVideo(f)));
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Transición: cicla los frames de la previa cada 900ms.
class _Cicla extends StatefulWidget {
  final List<Uint8List> frames;
  const _Cicla({required this.frames});

  @override
  State<_Cicla> createState() => _CiclaEstado();
}

class _CiclaEstado extends State<_Cicla> {
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.frames.length > 1) {
      _t = Timer.periodic(
        const Duration(milliseconds: 900),
        (_) {
          if (!mounted) return;
          setState(() => _i = (_i + 1) % widget.frames.length);
        },
      );
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      widget.frames[_i.clamp(0, widget.frames.length - 1)],
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: 256,
      cacheHeight: 256,
    );
  }
}

/// Icono informativo: nunca un cuadro vacío (formato + nombre).
class _TileIcono extends StatelessWidget {
  final FichaArchivo f;
  final bool esVideo;
  const _TileIcono({required this.f, required this.esVideo});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          esVideo
              ? Icons.movie_rounded
              : Icons.insert_drive_file_rounded,
          size: 30,
          color: esVideo ? Colors.lightBlueAccent : Colors.grey,
        ),
        Text(
          f.formato.isEmpty ? 'archivo' : f.formato,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white70),
        ),
      ],
    );
  }
}
