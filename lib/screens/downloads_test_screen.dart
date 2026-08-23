import 'package:flutter/material.dart';

import '../lua/downloads/download_manager.dart';

/// Test del menú central: pegar link de descarga y probar el pipeline real
/// (streaming Dart puro + notificación con MB en vivo + cancelar).
class DownloadsTestScreen extends StatefulWidget {
  const DownloadsTestScreen({super.key});

  @override
  State<DownloadsTestScreen> createState() => _DownloadsTestScreenState();
}

class _DownloadsTestScreenState extends State<DownloadsTestScreen> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _askWhere = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text =
        'https://huggingface.co/ScortexIA/laurelia/resolve/laurelia-llm/tokenizer.json';
  }

  Future<void> _start() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    await DownloadManager.instance.start(
      url,
      fileName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      askWhere: _askWhere,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = DownloadManager.instance.tasks;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          TextField(
            controller: _urlCtrl,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Link de descarga',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Nombre (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('preguntar dónde',
                style: TextStyle(fontSize: 11)),
            Switch(value: _askWhere, onChanged: (v) => setState(() => _askWhere = v)),
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Descargar'),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: AnimatedBuilder(
          animation: DownloadManager.instance,
          builder: (_, __) => tasks.isEmpty
              ? const Center(
                  child: Text('sin descargas activas',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: tasks.length,
                  itemBuilder: (_, i) => _tile(tasks[i]),
                ),
        ),
      ),
    ]);
  }

  Widget _tile(DownloadTask t) {
    final color = switch (t.status) {
      DlStatus.ok => Colors.greenAccent,
      DlStatus.error => Colors.redAccent,
      DlStatus.cancelada => Colors.orangeAccent,
      DlStatus.activa => Colors.cyanAccent,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF0B1226),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: .4))),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_iconFor(t.status), size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t.url.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            Text('${DownloadManager.pct(t)} · ${t.mb}',
                style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: color)),
            if (t.status == DlStatus.activa)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => DownloadManager.instance.cancel(t.id),
                tooltip: 'Cancelar',
              ),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: t.total > 0 ? t.progress : null,
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 4),
          Text(t.error.isNotEmpty ? t.error : t.path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: Colors.white38)),
        ]),
      ),
    );
  }

  IconData _iconFor(DlStatus s) => switch (s) {
        DlStatus.ok => Icons.check_circle_rounded,
        DlStatus.error => Icons.cancel_rounded,
        DlStatus.cancelada => Icons.remove_circle_outline_rounded,
        DlStatus.activa => Icons.downloading_rounded,
      };
}
