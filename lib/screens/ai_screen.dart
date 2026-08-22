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
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    await widget.laurelia.loadHistory();
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(widget.laurelia.history
            .map((h) => _Msg(h['content']!, h['role'] == 'user')));
    });
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar historial'),
        content: const Text(
            'Se borran todos los mensajes del chat. ¿Continuar?'),
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
    await widget.laurelia.clearHistory();
    if (mounted) setState(() => _messages.clear());
  }

  Future<void> _deleteModel() async {
    final name = widget.laurelia.model;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar modelo $name'),
        content: const Text(
            'Se borra el checkpoint descargado del dispositivo. '
            'Podrás descargarlo de nuevo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.laurelia.deleteModel(name);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    widget.laurelia.addHistory('user', text);

    try {
      final reply = await widget.laurelia.generate(text, maxNewTokens: 200);
      final clean = reply.isEmpty ? '(vacío)' : reply;
      widget.laurelia.addHistory('assistant', clean);
      if (mounted) {
        setState(() {
          _messages.add(_Msg(clean, false));
        });
      }
    } catch (e) {
      widget.laurelia
          .addHistory('assistant', 'Error: $e');
      if (mounted) {
        setState(() {
          _messages.add(_Msg('Error: $e', false));
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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

  Future<void> _switchModel(String name) async {
    if (name == widget.laurelia.model) return;
    await widget.laurelia.setModel(name);
    if (mounted) setState(() {});
    // Recargar historial del chat (es único, se mantiene).
    if (mounted) setState(() => _status = widget.laurelia.status);
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: Colors.grey[800],
          child: Row(
            children: [
              Icon(
                loaded ? Icons.check_circle : Icons.cloud_download,
                size: 16,
                color: loaded ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 6),
              // Selector de modelo: base / fine
              DropdownButton<String>(
                value: widget.laurelia.model,
                underline: const SizedBox.shrink(),
                isDense: true,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                dropdownColor: Colors.grey[850],
                items: LaureliaChat.models
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(m == 'fine' ? 'Laurelia Fine' : 'Laurelia Base'),
                        ))
                    .toList(),
                onChanged: _busy ? null : (v) => _switchModel(v!),
              ),
              Text(
                loaded ? ' · cargado' : ' · no cargado',
                style: TextStyle(
                    fontSize: 11,
                    color: loaded ? Colors.green : Colors.orange),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: _busy ? null : _downloadAndLoad,
                child: Text(loaded ? 'Recargar' : 'Descargar',
                    style: const TextStyle(fontSize: 11)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await widget.laurelia.unload();
                          await widget.laurelia.load();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                tooltip: 'Recargar modelo',
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever,
                    size: 18, color: Colors.redAccent),
                onPressed: _busy ? null : _deleteModel,
                tooltip: 'Eliminar modelo del dispositivo',
              ),
              IconButton(
                icon:
                    const Icon(Icons.delete_sweep, size: 18, color: Colors.amber),
                onPressed: _clearChat,
                tooltip: 'Borrar historial del chat',
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
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78),
                        decoration: BoxDecoration(
                          color: m.user
                              ? const Color(0xFF2B7CD3)
                              : const Color(0xFF2A2A2E),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(14),
                            topRight: const Radius.circular(14),
                            bottomLeft: Radius.circular(m.user ? 14 : 4),
                            bottomRight: Radius.circular(m.user ? 4 : 14),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          m.text,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white),
                        ),
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
