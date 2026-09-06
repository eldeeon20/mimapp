import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../build_info.dart';
import '../services/tor_service.dart';

/// Probador del Tor embebido: arranque/parada, dormante, GET de páginas
/// comunes (o .onion) y descarga de archivos por el circuito (CDN /
/// git smart-http) con progreso, para verificar el túnel de punta a punta.
class TorTestScreen extends StatefulWidget {
  const TorTestScreen({super.key});

  @override
  State<TorTestScreen> createState() => _TorTestScreenState();
}

class _TorTestScreenState extends State<TorTestScreen> {
  final _eleCtrl = TextEditingController(text: 'bitcoin.stackwallet.com:50002');
  String? _eleResp;

  final _urlCtrl =
      TextEditingController(text: 'https://check.torproject.org/api/ip');
  final _onionCtrl = TextEditingController(
      text:
          'https://duckduckgogg42xjoc72x3sjasw76w7p7vgic3nbg4y7emtb6onir65lid.onion/');
  final _dlCtrl =
      TextEditingController(text: 'https://speed.hetzner.de/1MB.bin');
  bool _dormant = false;
  String? _response;
  double? _dlProgress;
  String? _dlResult;

  @override
  void initState() {
    super.initState();
    TorService.instance.addListener(_bump);
    TorService.instance.refresh();
  }

  void _bump() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    TorService.instance.removeListener(_bump);
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() work) async {
    if (TorService.instance.busy) return;
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('ERROR: $e',
                style: const TextStyle(color: Colors.redAccent)),
            backgroundColor: Colors.black));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _fetch(String url) => _guard(() async {
        setState(() => _response = 'consultando…');
        final r = await TorService.instance.httpGet(url);
        setState(() => _response = r);
      });

  /// Test del ejemplo Foundation: socket SSL crudo por el circuito.
  Future<void> _electrum() => _guard(() async {
        final t = _eleCtrl.text.trim();
        if (!t.contains(':')) throw 'formato: host:puerto';
        final host = t.split(':').first;
        final puerto = int.tryParse(t.split(':').last.split('/').first);
        if (host.isEmpty || puerto == null) throw 'formato: host:puerto';
        setState(() => _eleResp = 'conectando por el circuito…');
        final r = await TorService.instance.tcpPing(host, puerto);
        setState(() => _eleResp = r);
      });

  Future<void> _download() => _guard(() async {
        final dir = await getApplicationSupportDirectory();
        final name =
            _dlCtrl.text.split('/').last.split('?').first;
        final path = '${dir.path}/tor_dl_$name';
        setState(() {
          _dlProgress = 0;
          _dlResult = null;
        });
        final saved = await TorService.instance.download(
          _dlCtrl.text.trim(),
          savePath: path,
          onProgress: (got, total) =>
              mounted ? setState(() => _dlProgress = total != null && total > 0 ? got / total : null) : null,
        );
        final f = File(saved);
        setState(() {
          _dlProgress = null;
          _dlResult = 'guardado en $saved (${f.lengthSync()} bytes)';
        });
      });

  @override
  Widget build(BuildContext context) {
    final s = TorService.instance;
    final on = s.running;
    return Scaffold(
      body: ListView(padding: const EdgeInsets.all(12), children: [
        // ---- estado + control
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: (on ? Colors.greenAccent : Colors.grey)
                  .withValues(alpha: .1),
              borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('estado: ${s.state}',
                style: const TextStyle(fontSize: 11)),
            Text('fase: ${s.fase}',
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: s.fase == 'listo'
                        ? Colors.greenAccent
                        : Colors.orangeAccent)),
            Text('build $kSha',
                style: const TextStyle(fontSize: 8, color: Colors.white24)),
            if (on)
              SelectableText('salida: HTTP directo por arti (sin puente local)',
                  style:
                      const TextStyle(fontSize: 10.5, fontFamily: 'monospace')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(
                onPressed: s.busy || on ? null : () => _guard(s.start),
                icon: s.busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Iniciar'),
              ),
              OutlinedButton.icon(
                onPressed: !on ? null : () => _guard(s.stop),
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Detener'),
              ),
              OutlinedButton.icon(
                onPressed: !on || s.busy ? null : () => _guard(s.rebootstrap),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Re-bootstrap'),
              ),
            ]),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Modo dormante (batería)',
                  style: TextStyle(fontSize: 12)),
              value: _dormant,
              onChanged: !on
                  ? null
                  : (v) {
                      setState(() => _dormant = v);
                      _guard(() => s.setDormant(v));
                    },
            ),
          ]),
        ),
        const SizedBox(height: 10),
        // ---- test página común
        _row(_urlCtrl, 'URL común', 'GET', () => _fetch(_urlCtrl.text.trim())),
        const SizedBox(height: 8),
        // ---- test onion
        _row(_onionCtrl, 'Servicio .onion', 'GET',
            () => _fetch(_onionCtrl.text.trim())),
        const SizedBox(height: 8),
        // ---- test socket crudo SSL (patrón ejemplo Foundation)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(8)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CONEXIÓN cruda por el circuito',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text('¿abre TCP host:puerto a través del circuito?',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.white38)),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: TextField(
                      controller: _eleCtrl,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      decoration: const InputDecoration(
                          labelText: 'host:puerto'))),
                  FilledButton.tonal(
                      onPressed: s.busy ? null : _electrum,
                      child: const Text('PING')),
                ]),
                if (_eleResp != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SelectableText(_eleResp!,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11))),
              ]),
        ),
        const SizedBox(height: 8),
        // ---- test descarga CDN por el túnel
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            _row(_dlCtrl, 'Descarga CDN por Tor', 'Bajar', _download),
            if (_dlProgress != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: _dlProgress),
              ),
            if (_dlResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_dlResult!,
                    style: const TextStyle(fontSize: 10.5)),
              ),
          ]),
        ),
        if (_response != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
                child: SelectableText(_response!,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: Colors.lightGreenAccent))),
          ),
        ],
        const SizedBox(height: 10),
        // ---- log
        Container(
          height: 130,
          width: double.infinity,
          color: Colors.black.withValues(alpha: .5),
          padding: const EdgeInsets.all(8),
          child: ListView.builder(
            itemCount: s.log.length,
            itemBuilder: (_, i) => Text(s.log[i],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5,
                    fontFamily: 'monospace',
                    color: s.log[i].startsWith('ERROR')
                        ? Colors.redAccent
                        : Colors.greenAccent.withValues(alpha: .7))),
          ),
        ),
      ]),
    );
  }

  Widget _row(TextEditingController c, String label, String btn,
          VoidCallback onPressed) =>
      Row(children: [
        Expanded(
          child: TextField(
            controller: c,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                isDense: true),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: onPressed, child: Text(btn)),
      ]);
}
