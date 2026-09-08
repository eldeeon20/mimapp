import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/webk/index.dart';
import '../services/webk/server.dart';

/// Test de WebK: servidor HTTP local + WebView EMBEBIDO en esta ventana
/// (no usa el browser overlay del botón Web).
///
/// Flujo: Iniciar server → "Abrir hola" (manda la señal [autorizarUna] y
/// carga la página en el WebView de acá). Cada conexión necesita su señal;
/// sin señal el server responde 403 y cierra (sordo al sondeo).
class WebkTestScreen extends StatefulWidget {
  const WebkTestScreen({super.key});

  @override
  State<WebkTestScreen> createState() => _WebkTestScreenState();
}

class _WebkTestScreenState extends State<WebkTestScreen> {
  final _server = WebkServer();
  final _indice = WebkIndex();
  InAppWebViewController? _web;
  final _log = <String>[];
  bool _busy = false;
  bool _indiceListo = false;
  double _progreso = 1;

  /// Llave de sesión para el puente JS→Dart (se inyecta en la página tras
  /// cargarla; el html estático nunca la contiene). Sin llave válida no
  /// hay autorización, aunque la página la pida.
  String _llaveSesion = '';

  @override
  void initState() {
    super.initState();
    _server.resolvedor = _indice.resolver;
    _cargarIndice();
  }

  @override
  void dispose() {
    _server.detener();
    super.dispose();
  }

  void _add(String s) => setState(() {
        _log.add(s);
        if (_log.length > 40) _log.removeAt(0);
      });

  /// hola.html del asset; si falla, el respaldo embebido.
  Future<void> _cargarIndice() async {
    try {
      final html =
          await rootBundle.loadString('lib/services/webk/hola.html');
      _indice.registrarTexto('hola.html', html);
      _add('✓ hola.html cargado del asset (${html.length} chars)');
    } catch (e) {
      _indice.registrarTexto('hola.html', kWebkHolaRespaldo);
      _add('⚠ asset no cargó ($e), uso respaldo embebido');
    }
    if (mounted) setState(() => _indiceListo = true);
  }

  Future<void> _iniciar() async {
    if (_busy || _server.corriendo) return;
    setState(() => _busy = true);
    try {
      final puerto = await _server.iniciar();
      _llaveSesion =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
          '${math.Random().nextInt(1 << 32).toRadixString(16)}';
      _add('✓ server en ${_server.baseUrl} (puerto $puerto, loopback)');
    } catch (e) {
      _add('✗ iniciar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puente JS→Dart ('webk'): la página pide, Dart autentica y decide.
  /// - estado: lectura libre (stats del server).
  /// - autorizar: SOLO con la llave de sesión inyectada; si falla → DENEGADO.
  dynamic _onJs(List<dynamic> args) {
    final cmd = args.isNotEmpty && args[0] is Map
        ? Map<String, dynamic>.from(args[0] as Map)
        : <String, dynamic>{};
    switch (cmd['cmd']?.toString() ?? '') {
      case 'estado':
        return {
          'servidas': _server.servidas,
          'rechazadas': _server.rechazadas,
          'puerto': _server.puerto,
        };
      case 'autorizar':
        final ok = _llaveSesion.isNotEmpty &&
            cmd['llave']?.toString() == _llaveSesion;
        if (mounted) {
          _add(ok
              ? '· la página pidió autorización (llave OK)'
              : '✗ la página pidió autorización (llave MAL)');
        }
        if (ok) _server.autorizarUna();
        return ok ? 'OK' : 'DENEGADO';
      default:
        return 'CMD?';
    }
  }

  /// Señal desde la app + carga en el WebView de ESTA ventana.
  Future<void> _abrirHola() async {
    if (_busy || !_server.corriendo || _web == null) return;
    _server.autorizarUna();
    _add('· señal enviada (1 conexión autorizada)');
    try {
      await _web!.loadUrl(
        urlRequest:
            URLRequest(url: WebUri('${_server.baseUrl}/hola.html')),
      );
    } catch (e) {
      _add('✗ cargar: $e');
    }
  }

  Future<void> _detener() async {
    await _server.detener();
    _llaveSesion = '';
    _add('· server detenido (llave de sesión quemada)');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final corriendo = _server.corriendo;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Icon(
                corriendo ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: corriendo ? Colors.greenAccent : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  corriendo ? _server.baseUrl : 'server detenido',
                  style: const TextStyle(
                      fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'srv ${_server.servidas} · rej ${_server.rechazadas}',
                style: const TextStyle(
                    fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed: (_busy || corriendo) ? null : _iniciar,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Iniciar',
                    style: TextStyle(fontSize: 13)),
              ),
              FilledButton.icon(
                onPressed: (!corriendo || !_indiceListo)
                    ? null
                    : _abrirHola,
                icon: const Icon(Icons.open_in_browser_rounded,
                    size: 18),
                label: const Text('Abrir hola',
                    style: TextStyle(fontSize: 13)),
              ),
              OutlinedButton.icon(
                onPressed: corriendo
                    ? () {
                        _server.autorizarUna();
                        _add('· señal extra (1 conexión más)');
                      }
                    : null,
                icon: const Icon(Icons.key_rounded, size: 18),
                label: const Text('Autorizar otra',
                    style: TextStyle(fontSize: 13)),
              ),
              OutlinedButton.icon(
                onPressed: corriendo ? _detener : null,
                icon: const Icon(Icons.stop_rounded, size: 18),
                label: const Text('Detener',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(10),
              color: Colors.black,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(
                      url: WebUri('about:blank')),
                  onWebViewCreated: (c) {
                    _web = c;
                    c.addJavaScriptHandler(
                      handlerName: 'webk',
                      callback: _onJs,
                    );
                  },
                  onProgressChanged: (_, p) {
                    if (mounted) {
                      setState(() => _progreso = p / 100);
                    }
                  },
                  onLoadStop: (_, url) async {
                    // Llave de sesión a la página YA cargada (el html
                    // estático nunca la trae escrita).
                    if (_llaveSesion.isEmpty) return;
                    try {
                      await _web?.evaluateJavascript(
                        source:
                            "window.WEBK_LLAVE='$_llaveSesion';",
                      );
                    } catch (_) {}
                  },
                ),
                if (_progreso < 1)
                  const LinearProgressIndicator(
                      value: null, minHeight: 2),
              ],
            ),
          ),
        ),
        Container(
          height: 90,
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[800]!),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              _log.isEmpty ? '· log ·' : _log.join('\n'),
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }
}
