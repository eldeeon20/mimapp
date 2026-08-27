import 'package:flutter/material.dart';

import '../browser/browser_tab.dart';
import '../browser/browser_tabs.dart';
import '../browser/browser_webview.dart';

/// Browser chico sobre flutter_inappwebview: barra URL, pestañas y toggle
/// de JavaScript. Solo compone las clases del módulo lib/browser/.
///
/// Por ahora sin selector de red (Tor/directo): la clase Proxy queda
/// pendiente; cuando exista se enchufa acá y en DownloadManager.
class InAppWebScreen extends StatefulWidget {
  const InAppWebScreen({super.key});

  @override
  State<InAppWebScreen> createState() => _InAppWebScreenState();
}

class _InAppWebScreenState extends State<InAppWebScreen> {
  final BrowserTabs _tabs = BrowserTabs();
  late final TextEditingController _urlCtrl =
      TextEditingController(text: _tabs.active.url);

  void _syncField() {
    final u = _tabs.active.url;
    if (_urlCtrl.text != u) _urlCtrl.text = u;
  }

  Future<void> _go() async => _tabs.loadUrl(_tabs.active.id, _urlCtrl.text);

  Future<void> _back() async {
    await _tabs.goBack(_tabs.active.id);
    _syncField();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _tabs,
      builder: (_, __) {
        _syncField();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Web'),
            actions: [
              const Text('JS', style: TextStyle(fontSize: 11)),
              Switch(
                value: _tabs.jsEnabled,
                onChanged: (v) => _tabs.setJs(v),
              ),
            ],
          ),
          body: Column(children: [
            // ---- barra de URL
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                IconButton(
                  tooltip: 'Atrás',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _back,
                ),
                Expanded(
                  child: TextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) => _go(),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'buscar o escribir URL',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ir / recargar',
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: _go,
                ),
              ]),
            ),
            // ---- pestañas
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: [
                  for (var i = 0; i < _tabs.tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        label: Text(
                          '${i + 1}. ${_tabs.tabs[i].title}',
                          style: const TextStyle(fontSize: 10.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: i == _tabs.activeIndex,
                        onSelected: (_) => _tabs.activate(i),
                        onDeleted:
                            _tabs.tabs.length > 1 ? () => _tabs.closeAt(i) : null,
                        deleteIconColor: Colors.redAccent,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('', style: TextStyle(fontSize: 10)),
                    onPressed: _tabs.tabs.length >= BrowserTabs.maxTabs
                        ? null
                        : _tabs.add,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
            // ---- webviews vivos (IndexedStack conserva el estado)
            Expanded(
              child: IndexedStack(
                index: _tabs.activeIndex,
                children: [
                  for (final t in _tabs.tabs)
                    BrowserWebview(tabs: _tabs, tab: t as BrowserTabLike),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
}
