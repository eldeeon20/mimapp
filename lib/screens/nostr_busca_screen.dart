import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/nostr_busca.dart' as rust;
import '../services/nostr_busca.dart';
import '../services/relay_info.dart';
import '../widgets/relay_editor.dart';
import 'posts_screen.dart';

/// Pantalla de búsqueda de usuarios Nostr.
/// Un solo campo: si pegás un npub/nprofile o hex de 64 → modo B1
/// (perfil directo); si escribís texto → B2 (NIP-50 en relays que lo
/// soportan). Tap en resultado abre la ficha completa.
class NostrBuscaScreen extends StatefulWidget {
  const NostrBuscaScreen({super.key});

  @override
  State<NostrBuscaScreen> createState() => _NostrBuscaScreenState();
}

/// Editor arranca vacío: sin nada hardcodeado a la vista.
/// (Si está vacío, el lado Rust usa sus propios relays para que la
/// consulta igual funcione; eso no se muestra en ningún lado.)

class _NostrBuscaScreenState extends State<NostrBuscaScreen> {
  final _busca = NostrBusca();
  final _qCtrl = TextEditingController();

  List<String> _relays = [];
  List<rust.PerfilItem> _resultados = [];
  List<rust.PostItem> _postsRed = [];
  int _modo = 0; // 0 usuarios · 1 posts · 2 relés (solo, sin user)
  RelayCheck? _rele;
  List<RelayCheck>? _relesDir; // directorio: SOLO los que no tengo
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
    // Modo Relés: vacío trae TODOS los nuevos (solo lista relés).
    // Modos 0/1 sí exigen texto.
    if (q.isEmpty && _modo != 2) {
      setState(() => _estado = 'escribí un nombre o pegá un npub');
      return;
    }
    setState(() {
      _corriendo = true;
      _estado = _modo == 2
          ? 'revisando relay…'
          : _modo == 1
              ? 'buscando posts de la red…'
              : _esClave
                  ? 'trayendo perfil…'
                  : 'buscando "$q"…';
      _resultados = [];
      _postsRed = [];
      _rele = null;
      _relesDir = null;
    });
    try {
      if (_modo == 2) {
        // URL directa (con esquema) → se revisa ese. Texto (aunque
        // tenga punto) → directorio filtrado, EXCLUYENDO los del editor.
        final ql = q.toLowerCase();
        final esUrl = ql.startsWith('wss://') ||
            ql.startsWith('ws://') ||
            q.contains('://');
        if (esUrl) {
          final r = await RelayInfo.revisar(q);
          setState(() {
            _rele = r;
            _estado = r.ok
                ? 'relay OK · ${r.latenciaMs} ms'
                : 'relay con problemas';
          });
        } else {
          setState(() => _estado = q.isEmpty
              ? 'trayendo directorio…'
              : 'buscando "$q" (nuevos)…');
          final dir = await RelayDirectorio.cargar();
          final mios = _relays.toSet();
          final cands = [
            for (final u in dir)
              if (!mios.contains(u) &&
                  (q.isEmpty ||
                      u.toLowerCase().contains(q.toLowerCase())))
                u,
          ].take(50).toList();
          setState(() => _estado = 'revisando ${cands.length} nuevos…');
          final res = <RelayCheck>[];
          for (var i = 0; i < cands.length; i += 50) {
            final lote =
                cands.sublist(i, (i + 50).clamp(0, cands.length));
            res.addAll(await Future.wait(lote.map(RelayInfo.revisar)));
          }
          res.sort((a, b) {
            if (a.ok != b.ok) return a.ok ? -1 : 1;
            return a.latenciaMs.compareTo(b.latenciaMs);
          });
          setState(() {
            _relesDir = res;
            _estado = '${res.length} relays nuevos';
          });
        }
      } else if (_modo == 1) {
        final r = await _busca.buscarPosts(query: q, relays: _relays);
        setState(() {
          _postsRed = r;
          _estado = '${r.length} post(s)';
        });
      } else if (_esClave) {
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
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).pop();
                _verReles(p);
              },
              icon: const Icon(Icons.hub_rounded),
              label: const Text('Ver relés'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verReles(rust.PerfilItem p) async {
    final ctx = context;
    // hoja de carga → resultado
    showModalBottomSheet<void>(
      context: ctx,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _HojaReles(
        npub: p.npub,
        nombre: p.displayName.isNotEmpty ? p.displayName : p.name,
        busca: _busca,
        relaysConsulta: [..._relays],
        onUsar: (urls) {
          final seen = <String>{};
          final merged = <String>[];
          for (final u in [...urls, ..._relays]) {
            if (seen.add(u)) merged.add(u);
          }
          setState(() => _relays = merged);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${urls.length} relés cargados al editor')),
          );
        },
      ),
    );
  }

