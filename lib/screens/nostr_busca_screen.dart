import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/nostr_busca.dart' as rust;
import '../services/nostr_busca.dart';
import '../widgets/relay_editor.dart';

/// Pantalla de búsqueda de usuarios Nostr.
/// Un solo campo: si pegás un npub/nprofile o hex de 64 → modo B1
/// (perfil directo); si escribís texto → B2 (NIP-50 en relays que lo
/// soportan). Tap en resultado abre la ficha completa.
class NostrBuscaScreen extends StatefulWidget {
  const NostrBuscaScreen({super.key});

  @override
  State<NostrBuscaScreen> createState() => _NostrBuscaScreenState();
}

const _kRelaysDefault = [
  'wss://relay.damus.io',
  'wss://nos.social',
  'wss://relay.nostr.band',
  'wss://search.nos.today',
];

class _NostrBuscaScreenState extends State<NostrBuscaScreen> {
  final _busca = NostrBusca();
  final _qCtrl = TextEditingController();

  List<String> _relays = [..._kRelaysDefault];
  List<rust.PerfilItem> _resultados = [];
  bool _corriendo = false;
  String _estado = '';

  bool get _esClave {
    final v = _qCtrl.text.trim().toLowerCase();
    return v.startsWith('npub1') ||
        v.startsWith('nprofile1') ||
        RegExp(r'^[0-9a-f]{64}$').hasMatch(v);
  }

  Future<void> _run() async {
    if (_corriendo) return;
    final q = _qCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _estado = 'escribí un nombre o pegá un npub');
      return;
    }
    setState(() {
      _corriendo = true;
      _estado = _esClave ? 'trayendo perfil…' : 'buscando "$q"…';
      _resultados = [];
    });
    try {
      if (_esClave) {
        final p = await _busca.perfil(npub: q, relays: _relays);
        setState(() {
          _resultados = [p];
          _estado =
              p.name.isEmpty && p.displayName.isEmpty && p.about.isEmpty
                  ? 'sin metadata para ese npub'
                  : 'perfil listo';
        });
      } else {
        final r = await _busca.buscar(query: q, relays: _relays);
        setState(() => _estado = '${r.length} resultado(s)');
        _resultados = r;
      }
    } catch (e) {
      setState(() => _estado = 'ERROR: $e');
    } finally {
      if (mounted) setState(() => _corriendo = false);
    }
  }

  void _ficha(rust.PerfilItem p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 42,
                backgroundImage:
                    p.picture.isNotEmpty ? NetworkImage(p.picture) : null,
                child: p.picture.isEmpty
                    ? Text(
                        (p.displayName.isNotEmpty
                                ? p.displayName
                                : p.name)
                            .toUpperCase()
                            .characters
                            .first,
                        style: const TextStyle(fontSize: 30),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                p.displayName.isNotEmpty ? p.displayName : p.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (p.nip05.isNotEmpty)
              Center(
                child: Text('✓ ${p.nip05}',
                    style: TextStyle(color: Colors.greenAccent[200])),
              ),
            const SizedBox(height: 10),
            if (p.about.isNotEmpty) Text(p.about),
            const SizedBox(height: 14),
            SelectableText(p.npub,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: p.npub));
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copiar npub'),
            ),
          ],
        ),
      ),
    );
  }

  String _titulo(rust.PerfilItem p) =>
      p.displayName.isNotEmpty ? p.displayName : (p.name.isNotEmpty ? p.name : 'sin nombre');

  String _npubCorto(String npub) => npub.length <= 21
      ? npub
      : '${npub.substring(0, 10)}…${npub.substring(npub.length - 6)}';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _qCtrl,
                decoration: const InputDecoration(
                  hintText: 'nombre… o pegá un npub / nprofile / hex64',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (_) => _run(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _corriendo ? null : _run,
              icon: _corriendo
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_forward_rounded),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(
                child: Text(_estado,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12))),
          ]),
        ),
        RelayEditor(
          initial: _relays,
          onChanged: (r) => setState(() => _relays = [...r]),
        ),
        const Divider(height: 16),
        Expanded(
          child: _resultados.isEmpty
              ? Center(
                  child: Text('sin resultados',
                      style: TextStyle(color: Colors.grey[600])))
              : ListView.separated(
                  itemCount: _resultados.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = _resultados[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: p.picture.isNotEmpty
                            ? NetworkImage(p.picture)
                            : null,
                        child: p.picture.isEmpty
                            ? Text(_titulo(p).toUpperCase().characters.first)
                            : null,
                      ),
                      title: Text(_titulo(p)),
                      subtitle: Text(
                        p.about.isNotEmpty ? p.about : _npubCorto(p.npub),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: p.nip05.isNotEmpty
                          ? Icon(Icons.verified_rounded,
                              size: 18, color: Colors.greenAccent[200])
                          : null,
                      onTap: () => _ficha(p),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }
}
