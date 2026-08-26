import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../build_info.dart';
import '../services/iroh_p2p.dart';

/// Iroh Chat · DM con dos paneles sobre nodos iroh REALES.
///
/// CHAT 1 (host):  arranca solo y genera SU ticket → [📋] copiar.
/// CHAT 2:         pegás ese ticket (o el de otro teléfono) → CONECTAR.
/// Un solo ticket en toda la UI: el del host. El cliente jamás crea uno.
class IrohChatScreen extends StatefulWidget {
  const IrohChatScreen({super.key});
  @override
  State<IrohChatScreen> createState() => _IrohChatScreenState();
}

class _IrohChatScreenState extends State<IrohChatScreen> {
  // ---- host (CHAT 1) --------------------------------------------------
  IrohP2p? _a;
  String? _ticketA;
  final List<Map<String, String>> _chatA = []; // {'de','texto'}

  // ---- cliente (CHAT 2) ----------------------------------------------
  IrohP2p? _b;
  final List<Map<String, String>> _chatB = [];
  final _ticketCtrl = TextEditingController();
  String? _errB;

  final _msgACtrl = TextEditingController();
  final _msgBCtrl = TextEditingController();
  Timer? _tick;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _arrancarHost();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _tick?.cancel();
    try { _a?.stop(); } catch (_) {}
    try { _b?.stop(); } catch (_) {}
    super.dispose();
  }

  Future<void> _arrancarHost() async {
    setState(() => _busy = true);
    try {
      final n = await IrohP2p.crear();
      await n.startServidor();
      final t = await n.chatTicket();
      if (!mounted) return;
      setState(() { _a = n; _ticketA = t; });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ERROR host: $e',
              style: const TextStyle(color: Colors.redAccent)),
          backgroundColor: Colors.black87));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// CHAT 2 se conecta al ticket pegado. Si es el de CHAT 1, el DM
  /// queda entero en este dispositivo; si es de otro teléfono, igual.
  Future<void> _conectarB() async {
    setState(() { _busy = true; _errB = null; });
    try {
      // sin frenos: limpiamos todo whitespace y mandamos a conectar
      final limpio = _ticketCtrl.text.replaceAll(RegExp(r'\s'), '');
      if (limpio.isEmpty) throw 'pegá el ticket primero';
      _b ??= await IrohP2p.crear();
      await _b!.startServidor();
      await _b!.chatConectar(limpio);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errB = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _poll() {
    if (_busy) return;
    for (final par in [_a, _b]) {
      final n = par;
      if (n == null) continue;
      n.chatLeer().then((nuevos) {
        if (nuevos.isEmpty || !mounted) return;
        setState(() {
          (identical(n, _a) ? _chatA : _chatB).addAll(
              nuevos.map((t) => {'de': 'par', 'texto': t}));
        });
      }).catchError((_) {});
    }
  }

  Future<void> _mandar({required bool host}) async {
    final ctrl = host ? _msgACtrl : _msgBCtrl;
    final texto = ctrl.text.trim();
    if (texto.isEmpty) return;
    final n = host ? _a : _b;
    final lista = host ? _chatA : _chatB;
    if (n == null) return;
    setState(() => _busy = true);
    try {
      await n.chatMandar(texto);
      setState(() {
        lista.add({'de': 'yo', 'texto': texto});
        ctrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '$e'.contains('sin chat activo')
          ? 'sin canal: pegá el ticket y tocá CONECTAR'
          : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg,
              style: const TextStyle(color: Colors.redAccent)),
          backgroundColor: Colors.black87));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iroh Chat · DM')),
      body: Column(children: [
        Expanded(child: _panelHost()),
        const Divider(height: 1),
        Expanded(child: _panelCliente()),
        Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('build $kSha',
                style: const TextStyle(fontSize: 8, color: Colors.white24))),
      ]),
    );
  }

  Widget _panelHost() => _panel(
        titulo: 'CHAT 1 · HOST',
        nodo: _a,
        ticket: _ticketA,
        chat: _chatA,
        msgCtrl: _msgACtrl,
        onEnviar: () => _mandar(host: true),
        extra: Row(children: [
          Expanded(
              child: SelectableText('ticket: ${_ticketA ?? 'generando…'}',
                  maxLines: 2,
                  style:
                      const TextStyle(fontSize: 9, fontFamily: 'monospace'))),
          IconButton(
              tooltip: 'copiar mi ticket',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: _ticketA == null
                  ? null
                  : () => Clipboard.setData(ClipboardData(text: _ticketA!))),
        ]),
      );

  Widget _panelCliente() {
    final conectado = _b?.chatActivo ?? false;
    return _panel(
        titulo: 'CHAT 2${conectado ? ' · canal vivo' : ''}',
        nodo: _b,
        chat: _chatB,
        msgCtrl: _msgBCtrl,
        onEnviar: () => _mandar(host: false),
        extra: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: TextField(
              controller: _ticketCtrl,
              maxLines: 2,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                  labelText: 'pegá el ticket del host',
                  hintText: 'endpoint…'),
            )),
            IconButton(
                tooltip: 'pegar desde portapapeles',
                icon: const Icon(Icons.content_paste_rounded, size: 20),
                onPressed: _pegarDePortapapeles),
            IconButton.filled(
                tooltip: 'conectar',
                onPressed: _busy ? null : _conectarB,
                icon: const Icon(Icons.link_rounded)),
          ]),
          if (_errB != null)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_errB!,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.redAccent))),
        ]));
  }

  Future<void> _pegarDePortapapeles() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text ?? '';
    if (txt.isEmpty) {
      setState(() => _errB = 'portapapeles vacío');
      return;
    }
    setState(() {
      _ticketCtrl.text = txt;
      _errB = null;
    });
  }

  Widget _panel({
    required String titulo,
    required IrohP2p? nodo,
    String? ticket,
    required List<Map<String, String>> chat,
    required TextEditingController msgCtrl,
    required VoidCallback onEnviar,
    required Widget extra,
  }) {
    return Card(
        margin: const EdgeInsets.all(6),
        child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Icon(nodo == null ? Icons.circle_outlined : Icons.sensors_rounded,
                    size: 14,
                    color: nodo == null ? Colors.white24 : Colors.greenAccent),
                const SizedBox(width: 6),
                Text(titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12)),
              ]),
              const SizedBox(height: 4),
              extra,
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                    width: double.infinity,
                    color: Colors.black.withValues(alpha: .5),
                    padding: const EdgeInsets.all(6),
                    child: chat.isEmpty
                        ? const Center(
                            child: Text('sin mensajes',
                                style: TextStyle(
                                    color: Colors.white24, fontSize: 10)))
                        : ListView.builder(
                            reverse: true,
                            itemCount: chat.length,
                            itemBuilder: (_, i) {
                              final m = chat[chat.length - 1 - i];
                              final mio = m['de'] == 'yo';
                              return Align(
                                  alignment: mio
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 5),
                                      constraints:
                                          const BoxConstraints(maxWidth: 240),
                                      decoration: BoxDecoration(
                                          color: mio
                                              ? Colors.cyan
                                                  .withValues(alpha: .18)
                                              : Colors.greenAccent
                                                  .withValues(alpha: .12),
                                          borderRadius:
                                              BorderRadius.circular(9)),
                                      child: SelectableText(m['texto'] ?? '',
                                          style: const TextStyle(
                                              fontSize: 12))));
                            })),
              ),
              Row(children: [
                Expanded(child: TextField(
                    controller: msgCtrl,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                        hintText: 'escribí…', isDense: true),
                    onSubmitted: (_) => onEnviar())),
                IconButton(
                    onPressed: nodo == null ? null : onEnviar,
                    icon: const Icon(Icons.send_rounded, size: 20)),
              ]),
            ])));
  }
}
