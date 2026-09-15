import 'package:flutter/material.dart';

/// Menú de páginas de WebK: overlay con buscador local + lista de webs +
/// historial. Se cierra al tocar fuera ([onCerrar]) o con el botón atrás
/// (la pantalla lo envuelve en PopScope).
class MenuPaginas extends StatefulWidget {
  final List<String> paginas;
  final List<Map<String, String>> historial;
  final ValueChanged<String> onElegir;
  final VoidCallback onCerrar;
  final VoidCallback onBorrarHistorial;

  const MenuPaginas({
    super.key,
    required this.paginas,
    required this.historial,
    required this.onElegir,
    required this.onCerrar,
    required this.onBorrarHistorial,
  });

  @override
  State<MenuPaginas> createState() => _MenuPaginasState();
}

class _MenuPaginasState extends State<MenuPaginas> {
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    final pags = widget.paginas
        .where((p) => p.toLowerCase().contains(_filtro.toLowerCase()))
        .toList();
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onCerrar,
        child: Container(
          color: Colors.black54,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () {}, // dentro del menú no cierra
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 60, 16, 0),
              constraints:
                  const BoxConstraints(maxHeight: 420, maxWidth: 420),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1220),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: TextField(
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'buscar web local…',
                        prefixIcon:
                            Icon(Icons.search_rounded, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _filtro = v),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      children: [
                        for (final p in pags)
                          ListTile(
                            dense: true,
                            leading: const Icon(
                                Icons.language_rounded,
                                size: 18),
                            title: Text(p,
                                style: const TextStyle(fontSize: 13)),
                            onTap: () => widget.onElegir(p),
                          ),
                        if (pags.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('sin páginas',
                                style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12)),
                          ),
                        const Divider(height: 16),
                        Row(
                          children: [
                            const Text('Historial',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const Spacer(),
                            TextButton(
                              onPressed: widget.historial.isEmpty
                                  ? null
                                  : widget.onBorrarHistorial,
                              child: const Text('borrar',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        if (widget.historial.isEmpty)
                          const Text('vacío',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54)),
                        for (final h
                            in widget.historial.reversed.take(10))
                          ListTile(
                            dense: true,
                            leading: const Icon(
                                Icons.history_rounded,
                                size: 16),
                            title: Text(h['pagina'] ?? '',
                                style: const TextStyle(fontSize: 12)),
                            trailing: Text(h['cuando'] ?? '',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                            onTap: () =>
                                widget.onElegir(h['pagina'] ?? ''),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