  /// Modo Relés: directorio de NUEVOS (o URL directa), sin usuarios.
  /// Sin lista fija: lo que ya tenés se excluye siempre.
  Widget _vistaRele() {
    final r = _rele;
    final dir = _relesDir;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        if (dir != null) ...[
          for (final e in dir)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                  e.ok
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
                  color: e.ok ? Colors.green : Colors.red,
                  size: 20),
              title: Text(
                  e.nombre.isNotEmpty
                      ? e.nombre
                      : e.url.replaceFirst('wss://', ''),
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                  '${e.url.replaceFirst('wss://', '')}'
                  '${e.latenciaMs >= 0 ? ' · ${e.latenciaMs} ms' : ' · caído'}'
                  '${e.conPago ? ' · pago' : ''}',
                  style: const TextStyle(fontSize: 11)),
              trailing: IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'sumar al editor',
                  onPressed: () => _sumarRelay(e.url)),
              onTap: () {
                _qCtrl.text = e.url;
                _run();
              },
            ),
          if (dir.isEmpty)
            Text('nada nuevo con ese filtro',
                style: TextStyle(color: Colors.grey[600])),
        ] else if (r == null)
          Text('pegá un relay (wss://…) y buscá',
              style: TextStyle(color: Colors.grey[600]))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                          r.ok
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          color: r.ok ? Colors.green : Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                          child: SelectableText(r.url,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                      if (r.latenciaMs >= 0)
                        Text('${r.latenciaMs} ms',
                            style: TextStyle(
                                color: r.latenciaMs < 800
                                    ? Colors.green
                                    : Colors.orange)),
                    ]),
                    if (r.nombre.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r.nombre,
                          style: const TextStyle(fontSize: 15)),
                    ],
                    if (r.descripcion.isNotEmpty)
                      Text(r.descripcion,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (r.software.isNotEmpty)
                        Chip(
                            label: Text('${r.software} ${r.version}',
                                style: const TextStyle(fontSize: 10))),
                      if (r.nips.isNotEmpty)
                        Chip(
                            label: Text('NIP-11 · ${r.nips.length} NIPs',
                                style: const TextStyle(fontSize: 10))),
                      if (r.conPago)
                        const Chip(
                            label: Text('pago',
                                style: TextStyle(fontSize: 10))),
                      if (r.limitado)
                        const Chip(
                            label: Text('con auth',
                                style: TextStyle(fontSize: 10))),
                    ]),
                    if (r.contacto.isNotEmpty)
                      SelectableText('contacto: ${r.contacto}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54)),
                    if (r.error.isNotEmpty)
                      Text(r.error,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.red)),
                    Row(children: [
                      TextButton(
                          onPressed: () => Clipboard.setData(
                              ClipboardData(text: r.url)),
                          child: const Text('copiar url',
                              style: TextStyle(fontSize: 11))),
                    ]),
                  ]),
            ),
          ),
      ],
    );
  }

  /// Suma un relay nuevo al editor (sale de la lista de nuevos).
  void _sumarRelay(String url) {
    if (_relays.contains(url)) return;
    setState(() {
      _relays = [..._relays, url];
      _relesDir?.removeWhere((e) => e.url == url);
      _estado = 'sumado al editor';
    });
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.person_search_rounded, size: 18),
                    label: Text('Usuarios')),
                ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.forum_rounded, size: 18),
                    label: Text('Posts')),
                ButtonSegment(
                    value: 2,
                    icon: Icon(Icons.hub_rounded, size: 18),
                    label: Text('Relés')),
              ],
              selected: {_modo},
              onSelectionChanged: (v) => setState(() => _modo = v.first),
            ),
            const SizedBox(height: 8),
            Row(children: [
            Expanded(
              child: TextField(
                controller: _qCtrl,
                decoration: InputDecoration(
                  hintText: _modo == 2
                      ? 'vacío = trae nuevos · texto filtra · o pegá wss://…'
                      : _modo == 1
                          ? 'buscar posts en toda la red…'
                          : 'nombre… o pegá un npub / nprofile / hex64',
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
          key: ValueKey(_relays.join(',')),
          initial: _relays,
          onChanged: (r) => setState(() => _relays = [...r]),
        ),
        const Divider(height: 16),
        Expanded(
          child: _modo == 2
              ? _vistaRele()
              : _modo == 1 && _postsRed.isNotEmpty
                  ? ListView.builder(
                  itemCount: _postsRed.length,
                  itemBuilder: (_, i) {
                    final b = _postsRed[i];
                    final d = DateTime.fromMillisecondsSinceEpoch(b.fechaMs);
                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigoAccent.withValues(alpha: .07),
                        border: Border.all(
                            color:
                                Colors.indigoAccent.withValues(alpha: .4)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${d.day}/${d.month}/${d.year} · ${_npubCorto(b.autorNpub)}',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.white38)),
                            const SizedBox(height: 4),
                            SelectableText(b.contenido,
                                style: const TextStyle(fontSize: 13)),
                            Row(children: [
                              TextButton(
                                  onPressed: () => Clipboard.setData(
                                      ClipboardData(text: b.idHex)),
                                  child: const Text('copiar ID',
                                      style: TextStyle(fontSize: 11))),
                              TextButton(
                                  onPressed: () async {
                                    try {
                                      final per = await _busca.perfil(
                                          npub: b.autorNpub,
                                          relays: _relays);
                                      if (!mounted) return;
                                      _ficha(per);
                                    } catch (_) {}
                                  },
                                  child: const Text('ver autor',
                                      style: TextStyle(fontSize: 11))),
                            ]),
                          ]),
                    );
                  },
                )
              : _resultados.isEmpty
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

/// Hoja de relés: trae NIP-65 + fallback NIP-02 y muestra lista.
class _HojaReles extends StatefulWidget {
  final String npub;
  final String nombre;
  final NostrBusca busca;
  final List<String> relaysConsulta;
  final ValueChanged<List<String>> onUsar;
  const _HojaReles({
    required this.npub,
    required this.nombre,
    required this.busca,
    required this.relaysConsulta,
    required this.onUsar,
  });
  @override
  State<_HojaReles> createState() => _HojaRelesState();
}

class _HojaRelesState extends State<_HojaReles> {
  List<rust.RelayItem>? _reles;
  String _estado = 'cargando relés…';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final r = await widget.busca.relays(
        npub: widget.npub,
        relays: widget.relaysConsulta,
      );
      if (!mounted) return;
      setState(() {
        _reles = r;
        _estado = r.isEmpty ? 'sin relés publicados' : '${r.length} relés';
        _error = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = 'ERROR: $e';
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reles = _reles;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.nombre.isEmpty
                  ? 'Relés'
                  : 'Relés de ${widget.nombre}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(_estado,
                style: TextStyle(
                    fontSize: 12,
                    color: _error ? Colors.redAccent : Colors.grey[400])),
            const SizedBox(height: 12),
            if (reles == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (reles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('el usuario no publicó lista de relés (NIP-65 ni NIP-02)',
                    style: TextStyle(color: Colors.white54)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: reles.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = reles[i];
                    final tags = [
                      if (r.lectura) 'lectura',
                      if (r.escritura) 'escritura',
                    ].join(' · ');
                    return ListTile(
                      dense: true,
                      title: SelectableText(r.url,
                          style: const TextStyle(fontSize: 12)),
                      subtitle: Text(
                          tags.isEmpty ? '—' : tags,
                          style: const TextStyle(fontSize: 10, color: Colors.white54)),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: 'copiar',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: r.url));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('copiado')));
                        },
                      ),
                    );
                  },
                ),
              ),
            if (reles != null && reles.isNotEmpty) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  final urls = reles.map((e) => e.url).toList();
                  widget.onUsar(urls);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.input_rounded),
                label: const Text('Usar en editor'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
