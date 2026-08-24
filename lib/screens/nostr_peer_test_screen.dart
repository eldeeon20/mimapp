import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/nostr_keys.dart';
import '../services/nostr_peer_chat.dart';
import '../widgets/relay_editor.dart';

/// Test del chat con observador (patrón Mostro / clave compartida ECDH):
/// Participante A y Participante B conversan por relays; un Observador con
/// la shared key puede LEER todo pero no enviar.
class NostrPeerTestScreen extends StatelessWidget {
  const NostrPeerTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Participante A'),
              Tab(text: 'Participante B'),
              Tab(text: 'Observador'),
            ],
            labelStyle: TextStyle(fontSize: 12),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _ParticipantPane(label: 'A', color: Colors.cyanAccent),
                _ParticipantPane(label: 'B', color: Colors.deepPurpleAccent),
                _ObserverPane(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Combo probado de Gtool (589 msgs recibidos): nos.lol + primal.net.
// nostr.wine es de pago y no entrega gift wraps anónimos; damus a veces
// filtra kind 1059 sin auth.
const _defaultRelays = [
  'wss://nos.lol',
  'wss://relay.primal.net',
];

class _ParticipantPane extends StatefulWidget {
  final String label;
  final Color color;

  const _ParticipantPane({required this.label, required this.color});

  @override
  State<_ParticipantPane> createState() => _ParticipantPaneState();
}

class _ParticipantPaneState extends State<_ParticipantPane>
    with AutomaticKeepAliveClientMixin {
  final _keys = NostrKeys();
  final _secretCtrl = TextEditingController();
  final _peerCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _messages = <_Bubble>[];
  final _scroll = ScrollController();

  // Límites de consulta ajustables (igual que el DM NIP-17).
  final _desdeCtrl = TextEditingController(text: '24');
  final _limiteCtrl = TextEditingController(text: '50');

  NostrPeerChat? _chat;
  Timer? _timer;
  String? _sharedKey;
  String? _generatedNpub; // pub visible al generar keys
  List<String> _relays = List.of(_defaultRelays); // editable
  bool _busy = false;
  String _error = '';
  final _log = <String>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _timer?.cancel();
    _chat?.close();
    _secretCtrl.dispose();
    _peerCtrl.dispose();
    _msgCtrl.dispose();
    _desdeCtrl.dispose();
    _limiteCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _generateKeys() async {
    final secret = await _keys.generate();
    final nsec = await _keys.toNsec(secret);
    final npub = await _keys.toNpub(secret);
    setState(() {
      _secretCtrl.text = nsec;
      _generatedNpub = npub;
      _error = '';
    });
  }

  Future<void> _connect() async {
    if (_busy) return;
    if (_secretCtrl.text.trim().isEmpty || _peerCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Completá tu secreto y el npub del otro peer');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final chat = await NostrPeerChat.create();
      final desdeH = int.tryParse(_desdeCtrl.text.trim()) ?? 24;
      final limite = int.tryParse(_limiteCtrl.text.trim()) ?? 50;
      final shared = await chat.initParticipant(
        senderSecret: _secretCtrl.text.trim(),
        receiverPubkey: _peerCtrl.text.trim(),
        relays: _relays,
        nLimit: limite.clamp(1, 500),
        since: desdeH <= 0 ? 0 : desdeH * 3600,
      );
      // Ventana de frescura del poll alineada con "Desde".
      await chat.setWindow(desdeH <= 0 ? 86400 * 365 : desdeH * 3600);
      // FIX CRÍTICO: antes el chat nunca se guardaba → poll no hacía nada
      // y send explotaba en silencio con null-check.
      setState(() {
        _chat = chat;
        _sharedKey = shared;
        _log.add('✓ conectado como participante · '
            'desde ${desdeH <= 0 ? "TODO" : "${desdeH}h"} · límite ${limite.clamp(1, 500)}');
      });
      await _drainLogs(chat);
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _drainLogs(NostrPeerChat chat) async {
    try {
      final lines = await chat.takeLogs();
      if (lines.isNotEmpty && mounted) {
        setState(() => _log.addAll(lines.take(50)));
      }
    } catch (_) {}
  }

  Future<void> _poll() async {
    final chat = _chat;
    if (chat == null) return;
    await _drainLogs(chat);
    try {
      final msgs = await chat.poll();
      if (msgs.isEmpty || !mounted) return;
      setState(() {
        for (final m in msgs) {
          _messages.add(_Bubble(text: m.content, mine: false));
        }
      });
      _scrollDown();
    } catch (e) {
      // antes: tragado. Ahora visible en rojo.
      if (mounted) setState(() => _error = 'poll: $e');
    }
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    setState(() => _messages.add(_Bubble(text: text, mine: true)));
    _scrollDown();
    try {
      await _chat!.send(text);
    } catch (e) {
      if (mounted) setState(() => _error = 'envío falló: $e');
    }
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
    super.build(context);
    final connected = _chat != null && _sharedKey != null;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: connected ? _chatArea() : _configForm(),
    );
  }

  Widget _configForm() {
    return ListView(
      children: [
        TextField(
          controller: _secretCtrl,
          obscureText: true,
          style: const TextStyle(fontSize: 11),
          decoration: InputDecoration(
            labelText:
                'Secreto de ${widget.label} (nsec o hex)',
            labelStyle: const TextStyle(fontSize: 10),
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(Icons.auto_awesome, size: 18, color: widget.color),
              tooltip: 'Generar keys (en memoria)',
              onPressed: _generateKeys,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_generatedNpub != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Row(children: [
              Text('npub de ${widget.label}: ',
                  style: TextStyle(fontSize: 9, color: Colors.white38)),
              Expanded(
                child: InkWell(
                  onTap: () => Clipboard.setData(
                      ClipboardData(text: _generatedNpub!)),
                  child: Text(_short(_generatedNpub!),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9, color: Colors.greenAccent)),
                ),
              ),
            ]),
          ),
        TextField(
          controller: _peerCtrl,
          style: const TextStyle(fontSize: 11),
          decoration: const InputDecoration(
            labelText: 'npub del otro participante',
            labelStyle: TextStyle(fontSize: 10),
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        RelayEditor(
          initial: _relays,
          onChanged: (v) => setState(() => _relays = List.of(v)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _desdeCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                labelText: 'Desde (h atrás)',
                labelStyle: TextStyle(fontSize: 10),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _limiteCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                labelText: 'Límite msgs',
                labelStyle: TextStyle(fontSize: 10),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link, size: 16),
          label: const Text('Conectar como participante'),
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
          ),
      ],
    );
  }

  Widget _chatArea() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.key_rounded,
              size: 14, color: Colors.greenAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text('shared: ${_short(_sharedKey ?? '')}',
                style:
                    const TextStyle(fontSize: 9, color: Colors.greenAccent)),
          ),
          InkWell(
            onTap: () =>
                Clipboard.setData(ClipboardData(text: _sharedKey ?? '')),
            child: const Icon(Icons.copy, size: 14, color: Colors.greenAccent),
          ),
        ]),
      ),
      Expanded(child: _bubbles()),
      Row(children: [        Expanded(
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
      ]),
      _ticker(),
      _logPanel(),
    ]);
  }

  /// Última línea del log siempre visible (heartbeat sin abrir el Registro).
  Widget _ticker() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        _log.isEmpty ? '' : _log.last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9,
          fontFamily: 'monospace',
          color: _log.last.startsWith('✗')
              ? Colors.redAccent
              : (_log.last.startsWith('✓')
                  ? Colors.greenAccent
                  : Colors.white38),
        ),
      ),
    );
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

  Widget _bubbles() {
    return ListView.builder(
      controller: _scroll,
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
                maxWidth: MediaQuery.of(context).size.width * 0.7),
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
}

