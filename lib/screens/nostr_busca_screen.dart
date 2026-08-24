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
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PostsScreen(npub: p.npub),
                ));
              },
              icon: const Icon(Icons.article_rounded),
              label: const Text('Ver publicaciones'),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
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

/// Muro de un npub: sus publicaciones kind 1 con controles de
/// cantidad (N) y "desde cuándo" (fecha limpiable = sin límite).
class PostsScreen extends StatefulWidget {
  final String npub;
  const PostsScreen({super.key, required this.npub});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  final _svc = NostrBusca();
  final _limiteCtrl = TextEditingController(text: '20');
  final _relaysCtrl = TextEditingController();

  DateTime? _desde;
  List<rust.PostItem> _posts = [];
  String _estado = '';
  bool _busy = false;

  Future<void> _buscar() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await _svc.posts(
        npub: widget.npub,
        relays: _relaysCtrl.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        limite: int.tryParse(_limiteCtrl.text.trim()) ?? 20,
        desdeMs: _desde?.millisecondsSinceEpoch ?? 0,
      );
      setState(() {
        _posts = res;
        _estado = '${res.length} publicación(es)';
      });
    } catch (e) {
      setState(() => _estado = 'ERROR: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _elegirDesde() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _desde ?? DateTime.now(),
      firstDate: DateTime(2009),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _desde = d);
  }

  String _fecha(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publicaciones')),
      body: ListView(padding: const EdgeInsets.all(10), children: [
        TextField(
          controller: _relaysCtrl,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
              hintText:
                  'relays separados por coma (vacío = damus/nos.social/band)',
              isDense: true,
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Row(children: [
          SizedBox(
            width: 80,
            child: TextField(
              controller: _limiteCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                  labelText: 'N', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: _elegirDesde,
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Desde', border: OutlineInputBorder()),
                child: Text(_desde == null
                    ? 'sin límite'
                    : '${_desde!.day}/${_desde!.month}/${_desde!.year}'),
              ),
            ),
          ),
          if (_desde != null)
            IconButton(
              tooltip: 'quitar fecha',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => setState(() => _desde = null),
            ),
        ]),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _buscar,
          icon: const Icon(Icons.search_rounded),
          label: Text(_busy ? 'buscando…' : 'Buscar publicaciones'),
        ),
        const SizedBox(height: 4),
        Center(
            child: Text('npub: ${widget.npub}',
                style:
                    const TextStyle(fontSize: 9, fontFamily: 'monospace'))),
        if (_estado.isNotEmpty)
          Padding(
              padding: const EdgeInsets.all(6),
              child: Center(child: Text(_estado))),
        for (final p in _posts)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.indigoAccent.withValues(alpha: .08),
              border: Border.all(
                  color: Colors.indigoAccent.withValues(alpha: .4)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_fecha(p.fechaMs),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white38)),
                  const SizedBox(height: 4),
                  SelectableText(p.contenido,
                      style: const TextStyle(fontSize: 13)),
                ]),
          ),
      ]),
    );
  }

  @override
  void dispose() {
    _limiteCtrl.dispose();
    _relaysCtrl.dispose();
    super.dispose();
  }
}
