import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../media_server/media_server.dart';

/// Cuadrícula de vista previa con UN SOLO scroll libre (slivers).
///
/// Sin caja anidada: el grid ES el scroll de la pestaña, carga
/// perezoso lo visible y el dedo nunca se traba entre dos scrolls.
class MiniGrid extends StatelessWidget {
  /// Solo imágenes (txt/no_open quedan en la lista, no gastan preview).
  final List<FichaArchivo> imagenes;

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

  /// Subcarpetas de la ruta actual (tap = entrar). Igual que lista.
  final List<String> dirs;
  final void Function(String d) onEntrarDir;

  const MiniGrid({
    super.key,
    required this.imagenes,
    required this.minis,
    required this.minisEnRam,
    required this.selNombre,
    required this.encabezado,
    required this.miniDe,
    required this.onTap,
    this.dirs = const [],
    required this.onEntrarDir,
  });

  static String _corto(String nombre) {
    final i = nombre.lastIndexOf('/');
    return i < 0 ? nombre : nombre.substring(i + 1);
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
                hijo = FutureBuilder<Uint8List?>(
                  future: miniDe(f),
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
                              fontSize: 9,
                              backgroundColor: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