class _ObserverPane extends StatefulWidget {
  const _ObserverPane();

  @override
  State<_ObserverPane> createState() => _ObserverPaneState();
}

class _ObserverPaneState extends State<_ObserverPane>
    with AutomaticKeepAliveClientMixin {
  final _keyCtrl = TextEditingController();
  final _messages = <String>[];
  List<String> _relays = List.of(_defaultRelays); // editable
  // Límites del observador también ajustables.
  final _desdeCtrl = TextEditingController(text: '24');
  final _limiteCtrl = TextEditingController(text: '50');
  NostrPeerChat? _chat;
  Timer? _timer;
  bool _busy = false;
  String _error = '';
  final _log = <String>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _timer?.cancel();
    _chat?.close();
    _keyCtrl.dispose();
    _desdeCtrl.dispose();
    _limiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    if (_keyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Pegá la shared key (la copiás de A o B)');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final chat = await NostrPeerChat.create();
      final desdeH = int.tryParse(_desdeCtrl.text.trim()) ?? 24;
      final limite = int.tryParse(_limiteCtrl.text.trim()) ?? 50;
      await chat.initObserver(
        sharedKeyHex: _keyCtrl.text.trim(),
        relays: _relays,
        nLimit: limite.clamp(1, 500),
        since: desdeH <= 0 ? 0 : desdeH * 3600,
      );
      await chat.setWindow(desdeH <= 0 ? 86400 * 365 : desdeH * 3600);
      setState(() {
        _chat = chat;
        _log.add('✓ observador conectado (solo lectura) · '
            'desde ${desdeH <= 0 ? "TODO" : "${desdeH}h"} · límite ${limite.clamp(1, 500)}');
      });
      await _drainLogs(chat);
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _drainLogs(NostrPeerChat chat) async {
    try {
      final lines = await chat.takeLogs();
      if (lines.isNotEmpty && mounted) {
        setState(() => _log.addAll(lines.take(50)));
      }
    } catch (_) {}
  }

  Future<void> _poll() async {
    final chat = _chat;
    if (chat == null) return;
    await _drainLogs(chat);
    try {
      final msgs = await chat.poll();
      if (msgs.isEmpty || !mounted) return;
      setState(() {
        for (final m in msgs) {
          _messages.add('${_short(m.pubkey)}: ${m.content}');
        }
      });
    } catch (e) {
      // antes: tragado. Ahora visible.
      if (mounted) setState(() => _error = 'poll: $e');
    }
  }

  Widget _logPanel() {
    return ExpansionTile(
      title: Text('Registro (${_log.length})',
          style: const TextStyle(fontSize: 11)),
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

  Widget _tickerObs() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        _log.isEmpty ? '' : _log.last,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9,
          fontFamily: 'monospace',
          color: _log.last.startsWith('✗')
              ? Colors.redAccent
              : (_log.last.startsWith('✓')
                  ? Colors.greenAccent
                  : Colors.white38),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final connected = _chat != null;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: connected
          ? ListView.builder(
              itemCount: _messages.length + 3,
              itemBuilder: (_, i) {
                if (i == _messages.length + 2) return _logPanel();
                if (i == _messages.length + 1) return _tickerObs();
                if (i == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.visibility_rounded,
                          size: 14, color: Colors.deepPurpleAccent),
                      const SizedBox(width: 6),
                      Text('observando (${_messages.length} mensajes)',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white60)),
                    ]),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(_messages[i - 1],
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.white70)),
                );
              },
            )
          : ListView(children: [
              TextField(
                controller: _keyCtrl,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Shared key (hex)',
                  labelStyle: TextStyle(fontSize: 10),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'El observador solo puede LEER los mensajes cifrados con '
                'esa shared key. No puede escribir ni ver identidades.',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
              const SizedBox(height: 12),
              RelayEditor(
                initial: _relays,
                onChanged: (v) => setState(() => _relays = List.of(v)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _desdeCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(
                      labelText: 'Desde (h atrás)',
                      labelStyle: TextStyle(fontSize: 10),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _limiteCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 11),
                    decoration: const InputDecoration(
                      labelText: 'Límite msgs',
                      labelStyle: TextStyle(fontSize: 10),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: _busy
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.visibility_rounded, size: 16),
                label: const Text('Conectar observador'),
              ),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.redAccent)),
                ),
            ]),
    );
  }
}

class _Bubble {
  final String text;
  final bool mine;
  _Bubble({required this.text, required this.mine});
}

String _short(String s) =>
    s.length <= 24 ? s : '${s.substring(0, 14)}…${s.substring(s.length - 8)}';
