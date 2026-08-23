import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/rqbit.dart';

/// Configuración de sesión en memoria (se aplica al primer arranque).
class _SessionCfg {
  bool dht = true;
  bool upnp = true;
  int? downBps; // bytes/s, null = ilimitado
  int? upBps;
}

/// Cliente BitTorrent (rqbit embebido): magnets o archivos .torrent,
/// límites globales y por torrent, selección múltiple de archivos,
/// info + peers, DHT Kademlia y UPnP port forwarding.
class TorrentScreen extends StatefulWidget {
  const TorrentScreen({super.key});

  @override
  State<TorrentScreen> createState() => _TorrentScreenState();
}

class _TorrentScreenState extends State<TorrentScreen> {
  final _cfg = _SessionCfg();

  bool _booting = true;
  String? _error;
  String? _bootInfo;
  List<TorrentItem> _items = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      if (!RqbitBridge.running) {
        final docs = await getApplicationDocumentsDirectory();
        _bootInfo = await RqbitBridge.startSession(
          '${docs.path}/torrent',
          dht: _cfg.dht,
          upnp: _cfg.upnp,
          downBps: _cfg.downBps,
          upBps: _cfg.upBps,
        );
      }
      setState(() => _error = null);
      await _refresh();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (mounted) setState(() => _booting = false);
  }

  Future<void> _refresh() async {
    if (!RqbitBridge.running) return;
    try {
      final items = await RqbitBridge.list();
      if (mounted) setState(() => _items = items);
    } catch (_) {}
  }

  // ------------------------------------------------------------ agregar

  Future<void> _addFlow() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.content_paste_rounded),
            title: const Text('Pegar magnet / URL .torrent'),
            onTap: () => Navigator.pop(ctx, 'url'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('Abrir archivo .torrent'),
            onTap: () => Navigator.pop(ctx, 'file'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    // Límites por torrent opcionales (KB/s, vacío = hereda global).
    final limitsCtrl = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(choice == 'url'
            ? 'Pegar magnet / URL'
            : 'Límites del torrent'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (choice == 'url')
            TextField(
              controller: limitsCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'magnet:?xt=... o https://.../file.torrent'),
            )
          else
            const Text('Se abrirá el selector de archivos .torrent.'),
          const SizedBox(height: 12),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Límite ↓ KB/s (vacío = global):')),
          TextField(
            controller: TextEditingController(),
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(hintText: 'ilimitado'),
          ),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('Límite ↑ KB/s (vacío = global):')),
          TextField(
            keyboardType: TextInputType.number,
            decoration:
                const InputDecoration(hintText: 'ilimitado'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Agregar')),
        ],
      ),
    );
    if (proceed != true) return;

    int? parseKb(TextEditingController c) {
      final v = int.tryParse(c.text.trim());
      return v == null ? null : v * 1024;
    }

    try {
      int? id;
      if (choice == 'url') {
        final url = limitsCtrl.text.trim();
        if (url.isEmpty) return;
        id = await RqbitBridge.addUrl(url);
      } else {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['torrent'],
          withData: true,
        );
        final file = res?.files.single;
        if (file == null || file.bytes == null) return;
        id = await RqbitBridge.addTorrentFile(
          Uint8List.fromList(file.bytes!),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(id != null
                ? 'Agregado (id $id)'
                : 'Agregado (list-only)')));
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ERROR: $e')));
      }
    }
  }

  // ------------------------------------------------------- config sesión

  Future<void> _settingsDialog() async {
    final dDown = TextEditingController(
        text: _cfg.downBps == null ? '' : '${_cfg.downBps! ~/ 1024}');
    final dUp = TextEditingController(
        text: _cfg.upBps == null ? '' : '${_cfg.upBps! ~/ 1024}');
    var dht = _cfg.dht;
    var upnp = _cfg.upnp;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Configuración de sesión'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              title: const Text('Kademlia DHT (UDP)'),
              subtitle: const Text('encontrar peers sin tracker'),
              value: dht,
              onChanged: (v) => setD(() => dht = v),
            ),
            SwitchListTile(
              title: const Text('UPnP port forwarding'),
              subtitle: const Text('que te alcancen al compartir'),
              value: upnp,
              onChanged: (v) => setD(() => upnp = v),
            ),
            TextField(
              controller: dDown,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Límite global ↓ KB/s (vacío = ∞)'),
            ),
            TextField(
              controller: dUp,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Límite global ↑ KB/s (vacío = ∞)'),
            ),
            if (RqbitBridge.running)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('La sesión ya está corriendo: estos valores '
                    'se aplican la próxima vez que arranques la app.',
                    style: TextStyle(fontSize: 11, color: Colors.orange)),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      _cfg.dht = dht;
      _cfg.upnp = upnp;
      _cfg.downBps =
          int.tryParse(dDown.text.trim())?.clamp(1, 1 << 30) ?? null;
      _cfg.upBps = int.tryParse(dUp.text.trim())?.clamp(1, 1 << 30) ?? null;
    });
  }

  // -------------------------------------------------------------- acción

  Future<void> _doAction(TorrentItem t, String action) async {
    if (t.id == null) return;
    try {
      await RqbitBridge.action(t.id!, action);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ERROR: $e')));
      }
    }
  }

  void _openDetail(TorrentItem t) {
    if (t.id == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DetailSheet(item: t),
    );
  }

  // ----------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Torrents'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: RqbitBridge.running
                  ? Colors.green.withValues(alpha: .18)
                  : Colors.red.withValues(alpha: .18),
            ),
            child: Text(
              RqbitBridge.running ? 'sesión activa' : 'detenida',
              style: TextStyle(
                  fontSize: 11,
                  color: RqbitBridge.running ? Colors.green : Colors.red),
            ),
          ),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Sesión: DHT/UPnP/límites',
              onPressed: _settingsDialog),
          IconButton(
              icon: const Icon(Icons.add_link_rounded),
              tooltip: 'Agregar magnet/.torrent',
              onPressed: _addFlow),
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _refresh),
        ],
      ),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText('ERROR sesión: $_error',
                      style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: _items.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 110),
                          Center(
                              child: Text(
                            'Sin torrents.\nTocá ⛓ para pegar un magnet\n'
                            'o abrir un archivo .torrent',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38),
                          )),
                          if (_bootInfo != null)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(_bootInfo!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white24)),
                            ),
                        ])
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _tile(context, _items[i]),
                        ),
                )),
    );
  }

  Widget _tile(BuildContext ctx, TorrentItem t) {
    final total = t.totalBytes;
    final pct = total > 0 ? (t.progressBytes / total).clamp(0.0, 1.0) : null;
    final color = switch (t.state) {
      'live' => Colors.green,
      'paused' => Colors.orange,
      'error' => Colors.red,
      _ => Colors.blueGrey,
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: InkWell(
        onTap: () => _openDetail(t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(t.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold))),
                  PopupMenuButton<String>(
                    onSelected: (a) => _doAction(t, a),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'start', child: Text('Iniciar')),
                      PopupMenuItem(value: 'pause', child: Text('Pausar')),
                      PopupMenuItem(value: 'forget', child: Text('Olvidar')),
                      PopupMenuItem(
                          value: 'delete', child: Text('Borrar + archivos')),
                    ],
                  ),
                ]),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3)),
                const SizedBox(height: 6),
                Text(
                  '${t.state} · ${_fmt(t.progressBytes)}'
                  '${total > 0 ? " / ${_fmt(total)}" : ""}'
                  '${t.downBps > 0 ? " · ↓ ${_fmtSpeed(t.downBps)}" : ""}'
                  '${t.upBps > 0 ? " · ↑ ${_fmtSpeed(t.upBps)}" : ""}',
                  style: TextStyle(fontSize: 12, color: color),
                ),
                if (t.error != null)
                  Text(t.error!,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.red)),
              ]),
        ),
      ),
    );
  }

  static String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }

  static String _fmtSpeed(int bps) => '${_fmt(bps)}/s';
}

