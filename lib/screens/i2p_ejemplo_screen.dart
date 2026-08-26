import 'package:flutter/material.dart';

import '../services/i2p_service.dart';
import 'i2p_test_screen.dart';

/// EJEMPLO I2P (menú radial): demo autónomo que verifica el router con un
/// GET fijo a un eepsite estable. Sin opciones ni campos libres — esas están
/// en el engranaje de arriba (panel de control), NO en Ajustes.
class I2pEjemploScreen extends StatefulWidget {
  const I2pEjemploScreen({super.key});

  @override
  State<I2pEjemploScreen> createState() => _I2pEjemploScreenState();
}

class _I2pEjemploScreenState extends State<I2pEjemploScreen> {
  final I2pService _s = I2pService.instance;

  /// Eepsite canónico de prueba (mantenido por zzz, dev core de I2P).
  static const _url = 'http://stats.i2p/';

  String _salida = '';
  bool _corriendo = false;

  void _bump() {
    if (!mounted) return;
    setState(() => _corriendo = _s.running);
  }

  @override
  void initState() {
    super.initState();
    _s.addListener(_bump);
    _corriendo = _s.running;
    _s.refresh();
  }

  @override
  void dispose() {
    _s.removeListener(_bump);
    super.dispose();
  }

  Future<void> _correr() async {
    setState(() => _salida = '[ejemplo] consultando $_url …');
    try {
      final r = await _s.httpGet(_url);
      setState(() => _salida =
          '[ejemplo]\n' + (r.length > 3000 ? '${r.substring(0, 3000)}…' : r));
    } catch (e) {
      setState(() => _salida = '[ejemplo] ERROR: $e\n'
          '(si recién arrancó el router, esperá a que construya túneles '
          'y reintentá)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('I2P · ejemplo eepsite'), actions: [
        IconButton(
          tooltip: 'Opciones del router',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const I2pTestScreen())),
        ),
      ]),
      body: ListenableBuilder(
        listenable: _s,
        builder: (_, __) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Icon(Icons.hub,
                        color: _corriendo ? Colors.green : Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      _s.busy
                          ? 'trabajando…'
                          : (_corriendo ? 'router corriendo' : 'router apagado'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                    'Este ejemplo hace un GET a $_url, un eepsite estable '
                    'dentro de la red I2P, usando el router emissary '
                    'embebido por SAMv3 directo.',
                    style: TextStyle(fontSize: 12),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            if (!_corriendo)
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Iniciar router'),
                onPressed: _s.busy ? null : _s.start,
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.science_outlined),
                label: const Text('Correr ejemplo'),
                onPressed: _correr,
              ),
            if (!_corriendo)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Primer arranque: reseed + construcción de túneles puede '
                  'tardar minutos. Cuando esté corriendo, volvé y corré el '
                  'ejemplo.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            const SizedBox(height: 12),
            if (_salida.isNotEmpty)
              Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SelectableText(
                    _salida,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: Colors.lightGreenAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
