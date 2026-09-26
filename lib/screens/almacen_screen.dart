import 'package:flutter/material.dart';

import '../services/almacen.dart';
import '../services/settings.dart';

/// Almacén y caché: check de memoria (Kotlin) + tamaños por grupo +
/// limpieza en DOS modos: Datos (db, sin app.db) y Descargados
/// (modelos, descargas, torrents). Todo con confirmación y conteo.
class AlmacenScreen extends StatefulWidget {
  const AlmacenScreen({super.key});

  @override
  State<AlmacenScreen> createState() => _AlmacenScreenState();
}

class _AlmacenScreenState extends State<AlmacenScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, int> _mem = {
    'internaTotal': 0,
    'internaLibre': 0,
    'ramTotal': 0,
    'ramLibre': 0,
  };
  GrupoCache? _datos;
  GrupoCache? _descargas;
  String _raizTorrent = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await Settings.instance.load();
      var raiz = Settings.instance.torrentRoot;
      if (raiz.isEmpty) {
        final docs = await Almacen.docs();
        raiz = '$docs/torrent';
      }
      final mem = await Almacen.memoria();
      final datos = await Almacen.grupoDatos();
      final desc = await Almacen.grupoDescargas(raiz);
      if (!mounted) return;
      setState(() {
        _mem = mem;
        _datos = datos;
        _descargas = desc;
        _raizTorrent = raiz;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  Future<void> _liberar(GrupoCache g) async {
    if (g.rutas.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Liberar ${g.nombre}?'),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Se borran ${g.rutas.length} item(s) '
                    '(${Almacen.fmt(g.bytes)}):'),
                const SizedBox(height: 8),
                for (final r in g.rutas.take(20))
                  Text('· ${Almacen.base(r)}',
                      style: const TextStyle(fontSize: 12)),
                if (g.rutas.length > 20)
                  Text('… y ${g.rutas.length - 20} más',
                      style: const TextStyle(fontSize: 12)),
                if (g.nombre.startsWith('Datos'))
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                        'OJO: son tus db locales (app.db con ajustes, a salvo).',
                        style: TextStyle(color: Colors.orange, fontSize: 12)),
                  ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await Almacen.liberar(g.rutas);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Liberados $n item(s)')));
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final total = _mem['internaTotal'] ?? 0;
    final libre = _mem['internaLibre'] ?? 0;
    final usado = (total - libre).clamp(0, total);
    final ramT = _mem['ramTotal'] ?? 0;
    final ramL = _mem['ramLibre'] ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Almacén y caché'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Recalcular',
              onPressed: _cargando ? null : _check),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText('ERROR: $_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _titulo('Memoria (check nativo)'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Interna: ${Almacen.fmt(usado)} usados / '
                                  '${Almacen.fmt(total)} '
                                  '(${Almacen.fmt(libre)} libres)',
                                  style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                  value: total > 0
                                      ? usado / total
                                      : 0),
                              const SizedBox(height: 8),
                              Text(
                                  'RAM: ${Almacen.fmt(ramT - ramL)} en uso / '
                                  '${Almacen.fmt(ramT)} '
                                  '(${Almacen.fmt(ramL)} libres)',
                                  style: const TextStyle(fontSize: 13)),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                  value: ramT > 0
                                      ? (ramT - ramL) / ramT
                                      : 0),
                            ]),
                      ),
                    ),
                    _grupoCard(
                      _datos,
                      Icons.storage_rounded,
                      'app.db (ajustes) nunca se toca.',
                      _liberar,
                    ),
                    _grupoCard(
                      _descargas,
                      Icons.download_rounded,
                      _raizTorrent.isEmpty
                          ? ''
                          : 'Raíz torrents: $_raizTorrent',
                      _liberar,
                    ),
                  ],
                ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold)),
      );

  Widget _grupoCard(
    GrupoCache? g,
    IconData icono,
    String pie,
    Future<void> Function(GrupoCache) onLiberar,
  ) {
    if (g == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icono, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        '${g.nombre} · ${Almacen.fmt(g.bytes)}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold))),
                FilledButton.tonalIcon(
                  onPressed: g.rutas.isEmpty ? null : () => onLiberar(g),
                  icon: const Icon(Icons.cleaning_services_rounded,
                      size: 16),
                  label: const Text('Liberar',
                      style: TextStyle(fontSize: 12)),
                ),
              ]),
              if (g.detalle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final d in g.detalle)
                          Text('· ${d.key}: ${Almacen.fmt(d.value)}',
                              style: const TextStyle(fontSize: 12)),
                      ]),
                ),
              if (g.nombre.startsWith('Datos')) ...[
                const SizedBox(height: 4),
                for (final r in g.rutas.take(8))
                  Text('· ${Almacen.base(r)}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white54)),
                if (g.rutas.length > 8)
                  Text('… y ${g.rutas.length - 8} más',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white54)),
                if (g.rutas.isEmpty)
                  const Text('vacío',
                      style: TextStyle(
                          fontSize: 11, color: Colors.white54)),
              ],
              if (pie.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(pie,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                ),
            ]),
      ),
    );
  }
}
