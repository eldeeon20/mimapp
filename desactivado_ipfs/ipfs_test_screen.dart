import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ipfs_service.dart';

/// Test IPFS: DOS tabs sobre el mismo panel —
///   [Offline] nodo local puro (fase 1, gateway :8080)
///   [P2P]     nodo online real: DHT server + bitswap + bootstrap
///             público de libp2p (fase 2, gateway :8081)
/// Ambos viven en singletons del service, así que sobreviven al cambio
/// de tab y se pueden probar los dos a la vez.
class IpfsTestScreen extends StatelessWidget {
  const IpfsTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('IPFS'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Offline'),
            Tab(text: 'P2P online'),
          ]),
        ),
        body: TabBarView(children: [
          _NodePanel(svc: IpfsService.instance),
          _NodePanel(svc: IpfsService.p2p),
        ]),
      ),
    );
  }
}

// ======================================================================
// PANEL por nodo (idéntico para offline y P2P; cambia color/labels)
// ======================================================================

class _NodePanel extends StatefulWidget {
  final IpfsService svc;
  const _NodePanel({required this.svc});

  @override
  State<_NodePanel> createState() => _NodePanelState();
}

class _NodePanelState extends State<_NodePanel>
    with AutomaticKeepAliveClientMixin {
  final _cidCtrl = TextEditingController();
  final _log = <String>[];
  bool _busy = false;
  bool _gateway = false;
  String? _selectedCid;
  String _readout = '';

  IpfsService get _svc => widget.svc;

  Color get _accent => _svc.online ? Colors.lightBlueAccent : Colors.tealAccent;

  @override
  bool get wantKeepAlive => true;

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
      _say(_svc.online ? 'iniciá el nodo P2P primero' : 'iniciá el nodo primero');
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

  Future<void> _providers(String cid) =>
      _svc.online ? _guard(() => _svc.providers(cid)) : _read(cid);

  Widget _cidRow(String cid) {
    final sel = cid == _selectedCid;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color:
            sel ? _accent.withValues(alpha: .08) : Colors.white.withValues(alpha: .03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: sel ? _accent.withValues(alpha: .5) : Colors.white12),
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
              tooltip: _svc.online ? 'Leer' : 'Leer texto',
              icon: const Icon(Icons.article_rounded, size: 18),
              onPressed: () => _read(cid)),
          if (_svc.online)
            IconButton(
                tooltip: 'Providers DHT',
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                onPressed: () => _providers(cid)),
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
    super.build(context);
    final running = _svc.running;
    return Column(children: [
      // ---- estado + controles del nodo
      Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (running ? _accent : Colors.orangeAccent).withValues(alpha: .07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: (running ? _accent : Colors.orangeAccent)
                  .withValues(alpha: .4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_svc.status(),
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: running ? _accent : Colors.orangeAccent)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              onPressed: _busy ? null : _toggleNode,
              icon: Icon(running
                  ? Icons.stop_circle_rounded
                  : Icons.play_circle_rounded),
              label: Text(running ? 'Detener' : 'Iniciar'),
            ),
            FilledButton.tonalIcon(
              onPressed: (_busy || !running) ? null : _addFile,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Agregar archivo'),
            ),
            if (_svc.online)
              FilledButton.tonalIcon(
                onPressed: (_busy || !running)
                    ? null
                    : () => _guard(() => _svc.stats()),
                icon: const Icon(Icons.monitor_heart_rounded, size: 18),
                label: const Text('Stats'),
              ),
            Text('GW :${_svc.gatewayPort}', style: const TextStyle(fontSize: 10)),
            Switch(
              value: _gateway,
              onChanged: (v) => setState(() {
                _gateway = v;
                if (running) _say('el gateway aplica al reiniciar el nodo');
              }),
            ),
          ]),
        ]),
      ),
      // ---- CID pegado o seleccionado
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
              tooltip: _svc.online ? 'Buscar providers' : 'Leer texto',
              icon: Icon(_svc.online
                  ? Icons.manage_search_rounded
                  : Icons.travel_explore_rounded),
              onPressed: () {
                final cid = (_cidCtrl.text.trim().isNotEmpty
                        ? _cidCtrl.text.trim()
                        : _selectedCid) ??
                    '';
                if (cid.isNotEmpty) _providers(cid);
              }),
          IconButton(
              tooltip: 'Pin',
              icon: const Icon(Icons.push_pin_outlined),
              onPressed: () {
                final cid = (_cidCtrl.text.trim().isNotEmpty
                        ? _cidCtrl.text.trim()
                        : _selectedCid) ??
                    '';
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
      // ---- lista de CIDs del nodo
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
              _svc.online
                  ? 'CID DEL NODO P2P (${_svc.localCids.length})'
                  : 'CID LOCALES (${_svc.localCids.length})',
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
              ? ListView(children: [
                  const SizedBox(height: 60),
                  Center(
                      child: Text(
                    _svc.online
                        ? 'agregá un archivo o pegá un CID externo para buscarlo en la red'
                        : 'agregá un archivo para generar CIDs',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  )),
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
                      : _accent.withValues(alpha: .7))),
        ),
      ),
    ]);
  }
}
