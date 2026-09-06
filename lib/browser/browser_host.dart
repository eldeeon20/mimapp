import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_cookies.dart';
import 'browser_tab.dart';
import 'browser_tabs.dart';
import 'browser_webview.dart';

/// Browser completo (barra + WebViews) montado como overlay global en
/// app.dart. Al usar `Visibility(maintainState: true)` los WebViews siguen
/// montados aunque el browser esté cerrado → el estado (scroll/historial/JS)
/// persiste al ir y volver de la pantalla Web.
///
/// Barra: `← atrás · → adelante · ⟳ recargar · URL · [pestañas] · [⋮]`.
/// El botón ⋮ abre un menú propio (no PopupMenuButton, que no funciona dentro
/// del overlay) con Nueva pestaña / Ajustes del navegador / Cerrar Web.
/// JavaScript se activa solo desde Ajustes. El botón atrás del celular nunca
/// cierra la app: cierra popups → cierra el browser (web intacta) → si no hay
/// nada, bloquea.
class BrowserWebViewsHost extends StatefulWidget {
  const BrowserWebViewsHost({super.key});

  @override
  State<BrowserWebViewsHost> createState() => _BrowserWebViewsHostState();
}

class _BrowserWebViewsHostState extends State<BrowserWebViewsHost>
    with WidgetsBindingObserver {
  final _urlCtrl = TextEditingController();
  final _proxyCtrl = TextEditingController();
  bool _tabsOpen = false;
  bool _menuOpen = false;
  bool _settingsOpen = false;
  bool _historyOpen = false;
  String _proxyScheme = 'PROXY';
  List<WebHistoryItem>? _historyItems;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    final t = BrowserTabs.instance;
    _urlCtrl.text = t.active.url;
    _proxyCtrl.text = t.proxyHostPort;
    _proxyScheme = t.proxyScheme;
    t.addListener(_syncUrl);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    BrowserTabs.instance.removeListener(_syncUrl);
    WidgetsBinding.instance.removeObserver(this);
    _urlCtrl.dispose();
    _proxyCtrl.dispose();
    super.dispose();
  }

  /// El botón atrás del celular NO cierra la app nunca (decisión del usuario).
  /// Cerramos primero cualquier popup; si el browser está abierto lo ocultamos
  /// (las WebViews siguen vivas); si no queda nada, bloqueamos la salida.
  @override
  Future<bool> didRequestPopRoute() async {
    // Si hay una pantalla apilada (sub-ruta), dejamos que el Navigator la
    // cierre normalmente: no bloqueamos la navegación de la app.
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      return false;
    }
    if (_historyOpen) {
      setState(() => _historyOpen = false);
      return true;
    }
    if (_settingsOpen) {
      setState(() => _settingsOpen = false);
      return true;
    }
    if (_menuOpen) {
      setState(() => _menuOpen = false);
      return true;
    }
    if (_tabsOpen) {
      setState(() => _tabsOpen = false);
      return true;
    }
    final tabs = BrowserTabs.instance;
    if (tabs.isOpen) {
      tabs.closeBrowser();
      return true;
    }
    return true; // nunca cerrar la app con atrás
  }

  void _syncUrl() {
    final a = BrowserTabs.instance.active;
    if (_urlCtrl.text != a.url) _urlCtrl.text = a.url;
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyItems = null;
    });
    try {
      final tabs = BrowserTabs.instance;
      final c = tabs.controllerOf(tabs.active.id);
      final h = await c?.getCopyBackForwardList();
      setState(() {
        _historyItems = h?.list;
        _historyLoading = false;
      });
    } catch (e) {
      setState(() {
        _historyItems = const [];
        _historyLoading = false;
      });
    }
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
                            child: BrowserWebview(
                                key: ValueKey(t.id), tabs: tabs, tab: t),
                          ),
                      ],
                    ),
                  ),
                ]),
                if (_tabsOpen) _tabsPanel(tabs),
                if (_menuOpen) _menuPanel(tabs),
                if (_settingsOpen) _settingsPanel(tabs),
                if (_historyOpen) _historyPanel(tabs),
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
        IconButton(
          icon: const Icon(Icons.more_vert, size: 20),
          onPressed: () => setState(() => _menuOpen = !_menuOpen),
        ),
      ]),
    );
  }

  Widget _overlayPanel({
    required Widget child,
    required VoidCallback onClose,
    Alignment alignment = Alignment.topRight,
  }) {
    return Material(
      color: Colors.black54,
      child: GestureDetector(
        onTap: onClose,
        child: Align(
          alignment: alignment,
          child: GestureDetector(
            onTap: () {}, // tocar el contenido no cierra
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _menuPanel(BrowserTabs tabs) {
    return _overlayPanel(
      onClose: () => setState(() => _menuOpen = false),
      child: Container(
        margin: const EdgeInsets.only(top: 48, right: 8),
        width: 240,
        decoration: BoxDecoration(
            color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Nueva pestaña'),
            onTap: () {
              tabs.add();
              setState(() => _menuOpen = false);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Ajustes del navegador'),
            onTap: () => setState(() {
              _menuOpen = false;
              _settingsOpen = true;
            }),
          ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cerrar Web'),
            onTap: () {
              tabs.closeBrowser();
              setState(() => _menuOpen = false);
            },
          ),
        ]),
      ),
    );
  }

  Widget _settingsPanel(BrowserTabs tabs) {
    return _overlayPanel(
      alignment: Alignment.bottomCenter,
      onClose: () => setState(() => _settingsOpen = false),
      child: Container(
        margin: const EdgeInsets.all(8),
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        decoration: BoxDecoration(
            color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('Ajustes del navegador',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _settingsOpen = false)),
            ]),
            SwitchListTile(
              title: const Text('Habilitar JavaScript'),
              value: tabs.jsEnabled,
              onChanged: (v) => tabs.setJs(v),
            ),
            SwitchListTile(
              title: const Text('Bloquear imágenes'),
              value: tabs.blockNetworkImage,
              onChanged: (v) => tabs.setBlockNetworkImage(v),
            ),
            SwitchListTile(
              title: const Text('Cookies de terceros'),
              value: tabs.thirdPartyCookies,
              onChanged: (v) => tabs.setThirdPartyCookies(v),
            ),
            SwitchListTile(
              title: const Text('Cookies compartidas'),
              value: tabs.sharedCookies,
              onChanged: (v) => tabs.setSharedCookies(v),
            ),
            SwitchListTile(
              title: const Text('Sin geolocalizar'),
              value: !tabs.geolocation,
              onChanged: (v) => tabs.setGeolocation(!v),
            ),
            SwitchListTile(
              title: const Text('Modo seguro (Safe Browsing)'),
              value: tabs.safeBrowsing,
              onChanged: (v) => tabs.setSafeBrowsing(v),
            ),
            SwitchListTile(
              title: const Text('Modo incógnito'),
              value: tabs.incognito,
              onChanged: (v) => tabs.setIncognito(v),
            ),
            const Divider(),
            const Text('Proxy (genérico)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _proxyCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'host:puerto (ej. 127.0.0.1:8080)',
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
                ),
              ),
              DropdownButton<String>(
                value: _proxyScheme,
                dropdownColor: Colors.grey[800],
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'PROXY', child: Text('HTTP')),
                  DropdownMenuItem(value: 'SOCKS', child: Text('SOCKS')),
                ],
                onChanged: (v) => setState(() => _proxyScheme = v!),
              ),
            ]),
            Row(children: [
              ElevatedButton(
                onPressed: () =>
                    tabs.setProxy(true, _proxyCtrl.text, _proxyScheme),
                child: const Text('Aplicar proxy'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () =>
                    tabs.setProxy(false, _proxyCtrl.text, _proxyScheme),
                child: const Text('Quitar proxy'),
              ),
            ]),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.cookie),
              title: const Text('Borrar todas las cookies'),
              onTap: () => CookieStore.instance.clearAll(),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Ver historial'),
              onTap: () {
                setState(() {
                  _settingsOpen = false;
                  _historyOpen = true;
                });
                _loadHistory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_toggle_off),
              title: const Text('Borrar historial'),
              onTap: () async {
                final c = tabs.controllerOf(tabs.active.id);
                await c?.clearHistory();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services),
              title: const Text('Borrar caché'),
              onTap: () => InAppWebViewController.clearAllCache(),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _historyPanel(BrowserTabs tabs) {
    return _overlayPanel(
      alignment: Alignment.center,
      onClose: () => setState(() => _historyOpen = false),
      child: Container(
        margin: const EdgeInsets.all(16),
        width: double.infinity,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: BoxDecoration(
            color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Row(children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Historial',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _historyOpen = false)),
          ]),
          const Divider(height: 1),
          Expanded(
            child: _historyLoading
                ? const Center(child: CircularProgressIndicator())
                : (_historyItems == null || _historyItems!.isEmpty)
                    ? const Center(child: Text('Sin historial'))
                    : ListView(
                        children: [
                          for (final item in _historyItems!)
                            ListTile(
                              title: Text(item.title ?? item.url.toString()),
                              subtitle: Text(item.url.toString()),
                              onTap: () async {
                                final c = tabs.controllerOf(tabs.active.id);
                                await c?.goTo(historyItem: item);
                                setState(() => _historyOpen = false);
                              },
                            ),
                        ],
                      ),
          ),
        ]),
      ),
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
