import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ipfs_service.dart';

/// Test IPFS local (fase 1 offline): iniciar/detener nodo, agregar
/// archivos, listar CIDs locales, leer contenido como texto, pin,
/// gateway HTTP opcional en :8080.
class IpfsTestScreen extends StatefulWidget {
  const IpfsTestScreen({super.key});

  @override
  State<IpfsTestScreen> createState() => _IpfsTestScreenState();
}

class _IpfsTestScreenState extends State<IpfsTestScreen> {
  final _cidCtrl = TextEditingController();
  final _log = <String>[];
  bool _busy = false;
  bool _gateway = false;
  String? _selectedCid;
  String _readout = '';

  IpfsService get _svc => IpfsService.instance;

  void _say(String m) => setState(() {
        _log.insert(0, m);
        if (_log.length > 40) _log.removeLast();
      });

  @override
  void initState() {
    super.initState();
    _say(_svc.status());
  }

  @override
  void dispose() {
    _cidCtrl.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<String> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _say(await work());
    } catch (e) {
      _say('ERROR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleNode() async {
    await _guard(() async =>
        _svc.running ? await _svc.stop() : await _svc.start(gateway: _gateway));
  }

  Future<void> _addFile() async {
    if (!_svc.running) {
      _say('iniciá el nodo primero');
      return;
    }
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return;
    await _guard(() async {
      final cid = await _svc.addFile(File(path));
      setState(() => _selectedCid ??= cid);
      return 'agregado · ${res!.files.single.name} → $cid';
    });
  }

  Future<void> _pin(String cid) => _guard(() async {
        await _svc.pin(cid);
        return 'pin OK · $cid';
      });

  Future<void> _read(String cid) => _guard(() async {
        final data = await _svc.cat(cid);
        setState(() => _readout = data == null
            ? '(sin contenido)'
            : utf8.decode(data, allowMalformed: true));
        return 'leído $cid (${data?.length ?? 0} bytes)';
      });

  Widget _cidRow(String cid) {
    final sel = cid == _selectedCid;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: sel ? Colors.tealAccent.withValues(alpha: .08) : Colors.white.withValues(alpha: .03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: sel ? Colors.tealAccent.withValues(alpha: .5) : Colors.white12),
      ),
      child: ListTile(
        dense: true,
        onTap: () => setState(() => _selectedCid = cid),
        title: Text(cid,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        subtitle: Text(sel ? 'seleccionado' : 'tocá para seleccionar',
            style: const TextStyle(fontSize: 9)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              tooltip: 'Leer texto',
              icon: const Icon(Icons.article_rounded, size: 18),
              onPressed: () => _read(cid)),
          IconButton(
              tooltip: 'Pin',
              icon: const Icon(Icons.push_pin_rounded, size: 18),
              onPressed: () => _pin(cid)),
          IconButton(
              tooltip: 'Copiar CID',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: cid));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('CID copiado'),
                        duration: Duration(seconds: 1)));
              }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = _svc.running;
    return Scaffold(
      appBar: AppBar(title: const Text('IPFS local (offline)')),
      body: Column(children: [
        // ---- estado + controles nodo
        Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (running ? Colors.tealAccent : Colors.orangeAccent)
                .withValues(alpha: .07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (running ? Colors.tealAccent : Colors.orangeAccent)
                    .withValues(alpha: .4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(_svc.status(),
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: running ? Colors.tealAccent : Colors.orangeAccent)),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.icon(
                onPressed: _busy ? null : _toggleNode,
                icon: Icon(running
                    ? Icons.stop_circle_rounded
                    : Icons.play_circle_rounded),
                label: Text(running ? 'Detener' : 'Iniciar'),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
                onPressed:
                    (_busy || !running) ? null : _addFile,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Agregar archivo'),
              ),
              const Spacer(),
              const Text('GW :8080', style: TextStyle(fontSize: 10)),
              Switch(
                value: _gateway,
                onChanged: (v) => setState(() {
                  _gateway = v;
                  if (running) {
                    _say('gateway aplica al reiniciar el nodo');
                  }
                }),
              ),
            ]),
          ]),
        ),
        // ---- lectura de CID pegado o seleccionado
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _cidCtrl,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: _selectedCid ?? 'pegá un CID…',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
                tooltip: 'Leer seleccionado/pegado',
                icon: const Icon(Icons.travel_explore_rounded),
                onPressed: () {
                  final cid =
                      (_cidCtrl.text.trim().isNotEmpty ? _cidCtrl.text.trim() : _selectedCid) ?? '';
                  if (cid.isNotEmpty) _read(cid);
                }),
            IconButton(
                tooltip: 'Pin seleccionado/pegado',
                icon: const Icon(Icons.push_pin_outlined),
                onPressed: () {
                  final cid =
                      (_cidCtrl.text.trim().isNotEmpty ? _cidCtrl.text.trim() : _selectedCid) ?? '';
                  if (cid.isNotEmpty) _pin(cid);
                }),
          ]),
        ),
        if (_readout.isNotEmpty)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 140),
            margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: SingleChildScrollView(
                child: SelectableText(_readout,
                    style: const TextStyle(
                        fontSize: 10.5, fontFamily: 'monospace'))),
          ),
        // ---- lista de CIDs
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('CID LOCALES (${_svc.localCids.length})',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: Colors.white.withValues(alpha: .5))),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: _svc.localCids.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 60),
                    Center(
                        child: Text('agregá un archivo para generar CIDs',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 12))),
                  ])
                : ListView.builder(
                    itemCount: _svc.localCids.length,
                    itemBuilder: (_, i) => _cidRow(_svc.localCids[i])),
          ),
        ),
        // ---- log
        Container(
          height: 110,
          width: double.infinity,
          color: Colors.black.withValues(alpha: .5),
          padding: const EdgeInsets.all(8),
          child: ListView.builder(
            itemCount: _log.length,
            itemBuilder: (_, i) => Text(_log[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 9.5,
                    fontFamily: 'monospace',
                    color: _log[i].startsWith('ERROR')
                        ? Colors.redAccent
                        : Colors.greenAccent.withValues(alpha: .7))),
          ),
        ),
      ]),
    );
  }
}
