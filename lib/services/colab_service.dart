import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../colab_cli/colab_auth.dart';
import '../colab_cli/colab_config.dart';
import '../colab_cli/colab_sessions.dart';
// import 'notification_service.dart'; // COMENTADO: no usar, la activa ya existe (777).
import 'nativo.dart';
import 'status_notifier.dart';

/// Servicio Colab: singleton que vive toda la vida de la app.
/// Auth + sesiones. La UI solo lee de acá.
///
/// - SIN autodetect y SIN ping en la app: el ÚNICO ping vive en el
///   servicio nativo `:ping` (proceso independiente). Crear celda =
///   único disparo ([startKeepAlive]); no hay detener, solo la X.
///   Servicio muerto = celda que se quita sola.
/// - Todo aviso va por la notificación que YA existe (Estado 777).
class ColabService {
  static final ColabService _instance = ColabService._();
  factory ColabService() => _instance;
  ColabService._();

  final ColabAuth auth = ColabAuth();
  late final ColabSessions sessions = ColabSessions(auth);

  // Espejo local de lo que pinea el servicio (para mostrar en 777).
  // NO pinea: solo display. El ping real está en el isolate de fondo.

  bool _initialized = false;

  /// Cantidad de sesiones de Colab activas (para el panel de estado).
  int activeSessionCount = 0;

  /// Endpoint que el servicio mantiene en ping (null = nada).
  String? activeEndpoint;

  /// Cuándo empezó el servicio a pinearlo (para el contador de 777).
  DateTime? espejoInicio;

  /// Pings OK contados por el servicio (lo escribe en el estado).
  int espejoPings = 0;

  /// Último error corto del ping nativo ("" = bien). Se muestra en 777.
  String espejoError = '';

  /// Endpoint que pineaba al morir (para desasignar la celda muerta).
  String espejoUltimoEndpoint = '';

  /// Log del último ping (código · latencia · hora). Se ve en el
  /// diálogo de Colab y en la 777.
  String espejoUltimoPing = '';

  /// true si el servicio mantiene algo en ping (espejo local).
  bool get pingActivo => activeEndpoint != null && activeEndpoint!.isNotEmpty;

  Duration get espejoElapsed => espejoInicio != null
      ? DateTime.now().difference(espejoInicio!)
      : Duration.zero;

  /// Ping MANUAL: le dice al servicio NATIVO "mantené este endpoint
  /// en ping" (HTTP keep-alive en Kotlin, igual que el CLI). Prende el
  /// servicio a pedido (sin celda no hay servicio).
  /// Recarga tokens (el login del diálogo usa otra instancia de auth).
  Future<void> startKeepAlive(String endpoint) async {
    if (endpoint.isEmpty) return;
    try {
      await auth.loadTokens();
    } catch (e) {
      espejoError = 'no abre tokens: $e';
      return;
    }
    final t = auth.tokens;
    if (t == null) {
      // Visible en el diálogo (antes tragado: "se activa y ya").
      espejoError = 'no autenticado en Colab: hacé login primero';
      return;
    }
    activeEndpoint = endpoint;
    espejoInicio = DateTime.now();
    espejoPings = 0;
    espejoError = '';
    espejoUltimoPing = '';
    // Sin exención la ROM mata el servicio al barrer y no revive
    // (service_flu sobrevive por esto, no por código). Se pide una vez.
    try {
      await Nativo.sinLimites();
    } catch (_) {}
    // Sin servicio no hay ping: prender el NATIVO primero, esperar que
    // arranque y recién ordenarle el ping.
    await Nativo.prender();
    await Future.delayed(const Duration(milliseconds: 1500));
    try {
      await Nativo.startPing(
        endpoint: endpoint,
        accessToken: t.accessToken,
        refreshToken: t.refreshToken,
        expiryMs: t.expiry.millisecondsSinceEpoch,
        clientId: ColabConfig.clientId,
        clientSecret: ColabConfig.clientSecret,
      );
    } catch (_) {}
    StatusNotifier.instance.reanudar();
    StatusNotifier.instance.refresh();
  }

