import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Una pestaña del browser inappwebview. Solo datos: el estado vivo del
/// WebView vive en [BrowserTabs] vía los controladores que registra
/// [BrowserWebview] al crearse.
class BrowserTab {
  BrowserTab({
    required this.id,
    this.title = 'Nueva pestaña',
    this.url = 'https://duckduckgo.com/',
  });

  final int id;
  String title;
  String url;

  InAppWebViewController? controller;

  void dispose() {
    controller = null;
  }
}
