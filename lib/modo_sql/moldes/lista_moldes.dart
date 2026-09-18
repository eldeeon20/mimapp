import 'package:flutter/material.dart';

import '../comun/campos.dart';
import '../media_server/media_server.dart';

/// Moldes como CARPETAS (sin historial): tap = abrir.
class ListaMoldes extends StatelessWidget {
  final List<MoldeInfo> moldes;
  final String? abierta;
  final bool cargando;
  final VoidCallback onRecargar;
  final void Function(String nombre) onAbrir;
  final void Function(String nombre) onBorrar;

  /// Sin borrar (grid/lista): borrar es gestión de la pestaña Moldes.
  final bool conBorrar;

  const ListaMoldes({
    super.key,
    required this.moldes,
    required this.abierta,
    required this.cargando,
    required this.onRecargar,
    required this.onAbrir,
    required this.onBorrar,
    this.conBorrar = true,
  });

  @override
  Widget build(BuildContext context) {
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
        for (final m in moldes)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.folder_rounded,
                  size: 28, color: Colors.amber),
              selected: abierta == m.nombre,
              title: Text(m.nombre,
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(fmtBytes(m.total),
                  style: const TextStyle(fontSize: 10)),
              onTap: () => onAbrir(m.nombre),
              trailing: conBorrar
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18, color: Colors.redAccent),
                      tooltip: 'Borrar molde',
                      onPressed: () => onBorrar(m.nombre),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}
