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

  /// UNA sola vista web reutilizada en normal y maximizado: si se
  /// reconstruye al cambiar de modo, el controlador muere y queda
  /// en blanco (ese era el bug).
  late final Widget _vistaWeb = InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri('about:blank')),
    onWebViewCreated: (c) {
      _web = c;
      c.addJavaScriptHandler(
        handlerName: 'webk',
        callback: _onJs,
      );
    },
    onLoadStop: (_, url) async {
      // Llave de sesión a la página YA cargada (el html
      // estático nunca la trae escrita).
      if (_llaveSesion.isEmpty) return;
      try {
        await _web?.evaluateJavascript(
          source: "window.WEBK_LLAVE='$_llaveSesion';",
        );
      } catch (_) {}
    },
  );

  /// Pantalla completa: solo el WebView (sin botones ni log).
  bool _pantallaCompleta = false;

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

  /// hola.html del asset + puerta/demo embebidos; si falla el asset,
  /// el respaldo embebido.
  Future<void> _cargarIndice() async {
    _indice.registrarTexto('puerta.html', kWebkPuerta);
    _indice.registrarTexto('demo.html', kWebkDemo);
    _add('✓ puerta.html + demo.html embebidos (puente verificado)');
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
  /// - hora: lectura libre (reloj de Dart).
  /// - autorizar: SOLO con la llave de sesión inyectada; si falla → DENEGADO.
  /// - abrir: "oye server, habilitame tal página" → Dart verifica la llave
  ///   y si OK manda la señal + carga el html real. Sin puente verificado
  ///   el contenido no se revela (en Chrome queda bloqueado).
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
      case 'hora':
        return {'dart_ahora': DateTime.now().toIso8601String()};
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
      case 'abrir':
        final ok = _llaveSesion.isNotEmpty &&
            cmd['llave']?.toString() == _llaveSesion;
        final pagina = cmd['pagina']?.toString() ?? '';
        if (!ok || !_indice.paginas.contains(pagina)) {
          if (mounted) _add('✗ abrir "$pagina": DENEGADO (puente no verificado)');
          return 'DENEGADO';
        }
        if (mounted) _add('· Dart habilita "$pagina" (puente OK)');
        _server.autorizarUna();
        _cargarPagina(pagina);
        return 'OK';
      default:
        return 'CMD?';
    }
  }

  /// Carga una página registrada en el WebView de ESTA ventana.
  Future<void> _cargarPagina(String nombre) async {
    if (_web == null) return;
    try {
      await _web!.loadUrl(
        urlRequest: URLRequest(url: WebUri('${_server.baseUrl}/$nombre')),
      );
    } catch (e) {
      _add('✗ cargar: $e');
    }
  }

  /// Señal desde la app + carga en el WebView de ESTA ventana.
  /// Abre maximizado (con Salir para volver a los ejemplos).
  Future<void> _abrirHola() async {
    if (_busy || !_server.corriendo || _web == null) return;
    _server.autorizarUna();
    _add('· señal enviada (1 conexión autorizada)');
    await _cargarPagina('hola.html');
    if (mounted) setState(() => _pantallaCompleta = true);
  }

  /// Puerta: carga el cargador; el CONTENIDO solo entra si el JS
  /// comprueba el puente y Dart lo habilita ("oye server…" → "sí, aquí").
  /// Abre maximizado (con Salir para volver a los ejemplos).
  Future<void> _abrirPuerta() async {
    if (_busy || !_server.corriendo || _web == null) return;
    _server.autorizarUna();
    _add('· puerta cargada (el contenido espera puente verificado)');
    await _cargarPagina('puerta.html');
    if (mounted) setState(() => _pantallaCompleta = true);
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
    // _vistaWeb vive SIEMPRE en el mismo slot del árbol: moverla a otro
    // padre (ej. overlay de pantalla completa) destruye la vista nativa
    // y queda en blanco. En completo se OCULTAN botones/log (mismo slot,
    // tamaño cero) y el Expanded la estira; la pastilla Salir va overlay.
    return Stack(
      children: [
        Column(
          children: [
            Visibility(
              visible: !_pantallaCompleta,
              maintainState: true,
              maintainSize: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Icon(
                      corriendo
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
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
            ),
            Visibility(
              visible: !_pantallaCompleta,
              maintainState: true,
              maintainSize: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          (_busy || corriendo) ? null : _iniciar,
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
                    FilledButton.tonalIcon(
                      onPressed: (!corriendo || !_indiceListo)
                          ? null
                          : _abrirPuerta,
                      icon: const Icon(Icons.verified_user_rounded,
                          size: 18),
                      label: const Text('Puente demo',
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
            ),
            const SizedBox(height: 8),
            Expanded(child: _marcoWeb(borde: !_pantallaCompleta)),
            Visibility(
              visible: !_pantallaCompleta,
              maintainState: true,
              maintainSize: false,
              child: Container(
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
            ),
          ],
        ),
        if (_pantallaCompleta) _pastillaSalir(),
      ],
    );
  }

  /// Pastilla Salir overlay para el modo completo (no toca el WebView).
  Widget _pastillaSalir() {
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text('Salir',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
          IconButton(
            tooltip: 'Salir (volver a ejemplos)',
            icon: const Icon(Icons.close_rounded,
                color: Colors.white, size: 20),
            onPressed: () =>
                setState(() => _pantallaCompleta = false),
          ),
        ]),
      ),
    );
  }

  /// Marco del WebView embebido (modo normal con borde, completo sin).
  /// Usa la instancia única [_vistaWeb] para no perder la página.
  Widget _marcoWeb({bool borde = true}) {
    return Container(
      margin: borde
          ? const EdgeInsets.fromLTRB(12, 0, 12, 0)
          : EdgeInsets.zero,
      decoration: borde
          ? BoxDecoration(
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(10),
              color: Colors.black,
            )
          : const BoxDecoration(color: Colors.black),
      clipBehavior: Clip.antiAlias,
      child: _vistaWeb,
    );
  }
}
