import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Contrato mínimo de pestaña para desacoplar widgets de la clase concreta.
abstract class BrowserTabLike {
  int get id;
  String get url;
}

/// Una pestaña del browser inappwebview. Solo datos: el estado vivo del
/// WebView vive en [BrowserTabs] vía los controladores que registra
/// [BrowserWebview] al crearse.
class BrowserTab implements BrowserTabLike {
  BrowserTab({
    required this.id,
    this.title = 'Nueva pestaña',
    this.url = 'https://duckduckgo.com/',
  });

  @override
  final int id;
  String title;
  @override
  String url;

  InAppWebViewController? controller;

  void dispose() {
    controller = null;
  }
}
