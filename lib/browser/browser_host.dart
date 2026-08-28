import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_tab.dart';
import 'browser_tabs.dart';
import 'browser_webview.dart';

/// Browser completo (barra + WebViews) montado como overlay global en
/// app.dart. Al usar `Visibility(maintainState: true)` los WebViews siguen
/// montados aunque el browser esté cerrado → el estado (scroll/historial/JS)
/// persiste al ir y volver de la pantalla Web.
///
/// Barra: `← atrás · → adelante · ⟳ recargar · URL · [pestañas] · [⋮]`.
/// El menú ⋮ tiene "Nueva pestaña", "Habilitar JavaScript" y "Cerrar Web".
class BrowserWebViewsHost extends StatefulWidget {
  const BrowserWebViewsHost({super.key});

  @override
  State<BrowserWebViewsHost> createState() => _BrowserWebViewsHostState();
}

class _BrowserWebViewsHostState extends State<BrowserWebViewsHost> {
  final _urlCtrl = TextEditingController();
  bool _tabsOpen = false;

  @override
  void initState() {
    super.initState();
    BrowserTabs.instance.addListener(_syncUrl);
  }

  @override
  void dispose() {
    BrowserTabs.instance.removeListener(_syncUrl);
    _urlCtrl.dispose();
    super.dispose();
  }

  void _syncUrl() {
    final a = BrowserTabs.instance.active;
    if (_urlCtrl.text != a.url) _urlCtrl.text = a.url;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = BrowserTabs.instance;
    return AnimatedBuilder(
      animation: tabs,
      builder: (context, _) {
        final open = tabs.isOpen;
        final active = tabs.active;
        return Visibility(
          visible: open,
          maintainState: true,
          maintainSize: false,
          maintainAnimation: true,
          child: Scaffold(
            body: SafeArea(
              child: Stack(children: [
                Column(children: [
                  _bar(tabs, active),
                  Expanded(
                    child: Stack(
                      children: [
                        for (final t in tabs.tabs)
                          Visibility(
                            key: ValueKey(t.id),
                            visible: t.id == active.id,
                            maintainState: true,
                            child: BrowserWebview(key: ValueKey(t.id), tabs: tabs, tab: t),
                          ),
                      ],
                    ),
                  ),
                ]),
                if (_tabsOpen) _tabsPanel(tabs),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(BrowserTabs tabs, BrowserTab active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      color: Colors.black87,
      child: Row(children: [
        IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => tabs.goBack(active.id)),
        IconButton(
            icon: const Icon(Icons.arrow_forward, size: 20),
            onPressed: () => tabs.goForward(active.id)),
        IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => tabs.reload(active.id)),
        Expanded(
          child: TextField(
            controller: _urlCtrl,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'buscar o escribir URL',
              hintStyle: TextStyle(fontSize: 12, color: Colors.white54),
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onSubmitted: (v) => tabs.loadUrl(active.id, v),
          ),
        ),
        IconButton(
            icon: const Icon(Icons.tab_rounded, size: 20),
            onPressed: () => setState(() => _tabsOpen = true)),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (v) async {
            if (v == 'new') {
              tabs.add();
            } else if (v == 'js') {
              await tabs.setJs(!tabs.jsEnabled);
            } else if (v == 'close') {
              tabs.closeBrowser();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'new', child: Text('Nueva pestaña')),
            PopupMenuItem(
              value: 'js',
              child: Row(children: [
                const Text('Habilitar JavaScript'),
                const Spacer(),
                Switch(value: tabs.jsEnabled, onChanged: null),
              ]),
            ),
            const PopupMenuItem(value: 'close', child: Text('Cerrar Web')),
          ],
        ),
      ]),
    );
  }

  Widget _tabsPanel(BrowserTabs tabs) {
    return Material(
      color: Colors.black54,
      child: GestureDetector(
        onTap: () => setState(() => _tabsOpen = false),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.all(12),
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7),
            decoration: BoxDecoration(
                color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                for (var i = 0; i < tabs.tabs.length; i++)
                  Card(
                    child: ListTile(
                      title: Text(tabs.tabs[i].title.isEmpty
                          ? 'Pestaña'
                          : tabs.tabs[i].title),
                      subtitle: Text(tabs.tabs[i].url,
                          style: const TextStyle(fontSize: 11)),
                      selected: i == tabs.activeIndex,
                      onTap: () {
                        tabs.activate(i);
                        setState(() => _tabsOpen = false);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => tabs.closeAt(i),
                      ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Nueva pestaña'),
                  onTap: () {
                    tabs.add();
                    setState(() => _tabsOpen = false);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
