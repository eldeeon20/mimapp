import 'package:flutter/material.dart';

import '../services/history_store.dart';
import '../services/settings.dart';
import 'page_registry.dart';
import 'page_router.dart';

/// Inicio de la web estilo buscador: logo, campo de búsqueda global
/// (nombres locales o uri completa), historial cifrado y grilla de
/// recomendados con las páginas locales "en caliente".
class WebHome extends StatefulWidget {
  /// Navega a un uri vía el PageRouter.
  final void Function(String uri) onOpenUri;

  /// Refresca el shell (tras toggles de tema/borrado de historial).
  final VoidCallback refresh;

  const WebHome({super.key, required this.onOpenUri, required this.refresh});

  @override
  State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final q = _searchCtrl.text.trim();
    if (q.isNotEmpty) widget.onOpenUri(q);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Settings.instance.webDarkMode;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        Center(
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [
              Color(0xFF22D3EE),
              Color(0xFFA78BFA),
              Color(0xFFFF2BD6),
            ]).createShader(r),
            child: Text('pr_web',
                style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: dark ? Colors.white : Colors.black87)),
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _searchCtrl,
          onSubmitted: (_) => _submit(),
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            hintText:
                'Buscar o uri (lua:// · http:// · tcp:// · udp:// · nostrn://)',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: _submit,
            ),
            filled: true,
            fillColor: dark ? const Color(0xFF0B1226) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(28),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ActionChip(
            avatar: Icon(
                dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                size: 16),
            label: Text(dark ? 'oscuro' : 'claro'),
            onPressed: () async {
              Settings.instance.webDarkMode = !Settings.instance.webDarkMode;
              await Settings.instance.save();
              widget.refresh();
            },
            tooltip: 'Modo global de la web (persistido en Ajustes)',
          ),
          ActionChip(
            avatar: const Icon(Icons.history_rounded, size: 16),
            label: Text('historial (${HistoryStore.instance.entries.length})'),
            onPressed: () async {
              await HistoryStore.instance.clear();
              widget.refresh();
            },
          ),
        ]),
        ..._historySection(),
        ..._recommendedSection(),
      ],
    );
  }

  List<Widget> _historySection() {
    final hist = HistoryStore.instance.entries;
    if (hist.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      Text('HISTORIAL',
          style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: Theme.of(context).hintColor)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final h in hist.take(12))
            InputChip(
              avatar: const Icon(Icons.history_edu_rounded, size: 14),
              label: Text(h['title'] ?? h['uri'] ?? '?',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onPressed: () => widget.onOpenUri(h['uri'] ?? ''),
              onDeleted: () async {
                await HistoryStore.instance.remove(h['uri'] ?? '');
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    ];
  }

  List<Widget> _recommendedSection() {
    return [
      const SizedBox(height: 22),
      Text('RECOMENDADOS · páginas locales en caliente',
          style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: Theme.of(context).hintColor)),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.9,
        children: [for (final r in PageRouter.instance.recommended()) _reco(r)],
      ),
      const SizedBox(height: 30),
    ];
  }

  Widget _reco(Map<String, String> r) {
    final dark = Settings.instance.webDarkMode;
    final color = _hex(r['color'] ?? '#22D3EE');
    final icon = _iconFor(r['icon'] ?? 'widgets');
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => widget.onOpenUri(r['uri']!),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF0B1226) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .5)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .15), blurRadius: 14),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r['title'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: dark ? Colors.white : Colors.black87)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(r['desc'] ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.3,
                    color: dark ? Colors.white54 : Colors.black45)),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String name) => switch (name) {
        'memory' => Icons.memory_rounded,
        'call_split' => Icons.call_split_rounded,
        'lock' => Icons.lock_rounded,
        'hub' => Icons.hub_rounded,
        'chat' => Icons.chat_bubble_rounded,
        'visibility' => Icons.visibility_rounded,
        'play' => Icons.play_circle_rounded,
        'psychology' => Icons.psychology_rounded,
        'download' => Icons.download_rounded,
        _ => Icons.widgets_rounded,
      };

  Color _hex(String s) {
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(s.trim());
    if (m == null) return Colors.cyanAccent;
    return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }
}
