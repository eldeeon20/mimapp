import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../src/rust/api/nostr_busca.dart' as rust;
import '../services/nostr_busca.dart';

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
            child: SelectableText('npub: ${widget.npub}',
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
                  Row(children: [
                    Expanded(
                        child: Text(_fecha(p.fechaMs),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white38))),
                    IconButton(
                      tooltip: 'copiar ID (para responder/citar en Nostrn+)',
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: p.idHex)),
                    ),
                  ]),
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
