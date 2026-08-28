import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
  /// aplica de una vez el estado JS global actual.
  void registerController(int tabId, InAppWebViewController c) {
    _controllers[tabId] = c;
    setJs(jsEnabled);
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

  /// Cambia el JavaScript global y lo aplica en vivo a cada WebView vivo.
  Future<void> setJs(bool enabled) async {
    jsEnabled = enabled;
    for (final c in _controllers.values) {
      try {
        await c.setSettings(
            settings: InAppWebViewSettings(javaScriptEnabled: enabled));
      } catch (_) {}
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in tabs) {
      t.dispose();
    }
    super.dispose();
  }
}
