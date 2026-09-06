import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/browser_downloads.dart';
import 'browser_tab.dart';
import 'browser_tabs.dart';

/// Envuelve UN InAppWebView (una pestaña): registra su controlador en el
/// gestor, propaga progreso/url/título y deriva descargas al gestor global.
class BrowserWebview extends StatefulWidget {
  const BrowserWebview({
    super.key,
    required this.tabs,
    required this.tab,
  });

  final BrowserTabs tabs;
  final BrowserTabLike tab;

  @override
  State<BrowserWebview> createState() => _BrowserWebviewState();
}

class _BrowserWebviewState extends State<BrowserWebview> {
  double _progress = 1;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Column(children: [
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.tab.url)),
            initialSettings: widget.tabs.currentWebViewSettings(),
            onWebViewCreated: (c) =>
                widget.tabs.registerController(widget.tab.id, c),
            onProgressChanged: (_, p) {
              if (mounted) setState(() => _progress = p / 100);
            },
            onLoadStop: (_, url) {
              if (url != null) {
                widget.tabs.updateUrl(widget.tab.id, url.toString());
              }
            },
            onTitleChanged: (_, title) =>
                widget.tabs.rename(widget.tab.id, title ?? ''),
            onDownloadStartRequest: (_, req) {
              DownloadManager.instance.start(
                req.url.toString(),
                suggestedName: req.suggestedFilename,
              );
            },
          ),
        ),
        if (_progress < 1)
          LinearProgressIndicator(value: _progress, minHeight: 2),
      ]),
    ]);
  }
}
