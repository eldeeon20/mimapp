import 'dart:io';

import 'package:flutter/material.dart';
import '../ai/laurelia_chat.dart';

/// Pantalla standalone de Laurelia AI: chat sin dependencia de Lua.
class AiScreen extends StatefulWidget {
  final LaureliaChat laurelia;
  const AiScreen({super.key, required this.laurelia});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _promptCtrl = TextEditingController();
  final _messages = <_Msg>[];
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    widget.laurelia.onProgress = (msg) {
      if (mounted) setState(() => _status = msg);
    };
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _promptCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    _promptCtrl.clear();

    setState(() {
      _messages.add(_Msg(text, true));
      _busy = true;
    });

    try {
      final reply = await widget.laurelia.generate(text, maxNewTokens: 200);
      setState(() {
        _messages.add(_Msg(reply.isEmpty ? '(vacío)' : reply, false));
      });
    } catch (e) {
      setState(() {
        _messages.add(_Msg('Error: $e', false));
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _downloadAndLoad() async {
    setState(() => _busy = true);
    try {
      await widget.laurelia.download();
      await widget.laurelia.load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = widget.laurelia.loaded;
    return Column(
      children: [
        // Status bar
        if (_status.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.grey[900],
            child: Text(_status,
                style: const TextStyle(fontSize: 11, color: Colors.greenAccent)),
          ),
        // Model info
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[800],
          child: Row(
            children: [
              Icon(
                loaded ? Icons.check_circle : Icons.cloud_download,
                size: 16,
                color: loaded ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                loaded
                    ? 'Modelo: ${widget.laurelia.modelName} (cargado)'
                    : 'Modelo: ${widget.laurelia.modelName} (no cargado)',
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: _busy ? null : _downloadAndLoad,
                child: Text(loaded ? 'Recargar' : 'Descargar + Cargar'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: () async {
                  await widget.laurelia.unload();
                  await widget.laurelia.load();
                  setState(() {});
                },
                tooltip: 'Recargar modelo',
              ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text('Escribí un prompt y tocá Enviar',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    return Align(
                      alignment:
                          m.user ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        constraints:
                            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                        decoration: BoxDecoration(
                          color: m.user ? Colors.indigo[700] : Colors.grey[800],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(m.text, style: const TextStyle(fontSize: 13)),
                      ),
                    );
                  },
                ),
        ),
        // Input
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptCtrl,
                  decoration: InputDecoration(
                    hintText: 'Prompt…',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    enabled: !_busy,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: (_busy || !loaded) ? null : _send,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Enviar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Msg {
  final String text;
  final bool user;
  _Msg(this.text, this.user);
}
