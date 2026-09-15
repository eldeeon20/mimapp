import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/webk/webk.dart';
import 'webk/caja_log.dart';
import 'webk/controles_webk.dart';
import 'webk/marco_web.dart';
import 'webk/menu_paginas.dart';
import 'webk/pastilla_salir.dart';

/// Test de WebK: servidor HTTP local + WebView EMBEBIDO en esta ventana
/// (no usa el browser overlay del botón Web).
///
/// Flujo: Iniciar server → menú "Páginas" (manda la señal [autorizarUna]
/// y carga la página en el WebView de acá). El server manda el reto js,
/// espera el ping y recién ahí sirve el html; sin señal responde 403.
///
/// Esta pantalla es SOLO estado + cableado: server, índice, llave,
/// conectores (puentes/), historial y ajustes. La UI vive en webk/
/// (controles, menú, log, pastilla, marco) y las páginas en
/// services/webk/paginas/. El puente JS→Dart vive en
/// services/webk/puentes/ (un conector por archivo).
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
  /// Ajustes vivos del WebView (imágenes/cookies): se mutan y re-aplican
  /// sin recrear la vista.
  final _ajustesWeb = InAppWebViewSettings(
    javaScriptEnabled: true,
    mediaPlaybackRequiresUserGesture: false,
  );

  /// Menú de páginas: overlay que se cierra al tocar fuera o con atrás.
  bool _menuAbierto = false;

  /// Historial de visitas (solo memoria; se borra al salir/detener).
  final _historial = <Map<String, String>>[];

  bool _bloqImg = false;
  bool _bloqCookies3ros = false;

  /// Conectores del puente JS→Dart (uno por archivo en puentes/):
  /// la pantalla SOLO registra; cada conector atiende sus comandos.
  /// 1000 páginas = 1000 archivos, este archivo no crece.
  late final _puentes = RegistroPuentes()
    ..registrar(PuenteNucleo(
      server: _server,
      indice: _indice,
      leerLlave: () => _llaveSesion,
      log: _logPuente,
      cargar: _cargarPagina,
    ))
    ..registrar(PuenteAgenda(
      leerLlave: () => _llaveSesion,
      log: _logPuente,
    ))
    ..registrar(PuenteBuilder(
      indice: _indice,
      leerLlave: () => _llaveSesion,
      log: _logPuente,
    ));

  void _logPuente(String s) {
    if (mounted) _add(s);
  }

  late final Widget _vistaWeb = InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri('about:blank')),
    initialSettings: _ajustesWeb,
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
    _puentes.cerrarTodos();
    _server.detener();
    super.dispose();
  }

  void _add(String s) => setState(() {
        _log.add(s);
        if (_log.length > 40) _log.removeAt(0);
      });

  /// Páginas como ARCHIVOS en paginas/ (a futuro serán muchas):
  /// se cargan del asset al índice; nada de html suelto en Dart.
  static const _archivos = [
    'hola.html',
    'puerta.html',
    'demo.html',
    'pagina2.html',
    'app.html',
    'twitch.html',
    'face.html',
    'agenda-sql.html',
  ];

  /// Entradas de webapps: cada app su carpeta en webapp/.
  /// SOLO los puntos de entrada (para el menú); el resto de archivos
  /// (css/js/json) el servidor los trae a demanda vía [cargaAsset].
  static const _entradasWebapp = [
    'webapp/builder/builder.html',
  ];

  Future<void> _cargarIndice() async {
    // Fallback a demanda: cualquier ruta bajo webk/ se sirve del asset
    // sin listarla acá (con reto+ping+pase igual que las registradas).
    _indice.cargaAsset =
        (ruta) => rootBundle.loadString('lib/services/webk/$ruta');
    var ok = 0;
    var total = 0;
    Future<void> cargarUno(String asset, String nombre) async {
      total++;
      try {
        final texto =
            await rootBundle.loadString('lib/services/webk/$asset');
        _indice.registrarTexto(nombre, texto);
        ok++;
      } catch (e) {
        _add('✗ asset $asset no cargó ($e)');
      }
    }

    for (final n in _archivos) {
      await cargarUno('paginas/$n', n);
    }
    for (final n in _entradasWebapp) {
      await cargarUno(n, n);
    }
    _add('✓ índice: $ok/$total páginas (reto+ping antes de servir)');
    if (mounted) setState(() => _indiceListo = ok > 0);
  }

  Future<void> _iniciar() async {
    if (_busy || _server.corriendo) return;
    setState(() => _busy = true);
    try {
      final puerto = await _server.iniciar();
      _llaveSesion =
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
          '${math.Random().nextInt(1 << 32).toRadixString(16)}';
      _server.llaveSesion = _llaveSesion; // el ping del reto la exige
      _add('✓ server en ${_server.baseUrl} (puerto $puerto, loopback)');
    } catch (e) {
      _add('✗ iniciar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Puente JS→Dart ('webk'): deriva a SU conector (puentes/).
  /// Acá NO hay lógica de comandos: cada conector atiende lo suyo.
  Future<dynamic> _onJs(List<dynamic> args) async {
    final cmd = args.isNotEmpty && args[0] is Map
        ? Map<String, dynamic>.from(args[0] as Map)
        : <String, dynamic>{};
    return _puentes.atender(cmd);
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
  /// El server manda el reto js, espera el ping y recién ahí sirve el html.
  /// Abre maximizado (con Salir para volver a los ejemplos).
  Future<void> _abrirPagina(String nombre) async {
    if (_busy || !_server.corriendo || _web == null) return;
    _server.autorizarUna();
    _add('· "$nombre": señal enviada (reto+ping antes del html)');
    if (_historial.isEmpty || _historial.last['pagina'] != nombre) {
      _historial.add({
        'pagina': nombre,
        'cuando': DateTime.now().toString().substring(11, 19),
      });
      if (_historial.length > 30) _historial.removeAt(0);
    }
    if (_menuAbierto) setState(() => _menuAbierto = false);
    await _cargarPagina(nombre);
    if (mounted) setState(() => _pantallaCompleta = true);
  }

  /// Señal extra sin abrir nada (para que Chrome la gaste, no existe):
  /// habilita UNA conexión más.
  void _autorizarOtra() {
    _server.autorizarUna();
    _add('· señal extra (1 conexión más)');
  }

  /// Imágenes sí/no (como web): re-aplica ajustes sin recrear la vista.
  Future<void> _cambiarImg(bool v) async {
    setState(() => _bloqImg = v);
    _ajustesWeb.blockNetworkImage = v;
    try {
      await _web?.setSettings(settings: _ajustesWeb);
    } catch (_) {}
    _add(v ? '· imágenes bloqueadas' : '· imágenes permitidas');
  }

  /// Cookies de terceros sí/no (como web).
  Future<void> _cambiarCookies3ros(bool v) async {
    setState(() => _bloqCookies3ros = v);
    _ajustesWeb.thirdPartyCookiesEnabled = !v;
    try {
      await _web?.setSettings(settings: _ajustesWeb);
    } catch (_) {}
    _add(v ? '· cookies de terceros bloqueadas' : '· cookies de terceros permitidas');
  }

  /// Borra TODAS las cookies del WebView (al salir no queda nada).
  Future<void> _limpiarCookies() async {
    try {
      await CookieManager.instance().deleteAllCookies();
      _add('· cookies borradas');
    } catch (e) {
      _add('✗ cookies: $e');
    }
  }

  /// Prueba: SIN segundo plano (no como web). Al salir se detiene el
  /// server + se borran cookies e historial (no queda nada).
  Future<void> _detener() async {
    await _limpiarCookies();
    _historial.clear();
    _puentes.cerrarTodos(); // conectores con algo abierto (agenda-sql)
    await _server.detener();
    _llaveSesion = '';
    _add('· server detenido (llave quemada, cookies e historial fuera)');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final corriendo = _server.corriendo;
    return _cuerpo(corriendo);
  }

  /// Cuerpo con PopScope: si el menú está abierto, atrás lo cierra
  /// (no sale de la pantalla). Tocar fuera del menú también lo cierra.
  Widget _cuerpo(bool corriendo) {
    return PopScope(
      canPop: !_menuAbierto,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _menuAbierto) {
          setState(() => _menuAbierto = false);
        }
      },
      child: _pila(corriendo),
    );
  }

  Widget _pila(bool corriendo) {
    // _vistaWeb vive SIEMPRE en el mismo slot del árbol: moverla a otro
    // padre destruye la vista nativa y queda en blanco. En completo se
    // OCULTAN controles/log y el Expanded la estira.
    return Stack(
      children: [
        Column(
          children: [
            Visibility(
              visible: !_pantallaCompleta,
              maintainState: true,
              maintainSize: false,
              child: ControlesWebk(
                corriendo: corriendo,
                busy: _busy,
                indiceListo: _indiceListo,
                baseUrl: _server.baseUrl,
                stats:
                    'srv ${_server.servidas} · rej ${_server.rechazadas} · reto ${_server.retosCaidos}',
                bloqImg: _bloqImg,
                bloqCookies3ros: _bloqCookies3ros,
                onIniciar: _iniciar,
                onPaginas: () => setState(() => _menuAbierto = true),
                onBuilder: () =>
                    _abrirPagina('webapp/builder/builder.html'),
                onAutorizarOtra: _autorizarOtra,
                onDetener: _detener,
                onCambiarImg: () => _cambiarImg(!_bloqImg),
                onCambiarCookies3ros: () =>
                    _cambiarCookies3ros(!_bloqCookies3ros),
                onLimpiarCookies: _limpiarCookies,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
                child: MarcoWeb(
                    vista: _vistaWeb, borde: !_pantallaCompleta)),
            Visibility(
              visible: !_pantallaCompleta,
              maintainState: true,
              maintainSize: false,
              child: CajaLog(lineas: _log),
            ),
          ],
        ),
        if (_pantallaCompleta)
          PastillaSalir(
              onSalir: () => setState(() => _pantallaCompleta = false)),
        if (_menuAbierto)
          MenuPaginas(
            paginas: _indice.paginas
                .where((p) => p.endsWith('.html'))
                .toList(),
            historial: _historial,
            onElegir: _abrirPagina,
            onCerrar: () => setState(() => _menuAbierto = false),
            onBorrarHistorial: () => setState(() => _historial.clear()),
          ),
      ],
    );
  }
}
