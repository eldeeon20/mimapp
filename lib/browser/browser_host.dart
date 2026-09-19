import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/tor_service.dart';
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
  bool _torBusy = false;
  String? _torMsg;

  /// Auto-Tor al abrir la web: el toggle nace en ON (se intenta una vez
  /// por sesión; si falla queda OFF y el usuario lo prende a mano).
  bool _torAutoTried = false;

  /// Flag histórico: YA NO desmonta vistas (fix negro al volver).
  /// Se deja en false siempre; antes true desmontaba a SizedBox.
  bool _enFondo = false;

  /// Generación POR PESTAÑA: solo se incrementa la de la pestaña cuyo
  /// renderer murió (onRenderProcessGone) para recrear ESA vista nativa
  /// con su URL. Las sanas no se tocan: la web se mantiene sin recargar.
  /// OJO: recrear en fondo con la Web cerrada (offstage) crea vistas que
  /// nunca enganchan surface y al reabrir queda negro: por eso la
  /// recreación de una muerta cerrada espera a que se ABRA (visible).
  final Map<int, int> _genTab = {};

  // _genVistas global ya no se usa (era recarga de todo al volver);
  // se deja comentado (regla: no borrar):
  // int _genVistas = 0;

  // _pendeRecrear global ya no se usa (era recarga de todo al abrir);
  // se deja comentado (regla: no borrar):
  // bool _pendeRecrear = false;

  @override
  void initState() {
    super.initState();
    final t = BrowserTabs.instance;
    _urlCtrl.text = t.active.url;
    _proxyCtrl.text = t.proxyHostPort;
    _proxyScheme = t.proxyScheme;
    t.addListener(_syncUrl);
    t.closePanels = _cerrarPaneles;
    WidgetsBinding.instance.addObserver(this);
    // Tor por defecto: al abrir la web se prende solo (una vez).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_torAutoTried || !mounted) return;
      _torAutoTried = true;
      if (!TorService.instance.proxyOn) {
        _cambiarTor(BrowserTabs.instance);
      }
    });
  }

  @override
  void dispose() {
    final tabs = BrowserTabs.instance;
    tabs.removeListener(_syncUrl);
    if (tabs.closePanels == _cerrarPaneles) tabs.closePanels = null;
    WidgetsBinding.instance.removeObserver(this);
    _urlCtrl.dispose();
    _proxyCtrl.dispose();
    super.dispose();
  }

  /// El botón atrás del celular NO cierra la app nunca (decisión del usuario).
