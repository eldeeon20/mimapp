import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/iroh_p2p.dart';

/// Chat P2P directo estilo DM, sobre iroh (sin servidor).
/// peer 1 inicia y comparte su ticket · peer 2 lo pega → canal vivo.
class IrohChatScreen extends StatefulWidget {
  const IrohChatScreen({super.key});
  @override
  State<IrohChatScreen> createState() => _IrohChatScreenState();
}

class _IrohChatScreenState extends State<IrohChatScreen> {
  final _nodo = IrohP2p();
  final _ticketCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _tick;
  bool _busy = false;
  bool? _on;
  String? _miId;
  String? _miTicket;
  final List<Map<String, String>> _chat = []; // {'de','texto'}
  String _estado = 'nodo apagado';

  @override
  void initState() {
    super.initState();
    _arrancar();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _tick?.cancel();
    try { _nodo.stop(); } catch (_) {}
    super.dispose();
  }

  Future<void> _arrancar() async {
    setState(() => _busy = true);
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/iroh_chat').createTempSync();
      await _nodo.startServidor(dir.path);
      final id = await _nodo.nodeId();
      final t = await _nodo.chatTicket();
      if (!mounted) return;
      setState(() { _on = true; _miId = id; _miTicket = t; _estado = 'nodo arriba'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _on = false; _estado = 'error: $e'; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    if (_on != true || _busy) return;
    try {
      final nuevos = await _nodo.chatLeer();
      if (nuevos.isNotEmpty && mounted) {
        setState(() => _chat
            .addAll(nuevos.map((t) => {'de': 'par', 'texto': t})));
        _alFondo();
      }
      final activo = _nodo.chatActivo;
      if (mounted && activo != (_estado == 'canal vivo')) {
        setState(() => _estado = activo ? 'canal vivo' : 'sin canal');
      }
    } catch (_) {}
  }

  void _alFondo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _conectar() => _guard(() async {
        await _nodo.chatConectar(_ticketCtrl.text.trim());
        setState(() => _estado = 'canal vivo');
      });

  Future<void> _mandar() => _guard(() async {
        final t = _msgCtrl.text.trim();
        if (t.isEmpty) return;
        await _nodo.chatMandar(t);
        setState(() => _chat.add({'de': 'yo', 'texto': t}));
        _msgCtrl.clear();
        _alFondo();
      });

  Future<void> _guard(Future<void> Function() f) async {
    setState(() => _busy = true);
    try { await f(); } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ERROR: $e',
              style: const TextStyle(color: Colors.redAccent)),
              backgroundColor: Colors.black87));
      if (_estado.startsWith('error') == false) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _on == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Iroh Chat · P2P')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(on ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                    size: 18,
                    color: on ? Colors.greenAccent : Colors.white38),
                const SizedBox(width: 6),
                Expanded(child: Text(_estado,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                IconButton(
                    onPressed: _busy ? null : _arrancar,
                    icon: const Icon(Icons.refresh_rounded)),
              ]),
              if (_miId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText('id: $_miId',
                      style: const TextStyle(
                          fontSize: 9.5, fontFamily: 'monospace')),
                ),
              if (_miTicket != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                      child: SelectableText(_miTicket!,
                          maxLines: 3,
                          style: const TextStyle(
                              fontSize: 9, fontFamily: 'monospace'))),
                  IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: 'copiar mi ticket',
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _miTicket!))),
                ]),
                const Text('↑ pasaselo al otro dispositivo',
                    style: TextStyle(fontSize: 10, color: Colors.white38)),
              ],
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _ticketCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'pegá el ticket del par',
                    hintText: 'endpoint…'),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                  onPressed: _busy ? null : _conectar,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('CONECTAR')),
            ]),
          ),
        ),
        // hilo de mensajes
        Container(
          height: MediaQuery.of(context).size.height * .45,
          width: double.infinity,
          color: Colors.black.withValues(alpha: .55),
          padding: const EdgeInsets.all(8),
          child: _chat.isEmpty
              ? const Center(
                  child: Text('sin mensajes todavía',
                      style:
                          TextStyle(color: Colors.white24, fontSize: 11)))
              : ListView.builder(
                  controller: _scroll,
                  itemCount: _chat.length,
                  itemBuilder: (_, i) {
                    final m = _chat[i];
                    final mio = m['de'] == 'yo';
                    return Align(
                      alignment: mio
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        constraints: const BoxConstraints(maxWidth: 300),
                        decoration: BoxDecoration(
                            color: mio
                                ? Colors.cyan.withValues(alpha: .18)
                                : Colors.greenAccent.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(10)),
                        child: SelectableText(m['texto'] ?? '',
                            style: const TextStyle(fontSize: 13)),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _msgCtrl,
            decoration: const InputDecoration(labelText: 'mensaje'),
            onSubmitted: (_) => _mandar(),
          )),
          IconButton.filled(
              onPressed: _busy ? null : _mandar,
              icon: const Icon(Icons.send_rounded)),
        ]),
      ]),
    );
  }
}
