import 'package:flutter/material.dart';

import '../comun/campos.dart';
import '../media_server/media_server.dart';

/// Moldes como CARPETAS (sin historial): tap = abrir.
/// Agrupa por carpeta DEL ÍNDICE (anidadas 'a/b', solo índice: ni SQL
/// ni .mld se tocan). Tocar un molde lo abre (solo ese, no todos).
class ListaMoldes extends StatelessWidget {
  final List<MoldeInfo> moldes;
  final String? abierta;
  final bool cargando;
  final VoidCallback onRecargar;
  final void Function(String nombre) onAbrir;
  final void Function(String nombre) onBorrar;

  /// Sin borrar (grid/lista): borrar es gestión de la pestaña Moldes.
  final bool conBorrar;

  /// En HF por molde (repo+versión): lo que ya está subido.
  final Map<String, ({String repo, int version})> hfInfo;

  /// Carpeta del índice por molde ('' = raíz). Sin esto, todo a raíz.
  final Map<String, String> carpetas;

  /// Mover a otra carpeta (null = sin botón: grid/lista).
  final void Function(String nombre)? onMover;

  const ListaMoldes({
    super.key,
    required this.moldes,
    required this.abierta,
    required this.cargando,
    required this.onRecargar,
    required this.onAbrir,
    required this.onBorrar,
    this.conBorrar = true,
    this.hfInfo = const {},
    this.carpetas = const {},
    this.onMover,
  });

  String _carpetaDe(String nombre) =>
      (carpetas[nombre] ?? '').replaceAll('\\', '/');

  @override
  Widget build(BuildContext context) {
    // Grupos por carpeta (raíz primero, resto alfabético).
    final grupos = <String, List<MoldeInfo>>{};
    for (final m in moldes) {
      grupos.putIfAbsent(_carpetaDe(m.nombre), () => []).add(m);
    }
    final orden = grupos.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty) return -1;
        if (b.isEmpty) return 1;
        return a.compareTo(b);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Moldes (carpetas)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: 'Recargar',
            onPressed: cargando ? null : onRecargar,
          ),
        ]),
        if (moldes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No hay moldes (tocá + para crear o indexá)',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        for (final g in orden) ...[
          if (g.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                  left: 4.0 + 12.0 * (g.split('/').length - 1),
                  top: 8,
                  bottom: 2),
              child: Row(children: [
                const Icon(Icons.folder_open_rounded,
                    size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(g,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                Text('${grupos[g]!.length}',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
            ),
          for (final m in grupos[g]!) _tile(context, m, g.isNotEmpty),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, MoldeInfo m, bool anidado) {
    return Card(
      margin: EdgeInsets.symmetric(
          vertical: 4, horizontal: anidado ? 12 : 0),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.folder_rounded,
            size: 28, color: Colors.amber),
        selected: abierta == m.nombre,
        title: Row(children: [
          Expanded(
            child:
                Text(m.nombre, style: const TextStyle(fontSize: 13)),
          ),
          if (hfInfo.containsKey(m.nombre))
            const Icon(Icons.cloud_done_rounded,
                size: 16, color: Colors.lightBlueAccent),
        ]),
        subtitle: Text(
            fmtBytes(m.total) +
                (hfInfo[m.nombre] == null
                    ? ''
                    : ' · ☁ ${hfInfo[m.nombre]!.repo} '
                        'v${hfInfo[m.nombre]!.version}'),
            style: const TextStyle(fontSize: 10)),
        // Tap = abrir SOLO este molde (no todos los del SQL).
        onTap: () => onAbrir(m.nombre),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (onMover != null)
            IconButton(
              icon: const Icon(Icons.drive_file_move_outline_rounded,
                  size: 18, color: Colors.lightBlueAccent),
              tooltip: 'Mover de carpeta (solo índice)',
              onPressed: () => onMover!(m.nombre),
            ),
          if (conBorrar)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: Colors.redAccent),
              tooltip: 'Borrar molde',
              onPressed: () => onBorrar(m.nombre),
            ),
        ]),
      ),
    );
  }
}