/// El atrás lo atiende el PopScope de pr_app.dart, que llama a
/// [BrowserTabs.closePanels] (registrado acá abajo): primero se cierran
/// los paneles (menú/pestañas/ajustes/historial), recién después la web.
/// (El WidgetsBindingObserver anterior usaba `didRequestPopRoute`, que no
/// existe en Flutter: ese código nunca se ejecutaba y el atrás se
/// comía la web entera.)
  bool _cerrarPaneles() {
    if (!(_tabsOpen || _menuOpen || _settingsOpen || _historyOpen)) {
      return false;
    }
    setState(() {
      _tabsOpen = false;
      _menuOpen = false;
      _settingsOpen = false;
      _historyOpen = false;
    });
    return true;
  }

  /// Fondo con web cerrada: se APARCA (pause: paran timers/GPU) y se
  /// REANUDA al volver/abrir, sin desmontar ni recargar. OJO: esto SOLO
  /// frena trabajo; el negro de TODA la app lo causaba la composición
  /// híbrida (SurfaceView huérfano tapando todo) y se arregla con
  /// useHybridComposition:false en currentWebViewSettings (las vistas
  /// siguen montadas, sin recargas). Con web abierta no se toca.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Código viejo dejado comentado (regla: no borrar):
    // final tabs = BrowserTabs.instance;
    // if (estado == AppLifecycleState.paused) {
    //   tabs.forgetAll();
    //   _enFondo = true;
    //   if (mounted) setState(() {});
    // } else if (estado == AppLifecycleState.resumed) {
    //   _enFondo = false;
    //   if (mounted) setState(() {});
    // }
    // Intento anterior dejado comentado (olvidaba controladores y
    // recreaba todo al volver/abrir = recargaba la web):
    // if (estado == AppLifecycleState.resumed) {
    //   _enFondo = false;
    //   try {
    //     final tabs = BrowserTabs.instance;
    //     tabs.forgetAll();
    //     _genVistas++;
    //   } catch (_) {}
    //   if (mounted) setState(() {});
    // } else if (estado == AppLifecycleState.paused) {
    //   _enFondo = false;
    // }
    // Intento anterior 2 dejado comentado (recreaba todo al abrir tras
    // volver con la Web cerrada = también recargaba):
    // if (estado == AppLifecycleState.resumed) {
    //   _enFondo = false;
    //   try {
    //     final tabs = BrowserTabs.instance;
    //     if (!tabs.isOpen) {
    //       tabs.forgetAll();
    //       _pendeRecrear = true;
    //     }
    //   } catch (_) {}
    //   if (mounted) setState(() {});
    // } else if (estado == AppLifecycleState.paused) {
    //   _enFondo = false;
    // }
    if (estado == AppLifecycleState.paused ||
        estado == AppLifecycleState.resumed) {
      // A propósito no se desmonta ni se olvida nada: mantener WebViews
      // y controladores vivos tal cual.
      _enFondo = false;
      final tabs = BrowserTabs.instance;
      if (estado == AppLifecycleState.paused && !tabs.isOpen) {
        // Web cerrada al ir a fondo: aparcar (sin recargar).
        unawaited(tabs.pausarTodos());
      } else if (estado == AppLifecycleState.resumed) {
        // Al volver: reanudar lo aparcado (sano o no, resume es seguro).
        unawaited(tabs.reanudarTodos());
      }
    }
  }

  void _syncUrl() {
    final tabs = BrowserTabs.instance;
    // Pestaña activa con renderer muerto: se recrea SOLO ella ahora
    // (si la Web está abierta = visible; si está cerrada se deja
    // marcada y se recrea cuando se abra, nunca en fondo).
    if (tabs.isOpen && tabs.estaMuerto(tabs.active.id)) {
      tabs.tomarMuerto(tabs.active.id);
      _genTab[tabs.active.id] = (_genTab[tabs.active.id] ?? 0) + 1;
      if (mounted) setState(() {});
    }
    // Si el browser se cerró desde afuera (botón atrás de app.dart),
    // los paneles locales quedaban abiertos y al reentrar no se veía
    // la web. Se resetean acá.
    if (!tabs.isOpen &&
        (_tabsOpen || _menuOpen || _settingsOpen || _historyOpen)) {
      setState(() {
        _tabsOpen = false;
        _menuOpen = false;
        _settingsOpen = false;
        _historyOpen = false;
      });
    }
    final a = tabs.active;
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
            // Mismo negro de la barra por si algo deja hueco.
            backgroundColor: Colors.black87,
            // top:false: la barra arranca en el borde físico (y=0) y usa
            // TODA la pantalla incluida la zona de la cámara; nada queda
            // por debajo de ella. Abajo/izq/der se siguen respetando.
            body: SafeArea(
              top: false,
              child: Stack(children: [
                Column(children: [
                  _bar(tabs, active),
                  Expanded(
                    // FIX negro: vistas siempre montadas; cada pestaña se
                    // recrea SOLO si su renderer murió (gen por pestaña).
                    // Las sanas quedan intactas, sin recargar.
                    // Viejo: _enFondo ? SizedBox.shrink() : Stack(...)
                    child: Stack(
                            children: [
                              for (final t in tabs.tabs)
                                Visibility(
                                  key: ValueKey(
                                      '${t.id}-v${_genTab[t.id] ?? 0}'),
                                  visible: t.id == active.id,
                                  maintainState: true,
                                  child: BrowserWebview(
                                      key: ValueKey(
                                          '${t.id}-v${_genTab[t.id] ?? 0}'),
                                      tabs: tabs,
                                      tab: t),
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
            onSubmitted: (v) async {
              try {
                await tabs.loadUrl(active.id, v);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$e')),
                );
              }
            },
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
    // Sin detector interno vacío: ese absorbía los taps de TODA la
    // pantalla y el toque afuera nunca llegaba a onClose.
    // behavior.opaque: el área oscura (sin hijo dibujado) también
    // recibe el tap; con deferToChild el toque afuera no cerraba.
    return Material(
      color: Colors.black54,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Align(
          alignment: alignment,
          child: child,
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
          _torToggle(tabs),
          ListTile(
            leading: _torBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            title: const Text('Re-bootstrap Tor'),
            subtitle: const Text('nuevo circuito + recarga',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
            onTap: _torBusy
                ? null
                : () async {
                    setState(() {
                      _menuOpen = false;
                      _torBusy = true;
                      _torMsg = 're-bootstrap…';
                    });
                    try {
                      await TorService.instance.rebootstrap();
                      try {
                        await tabs.reload(tabs.active.id);
                      } catch (_) {}
                      if (mounted) {
                        setState(
                            () => _torMsg = 'circuito nuevo, página recargada');
                      }
                    } catch (e) {
                      if (mounted) setState(() => _torMsg = 'ERROR: $e');
                    } finally {
                      if (mounted) setState(() => _torBusy = false);
                    }
                  },
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

  /// Toggle Tor en el menú ⋮: ON = arranca cliente (si falta) + proxy
  /// CONNECT local y manda todo el WebView por Tor; OFF = vuelve a
  /// directo. La URL sigue normal, solo cambia por dónde sale.
  Widget _torToggle(BrowserTabs tabs) {
    final tor = TorService.instance;
    return ListTile(
      leading: Icon(
        Icons.shield_rounded,
        color: tor.proxyOn ? Colors.greenAccent : Colors.grey,
      ),
      title: const Text('Tor'),
      subtitle: Text(
        _torBusy
            ? 'trabajando…'
            : (_torMsg ??
                (tor.proxyOn
                    ? 'ON · sale por Tor (${tor.proxyUrl})'
                    : 'OFF · navegar directo')),
        style: const TextStyle(fontSize: 11, color: Colors.white54),
      ),
      trailing: Switch(
        value: tor.proxyOn,
        onChanged: _torBusy ? null : (_) => _cambiarTor(tabs),
      ),
      onTap: _torBusy ? null : () => _cambiarTor(tabs),
    );
  }

  /// Prende/apaga la salida por Tor del navegador.
  /// Orden: start cliente → startProxy (hp aleatorio) → setProxy → reload
  /// (los WebViews vivos no re-leen proxy hasta recargar).
  Future<void> _cambiarTor(BrowserTabs tabs) async {
    final tor = TorService.instance;
    setState(() {
      _torBusy = true;
      _torMsg = null;
    });
    try {
      if (!tor.proxyOn) {
        await tor.refresh();
        if (!tor.running) {
          setState(() => _torMsg = 'arrancando Tor (bootstrap)…');
          await tor.start();
          await tor.refresh();
          if (!tor.running) {
            throw 'Tor no arrancó: ${tor.state}';
          }
        }
        final hp = await tor.startProxy();
        // SOCKS5 oficial de arti (un solo túnel, sin separar http):
        // Chromium manda el hostname y Tor resuelve (incluye .onion).
        final ok = await tabs.setProxy(true, hp, 'SOCKS',
            bypass: const ['127.0.0.1', 'localhost']);
        if (!ok) throw 'el WebView no aceptó el proxy';
        // Los WebViews ya creados no aplican el override hasta recargar.
        try {
          await tabs.reload(tabs.active.id);
        } catch (_) {}
        setState(() => _torMsg = 'ON · sale por Tor ($hp)');
      } else {
        await tabs.setProxy(false, '', 'PROXY');
        await tor.stopProxy();
        try {
          await tabs.reload(tabs.active.id);
        } catch (_) {}
        setState(() => _torMsg = 'OFF · navegar directo');
      }
    } catch (e) {
      setState(() => _torMsg = 'ERROR: $e');
    } finally {
      if (mounted) setState(() => _torBusy = false);
    }
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
        behavior: HitTestBehavior.opaque,
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
                        onPressed: () {
                          // Cerrar la última no reabre otra en bucle:
                          // cierra el panel y el browser.
                          final eraUltima = tabs.tabs.length <= 1;
                          tabs.closeAt(i);
                          if (eraUltima) {
                            setState(() => _tabsOpen = false);
                            tabs.closeBrowser();
                          }
                        },
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
