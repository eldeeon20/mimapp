import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/i2p_service.dart';

/// Panel de opciones del router I2P embebido (emissary): estado vivo,
/// iniciar/detener manual, sonda SAM y campos libres para GET/descarga.
/// Sin ejemplos hardcodeados: todo entra por los campos que llenes.
class I2pTestScreen extends StatefulWidget {
  const I2pTestScreen({super.key});

  @override
  State<I2pTestScreen> createState() => _I2pTestScreenState();
}

class _I2pTestScreenState extends State<I2pTestScreen> {
  final I2pService _s = I2pService.instance;
  final _urlCtrl = TextEditingController();
  final _dlCtrl = TextEditingController();

  String _salida = '';
  double? _progreso;

  void _bump() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _s.addListener(_bump);
    _s.refresh();
  }

  @override
  void dispose() {
    _s.removeListener(_bump);
    _urlCtrl.dispose();
    _dlCtrl.dispose();
    super.dispose();
  }

  Future<void> _get() async {
    setState(() => _salida = 'consultando ${_urlCtrl.text}…');
    try {
      final r = await _s.httpGet(_urlCtrl.text.trim());
      setState(() => _salida = r.length > 4000 ? '${r.substring(0, 4000)}…' : r);
    } catch (e) {
      setState(() => _salida = 'ERROR: $e');
    }
  }

  Future<void> _descargar() async {
    final url = _dlCtrl.text.trim();
    try {
      final dir = await getApplicationSupportDirectory();
      final nombre = 'i2p_dl_${DateTime.now().millisecondsSinceEpoch}';
      final path = '${dir.path}/$nombre';
      setState(() {
        _progreso = null;
        _salida = 'descargando $url…';
      });
      await _s.download(url, savePath: path,
          onProgress: (got) => mounted
              ? setState(() => _progreso = got.toDouble())
              : null);
      setState(() {
        _progreso = -1;
        _salida = 'guardado en:\n$path';
      });
    } catch (e) {
      setState(() {
        _progreso = null;
        _salida = 'ERROR descarga: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('I2P embebido · emissary')),
      body: ListenableBuilder(
        listenable: _s,
        builder: (_, __) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // ---------- header estado
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(
                      _s.running ? Icons.hub : Icons.hub_outlined,
                      color: _s.running
                          ? (_s.state.contains('listo')
                              ? Colors.green
                              : Colors.orange)
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _s.busy ? 'trabajando…' : _s.state,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ]),
                  if (_s.samPort != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SelectableText(
                          'SAMv3: 127.0.0.1:${_s.samPort} · '
                          'directo (sin puente local)'),
                    ),
                ]),
              ),
            ),
            // ---------- control
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: Icon(_s.running
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(_s.running ? 'Detener router' : 'Iniciar router'),
                  onPressed: _s.busy
                      ? null
                      : () => _s.running ? _s.stop() : _s.start(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _s.running ? _s.probeSam : null,
                child: const Text('Sonda SAM'),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Publicar mi dirección (inbound)',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                  'Solo con IP real + puerto forwardeado; tras CGNAT '
                  'dejalo apagado',
                  style: TextStyle(fontSize: 11)),
              value: _s.publicar,
              onChanged: _s.running
                  ? null
                  : (v) => setState(() => _s.publicar = v),
            ),
            const SizedBox(height: 4),
            const Text(
              'El router queda vivo a nivel app hasta que lo detengas. '
              'Primer arranque: reseed + construcción de túneles puede '
              'tardar minutos.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Divider(height: 24),
            // ---------- EJEMPLO (separado de las opciones)
            Card(
              color: Colors.blueGrey.shade900,
              margin: EdgeInsets.zero,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.science_outlined),
                title: const Text('Ejemplo',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'GET $_urlEjemplo · eepsite estable para verificar '
                    'que los túneles funcionan',
                    style: TextStyle(fontSize: 11)),
                trailing: OutlinedButton(
                  onPressed: _s.running ? _ejemplo : null,
                  child: const Text('Correr'),
                ),
              ),
            ),
            const Divider(height: 24),
            // ---------- GET libre
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL eepsite (ej: algo.i2p/pagina o xxx.b32.i2p)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _s.running ? _get() : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.travel_explore),
              label: const Text('GET por I2P'),
              onPressed: _s.running && _urlCtrl.text.isNotEmpty ? _get : null,
            ),
            const Divider(height: 24),
            // ---------- descarga libre
            TextField(
              controller: _dlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL de archivo a descargar por I2P',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Descargar por I2P'),
              onPressed:
                  _s.running && _dlCtrl.text.isNotEmpty ? _descargar : null,
            ),
            if (_progreso != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                    value: _progreso! <= 0 ? null : null),
              ),
            const Divider(height: 24),
            // ---------- salida
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
            // ---------- log
            if (_s.log.isNotEmpty)
              ExpansionTile(
                title: const Text('Registro',
                    style: TextStyle(fontSize: 13)),
                childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      _s.log.join('\n'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