  // ELIMINADO stopKeepAlive: no hay botón detener. Única salida = X de
  // la 888. Servicio muerto = celda que se quita sola (ver diálogo).
  // Se deja el hueco sin borrar.

  /// Inicializar: carga tokens, engancha el empuje de token fresco al
  /// servicio y recupera el espejo de lo que ya pineaba.
  /// Nada más: el servicio se crea al crear celda, punto.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // App viva → cada refresh Dart empuja el token al servicio `:ping`
    // (pisa sin resetear). App muerta → el servicio se autoabastece.
    ColabAuth.onTokensChanged = (t) async {
      try {
        await Nativo.updateToken(
          accessToken: t.accessToken,
          refreshToken: t.refreshToken,
          expiryMs: t.expiry.millisecondsSinceEpoch,
        );
      } catch (_) {}
    };
    await auth.loadTokens();
    await _recuperarEspejo();
  }

  /// Lee el estado que escribe el servicio NATIVO: si sigue vivo, la
  /// 777 lo muestra sin arrancar ningún ping en la app. Primero el
  /// canal nativo (siempre fresco), después el archivo legacy.
  /// Si el canal responde (mapa no vacío) se le cree: vivo → espejo,
  /// muerto → espejo en limpio (no mostrar fantasma).
  Future<void> _recuperarEspejo() async {
    try {
      final e = await Nativo.estado();
      if (e.isNotEmpty) {
        espejoUltimoEndpoint = '${e['ultimoEndpoint'] ?? ''}';
        if (e['vivo'] == true && '${e['endpoint'] ?? ''}'.isNotEmpty) {
          activeEndpoint = '${e['endpoint']}';
          final ms = (e['inicioMs'] as int?) ?? 0;
          espejoInicio = ms > 0
              ? DateTime.fromMillisecondsSinceEpoch(ms)
              : DateTime.now();
          espejoPings = (e['pingsOk'] as int?) ?? 0;
          espejoError = '${e['ultimoError'] ?? ''}';
          espejoUltimoPing = '${e['ultimoPing'] ?? ''}';
        } else {
          activeEndpoint = null;
          espejoInicio = null;
          espejoPings = 0;
          // Muerto: mostrar POR QUÉ paró (lo informa el nativo).
          final up = '${e['ultimaParada'] ?? ''}';
          espejoError = up.isNotEmpty ? 'paró: $up' : '';
          espejoUltimoPing = '${e['ultimoPing'] ?? ''}';
        }
        return;
      }
    } catch (_) {}
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/colab/colab_ping_estado.json');
      if (!await f.exists()) return;
      final d = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (d['vivo'] != true) return;
      final ep = '${d['endpoint'] ?? ''}';
      if (ep.isEmpty) return;
      final cuando = DateTime.tryParse('${d['cuando'] ?? ''}');
      // Fresco = el servicio escribió hace menos de 5 min (sigue vivo).
      if (cuando == null ||
          DateTime.now().difference(cuando) > const Duration(minutes: 5)) {
        return;
      }
      activeEndpoint = ep;
      espejoInicio = DateTime.tryParse('${d['inicio'] ?? ''}');
      espejoPings = (d['pingsOk'] as int?) ?? 0;
      espejoError = '';
    } catch (_) {}
  }

  /// Relee el espejo nativo (para la 777 cada 3s): pings y error vivos,
  /// sin arrancar nada en la app.
  Future<void> refrescarEspejo() => _recuperarEspejo();

  // COMENTADO: autodetect desactivado, el ping es solo manual.
  // Se deja sin borrar.
  bool autoDetect = false;
  // Timer? _watchdog;
  // void _arrancarWatchdog() {}
  // Future<void> _vigilar() async {}
}
