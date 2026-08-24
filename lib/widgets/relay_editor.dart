import 'package:flutter/material.dart';

/// Editor de lista de relays: chips con ✕ para quitar + campo para agregar.
/// Usado por los tests Nostr (DM NIP-17 y observer) que antes tenían los
/// relays clavados en constantes.
class RelayEditor extends StatefulWidget {
  final List<String> initial;
  final ValueChanged<List<String>> onChanged;

  const RelayEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<RelayEditor> createState() => _RelayEditorState();
}

class _RelayEditorState extends State<RelayEditor> {
  late List<String> _relays = [...widget.initial];
  final _ctrl = TextEditingController();

  void _emit() => widget.onChanged(List.unmodifiable(_relays));

  void _remove(String r) {
    setState(() => _relays.remove(r));
    _emit();
  }

  void _add() {
    var v = _ctrl.text.trim();
    if (v.isEmpty) return;
    if (!v.startsWith('ws://') && !v.startsWith('wss://')) v = 'wss://$v';
    if (!_relays.contains(v)) {
      setState(() => _relays.add(v));
      _emit();
    }
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final r in _relays)
              InputChip(
                label: Text(r.replaceAll('wss://', '').replaceAll('ws://', ''),
                    style: const TextStyle(fontSize: 9)),
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.white.withValues(alpha: .05),
                onDeleted: () => _remove(r),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                hintText: 'agregar relay (ej. nos.lol)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded,
                size: 18, color: Colors.greenAccent),
            tooltip: 'Agregar relay',
            onPressed: _add,
          ),
        ]),
      ],
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
}
