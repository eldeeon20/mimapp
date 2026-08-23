import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/nostr_chat.dart';
import '../services/nostr_keys.dart';

/// Test del chat NIP-17 simple (SIN observador): dos peers en el mismo
/// dispositivo conversan por relays públicos. Mitad superior = Peer 1,
/// mitad inferior = Peer 2.
class NostrDmTestScreen extends StatelessWidget {
  const NostrDmTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(child: _DmPane(label: 'PEER 1', color: Colors.cyanAccent)),
        Container(height: 2, color: Colors.white12),
        const Expanded(
            child: _DmPane(label: 'PEER 2', color: Colors.deepPurpleAccent)),
      ],
    );
  }
}

class _DmPane extends StatefulWidget {
  final String label;
  final Color color;

  const _DmPane({required this.label, required this.color});

  @override
  State<_DmPane> createState() => _DmPaneState();
}

class _DmPaneState extends State<_DmPane> {
  // Combo probado de Gtool: DM=nos.lol, lectura=primal.net.
  // nostr.wine es de pago y no entrega gift wraps anónimos.
  static const defaultDmRelays = ['wss://nos.lol'];
  static const defaultReadRelays = ['wss://relay.primal.net'];

  final _keys = NostrKeys();
  final _nsecCtrl = TextEditingController();
  final _peerCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _messages = <_Bubble>[];
  final _scroll = ScrollController();

  final _log = <String>[];

  NostrChat? _chat;
  Timer? _timer;
  String? _myNpub;
  String? _generatedNpub;
  bool _busy = false;
  String _error = '';

  bool get connected => _chat != null && _chat!.connected;

  @override
  void dispose() {
    _timer?.cancel();
    _chat?.close();
    _nsecCtrl.dispose();
    _peerCtrl.dispose();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _generateKeys() async {
    final secret = await _keys.generate();
    final nsec = await _keys.toNsec(secret);
    final npub = await _keys.toNpub(secret);
    setState(() {
      _nsecCtrl.text = nsec;
      _generatedNpub = npub;
      _error = '';
    });
  }

  Future<void> _connect() async {
    if (_busy) return;
    final npub = _peerCtrl.text.trim();
    if (npub.isEmpty) {
      setState(() => _error = 'Falta el npub del otro peer');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final nsec = _nsecCtrl.text.trim();
      final chat = NostrChat();
      await chat.init(
        nsec: nsec.isEmpty ? null : nsec,
        peerNpub: npub,
        dmRelays: defaultDmRelays,
        readRelays: defaultReadRelays,
        nSeconds: 3600,
        nLimit: 10,
      );
      final pk = await chat.publicKey();
      setState(() {
        _chat = chat;
        _myNpub = pk;
        _log.add('✓ iniciado · yo: $pk');
      });
      await _drainLogs();
      _startPolling();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _drainLogs() async {
    final c = _chat;
    if (c == null) return;
    try {
      final lines = await c.takeLogs();
      if (lines.isNotEmpty && mounted) {
        setState(() => _log.addAll(lines.take(50)));
      }
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (!connected) return;
    await _drainLogs();
    try {
      final msgs = await _chat!.poll(timeoutSecs: 2);
      if (msgs.isEmpty || !mounted) return;
      setState(() {
        for (final m in msgs) {
          _messages.add(_Bubble(text: m.content, mine: false));
        }
      });
      _scrollDown();
    } catch (e) {
      // antes: tragado. Ahora visible.
      if (mounted) setState(() => _error = 'poll: $e');
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || !connected) return;
    _msgCtrl.clear();
    setState(() => _messages.add(_Bubble(text: text, mine: true)));
    _scrollDown();
    try {
      await _chat!.send(text);
    } catch (e) {
      if (mounted) setState(() => _error = 'envío falló: $e');
    }
  }

  void _disconnect() {
    _timer?.cancel();
    _chat?.close();
    setState(() {
      _chat = null;
      _myNpub = null;
      _messages.clear();
    });
  }

  Widget _logPanel() {
    return ExpansionTile(
      title: Text('Registro (${_log.length})',
          style: const TextStyle(fontSize: 11)),
      initiallyExpanded: _error.isNotEmpty,
      children: [
        Container(
          constraints: const BoxConstraints(maxHeight: 130),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _log.length,
            itemBuilder: (_, i) => SelectableText(_log[i],
                style:
                    const TextStyle(fontSize: 9, color: Colors.white54)),
          ),
        ),
      ],
    );
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF050B18),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          _header(),
          if (!connected) _configForm() else ...[
            Expanded(child: _bubbles()),
            _inputRow(),
            _logPanel(),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    final statusColor = connected ? Colors.greenAccent : widget.color;
    final statusText = connected
        ? 'conectado · ${_short(_myNpub ?? '')}'
        : (_busy ? 'conectando…' : 'desconectado');
    return Row(
      children: [
        Container(width: 8, height: 8,
            decoration:
                BoxDecoration(color: statusColor, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(widget.label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: widget.color)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(statusText,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white54)),
        ),
        if (connected)
          IconButton(
            icon: const Icon(Icons.link_off, size: 16, color: Colors.redAccent),
            onPressed: _disconnect,
            tooltip: 'Desconectar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
      ],
    );
  }

  Widget _configForm() {
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.only(top: 4),
        children: [
          TextField(
            controller: _nsecCtrl,
            obscureText: true,
            style: const TextStyle(fontSize: 11),
            decoration: InputDecoration(
              labelText: 'Mi secreto (nsec o hex; vacío = generar)',
              labelStyle: const TextStyle(fontSize: 10),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(Icons.auto_awesome,
                    size: 18, color: widget.color),
                tooltip: 'Generar keys nuevas (en memoria)',
                onPressed: _generateKeys,
              ),
            ),
          ),
          if (_generatedNpub != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Row(children: [
                const Text('npub generada: ',
                    style: TextStyle(fontSize: 9, color: Colors.white38)),
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: _generatedNpub!)),
                    child: Text(_short(_generatedNpub!),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 9, color: Colors.greenAccent)),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 6),
          TextField(
            controller: _peerCtrl,
            style: const TextStyle(fontSize: 11),
            decoration: InputDecoration(
              labelText: 'npub del otro peer',
              labelStyle: const TextStyle(fontSize: 10),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: defaultRelays
                .map((r) => Chip(
                      label: Text(r.replaceAll('wss://', ''),
                          style: const TextStyle(fontSize: 8)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white.withValues(alpha: .04),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link, size: 16),
            label: const Text('Conectar'),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(34)),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 9, color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }

  Widget _bubbles() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        return Align(
          alignment:
              m.mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.62),
            decoration: BoxDecoration(
              color: m.mine ? const Color(0xFF2B7CD3) : const Color(0xFF23232A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(m.text,
                style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
        );
      },
    );
  }

  Widget _inputRow() {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _msgCtrl,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Mensaje…',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _send(),
        ),
      ),
      IconButton(
        icon: Icon(Icons.send_rounded, size: 18, color: widget.color),
        onPressed: _send,
      ),
    ]);
  }
}

class _Bubble {
  final String text;
  final bool mine;
  _Bubble({required this.text, required this.mine});
}

String _short(String s) =>
    s.length <= 20 ? s : '${s.substring(0, 10)}…${s.substring(s.length - 6)}';
