import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_cookies.dart';
import 'browser_tab.dart';

/// Gestor de pestañas del browser: lista, activa, alta/baja con tope por
/// memoria y registro de controladores vivos del plugin. Notifica a la
/// pantalla para redibujar chips e IndexedStack.
///
/// El toggle global de JavaScript también vive acá: al cambiarlo se aplica
/// en vivo a todos los controladores registrados y queda como valor inicial
/// de las pestañas nuevas.
///
/// Es un singleton: las pestañas (y el host global de WebViews) sobreviven a
/// la navegación dentro de la app. `openBrowser`/`closeBrowser` controlan el
/// overlay global montado en app.dart.
class BrowserTabs extends ChangeNotifier {
  BrowserTabs._() {
    tabs.add(BrowserTab(id: _nextId()));
  }
  static final BrowserTabs instance = BrowserTabs._();

  static const maxTabs = 8;

  final List<BrowserTab> tabs = [];
  final Map<int, InAppWebViewController> _controllers = {};
  int activeIndex = 0;
  bool jsEnabled = true;
  int _idSeq = 0;

  // Ajustes del navegador (preferencias vivas, aplicadas a cada WebView).
  bool thirdPartyCookies = true;
  bool sharedCookies = false;
  bool blockNetworkImage = false;
  bool geolocation = false; // false = "sin geolocalizar"
  bool safeBrowsing = true; // "modo seguro"
  bool incognito = false;
  bool proxyEnabled = false;
  String proxyHostPort = '';
  String proxyScheme = 'PROXY';

  final ValueNotifier<bool> _open = ValueNotifier(false);
  bool get isOpen => _open.value;
  void openBrowser() {
    _open.value = true;
    notifyListeners();
  }

  void closeBrowser() {
    _open.value = false;
    notifyListeners();
  }

  BrowserTab get active {
    if (tabs.isEmpty) tabs.add(BrowserTab(id: _nextId()));
    final i = activeIndex.clamp(0, tabs.length - 1);
    return tabs[i];
  }

  int _nextId() => _idSeq++;

  /// Registra el controlador que [BrowserWebview] crea para esa pestaña;
  /// aplica de una vez todos los ajustes actuales.
  void registerController(int tabId, InAppWebViewController c) {
    _controllers[tabId] = c;
    applyTo(c);
  }

  void forgetController(int tabId) => _controllers.remove(tabId);

  void activate(int index) {
    if (index < 0 || index >= tabs.length) return;
    activeIndex = index;
    notifyListeners();
  }

  void add() {
    if (tabs.length >= maxTabs) return;
    tabs.add(BrowserTab(
        id: _nextId(), title: 'Nueva pestaña', url: 'https://duckduckgo.com/'));
    activeIndex = tabs.length - 1;
    notifyListeners();
  }

  /// Cierra SOLO la pestaña en [index] (sin cascada). Si era la última,
  /// crea una "Nueva pestaña" fresca para que siempre haya una.
  void closeAt(int index) {
    if (index < 0 || index >= tabs.length) return;
    final id = tabs[index].id;
    _controllers.remove(id);
    tabs[index].dispose();
    tabs.removeAt(index);
    if (tabs.isEmpty) {
      tabs.add(BrowserTab(
          id: _nextId(), title: 'Nueva pestaña', url: 'https://duckduckgo.com/'));
    }
    if (activeIndex >= tabs.length) activeIndex = tabs.length - 1;
    if (activeIndex < 0) activeIndex = 0;
    notifyListeners();
  }

  void rename(int tabId, String title) {
    final t = tabs.where((x) => x.id == tabId).firstOrNull;
    if (t == null) return;
    t.title = title.isEmpty ? 'Pestaña' : title;
    notifyListeners();
  }

  void updateUrl(int tabId, String url) {
    final t = tabs.where((x) => x.id == tabId).firstOrNull;
    if (t == null) return;
    t.url = url;
    notifyListeners();
  }