/// Detalle: info, archivos seleccionables (múltiple) y peers vivos.
class _DetailSheet extends StatefulWidget {
  final TorrentItem item;
  const _DetailSheet({required this.item});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  List<TorrentFile>? _files;
  List<bool>? _checked;
  List<TorrentPeer>? _peers;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.item.id!;
    try {
      final files = await RqbitBridge.files(id);
      final peers = await RqbitBridge.peers(id);
      if (!mounted) return;
      setState(() {
        _files = files;
        _checked = files.map((f) => f.included).toList();
        _peers = peers;
        _err = null;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _applySelection() async {
    final id = widget.item.id!;
    final sel = <int>[
      for (var i = 0; i < (_files?.length ?? 0); i++)
        if (_checked![i]) _files![i].index,
    ];
    try {
      await RqbitBridge.setOnlyFiles(id, sel);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Selección aplicada (${sel.length} archivos)')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ERROR: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      builder: (ctx, scroll) => Container(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(it.name,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx)),
          ]),
          Text(
            'id: ${it.id} · ${it.infoHash}\n'
            '${_fmt(it.progressBytes)} / ${_fmt(it.totalBytes)} '
            '(↑ subido ${_fmt(it.uploadedBytes)}) · estado: ${it.state}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const Divider(),
          Expanded(
            child: _err != null
                ? SelectableText('ERROR: $_err',
                    style: const TextStyle(color: Colors.red))
                : ListView(controller: scroll, children: [
                    Row(children: [
                      const Text('Archivos',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _applySelection,
                        icon: const Icon(Icons.check_circle_rounded,
                            size: 18),
                        label: const Text('Aplicar selección'),
                      ),
                    ]),
                    if (_files == null)
                      const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator()),
                    for (var i = 0; i < (_files?.length ?? 0); i++)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _checked?[i] ?? false,
                        onChanged: (v) =>
                            setState(() => _checked?[i] = v ?? false),
                        title: Text(_files![i].name,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(_fmt(_files![i].length),
                            style: const TextStyle(fontSize: 11)),
                      ),
                    const Divider(),
                    Text('Peers (${_peers?.length ?? 0})',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (_peers != null && _peers!.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(10),
                          child: Text('Sin peers conectados.',
                              style: TextStyle(color: Colors.white38))),
                    for (final p in _peers ?? const <TorrentPeer>[])
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.lan_rounded, size: 20),
                        title: Text(p.addr,
                            style: const TextStyle(fontSize: 12)),
                        subtitle: Text(
                            '${p.client ?? "?"} · ${p.state} · '
                            '↓ ${_fmt(p.downloaded)} · ↑ ${_fmt(p.uploaded)}',
                            style: const TextStyle(fontSize: 11)),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }

  static String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }
}
