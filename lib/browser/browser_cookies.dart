import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Almacén global de cookies del browser: envuelve el CookieManager del
/// plugin para que el resto de la app no dependa de tipos concretos más
/// de lo necesario. Útil para sesión persistente entre pestañas y para
/// inspección/limpieza desde UI futura.
class CookieStore {
  CookieStore._();
  static final CookieStore instance = CookieStore._();

  Future<List<Cookie>> forUrl(String url) =>
      CookieManager.instance().getCookies(url: WebUri(url));

  Future<void> set(String url, String name, String value) =>
      CookieManager.instance()
          .setCookie(url: WebUri(url), name: name, value: value);

  /// Borra TODAS las cookies manejadas por el WebView. Devuelve si pudo.
  Future<bool> clearAll() async {
    try {
      return await CookieManager.instance().deleteAllCookies();
    } catch (_) {
      return false;
    }
  }

  /// Vuelca legible las cookies de una URL (para consola/debug futuro).
  Future<String> dump(String url) async {
    try {
      final list = await forUrl(url);
      if (list.isEmpty) return '(sin cookies)';
      return list
          .map((c) => '${c.name}=${c.value.length}B')
          .join('\n');
    } catch (e) {
      return 'error: $e';
    }
  }
}