  InAppWebViewController? controllerOf(int tabId) => _controllers[tabId];

  /// Carga [input] en la pestaña dada; agrega https:// si falta esquema.
  Future<void> loadUrl(int tabId, String input) async {
    var u = input.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    updateUrl(tabId, u);
    await controllerOf(tabId)?.loadUrl(urlRequest: URLRequest(url: WebUri(u)));
  }

  Future<void> reload(int tabId) async {
    await controllerOf(tabId)?.reload();
  }

  Future<bool> goBack(int tabId) async {
    final c = controllerOf(tabId);
    if (c == null || !(await c.canGoBack())) return false;
    await c.goBack();
    return true;
  }

  Future<bool> goForward(int tabId) async {
    final c = controllerOf(tabId);
    if (c == null || !(await c.canGoForward())) return false;
    await c.goForward();
    return true;
  }

  /// Configuración completa que se aplica a cada WebView (nuevos y vivos).
  InAppWebViewSettings currentWebViewSettings() => InAppWebViewSettings(
        javaScriptEnabled: jsEnabled,
        thirdPartyCookiesEnabled: thirdPartyCookies,
        sharedCookiesEnabled: sharedCookies,
        blockNetworkImage: blockNetworkImage,
        geolocationEnabled: geolocation,
        safeBrowsingEnabled: safeBrowsing,
        incognito: incognito,
        transparentBackground: true,
        supportZoom: true,
      );

  /// Aplica todos los ajustes actuales a un controlador concreto.
  Future<void> applyTo(InAppWebViewController c) async {
    try {
      await c.setSettings(settings: currentWebViewSettings());
    } catch (_) {}
  }

  Future<void> _applyAll() async {
    for (final c in _controllers.values) {
      await applyTo(c);
    }
  }

  /// Cambia el JavaScript global y lo aplica en vivo a cada WebView vivo.
  Future<void> setJs(bool enabled) async {
    jsEnabled = enabled;
    await _applyAll();
    notifyListeners();
  }

  Future<void> setThirdPartyCookies(bool v) async {
    thirdPartyCookies = v;
    notifyListeners();
    await _applyAll();
  }

  Future<void> setSharedCookies(bool v) async {
    sharedCookies = v;
    notifyListeners();
    await _applyAll();
  }

  Future<void> setBlockNetworkImage(bool v) async {
    blockNetworkImage = v;
    notifyListeners();
    await _applyAll();
  }

  Future<void> setGeolocation(bool v) async {
    geolocation = v;
    notifyListeners();
    await _applyAll();
  }

  Future<void> setSafeBrowsing(bool v) async {
    safeBrowsing = v;
    notifyListeners();
    await _applyAll();
  }

  Future<void> setIncognito(bool v) async {
    incognito = v;
    notifyListeners();
    // Las WebViews ya vivas no cambian incógnito en caliente: limpiamos su
    // rastro y las nuevas respetan el modo vía initialSettings.
    if (v) {
      try {
        await InAppWebViewController.clearAllCache();
      } catch (_) {}
      await CookieStore.instance.clearAll();
    }
  }

  /// Aplica (o quita) un proxy genérico a TODOS los WebViews de la app.
  /// [scheme] es 'PROXY' (HTTP) o 'SOCKS'.
  Future<bool> setProxy(bool enabled, String hostPort, String scheme) async {
    proxyEnabled = enabled;
    proxyHostPort = hostPort.trim();
    proxyScheme = scheme;
    notifyListeners();
    try {
      final pc = ProxyController.instance();
      if (enabled && proxyHostPort.isNotEmpty) {
        await pc.setProxyOverride(
          settings: ProxySettings(
            proxyRules: [ProxyRule(url: '$scheme $proxyHostPort')],
          ),
        );
      } else {
        await pc.clearProxyOverride();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    for (final t in tabs) {
      t.dispose();
    }
    super.dispose();
  }
}
