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
/// - SIN autodetect y SIN ping en la app: el ÚNICO ping vive en el isolate
///   del servicio (ColabPingMotor en bootstrap). La app solo le ordena
///   "mantené esto en ping" vía [startKeepAlive] y "cortá" vía
///   [stopKeepAlive]. Si la app se cierra, el servicio sigue pineando.
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
    } catch (_) {}
    final t = auth.tokens;
    if (t == null) throw StateError('No autenticado en Colab');
    activeEndpoint = endpoint;
    espejoInicio = DateTime.now();
    espejoPings = 0;
    // Sin servicio no hay ping: prender el NATIVO primero, esperar que
    // arranque y recién ordenarle el ping.
    await Nativo.prender();
    await Future.delayed(const Duration(milliseconds: 1500));
    try {
      await Nativo.startPing(
        endpoint: endpoint,
        accessToken: t.accessToken,
        refreshToken: t.refreshToken,
        expiryIso: t.expiry.toIso8601String(),
        clientId: ColabConfig.clientId,
        clientSecret: ColabConfig.clientSecret,
      );
    } catch (_) {}
    StatusNotifier.instance.reanudar();
    StatusNotifier.instance.refresh();
  }

  /// Corta el ping y APAGA el servicio nativo (sin celda no queda nada).
  /// Solo acción explícita del usuario. No mata la app.
  Future<void> stopKeepAlive() async {
    try {
      await Nativo.stopPing();
    } catch (_) {}
    activeEndpoint = null;
    espejoInicio = null;
    espejoPings = 0;
    StatusNotifier.instance.refresh();
    // Sin celda el servicio no tiene por qué quedar: pararlo también.
    try {
      await Nativo.stop();
    } catch (_) {}
  }

  /// Inicializar: carga tokens y recupera el espejo de lo que el
  /// servicio ya pineaba (si la app se cerró y el servicio siguió).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await auth.loadTokens();
    await _recuperarEspejo();
  }

  /// Lee el estado que escribe el servicio NATIVO: si sigue vivo, la
  /// 777 lo muestra sin arrancar ningún ping en la app. Primero el
  /// canal nativo (siempre fresco), después el archivo legacy.
  Future<void> _recuperarEspejo() async {
    try {
      final e = await Nativo.estado();
      if (e['vivo'] == true && '${e['endpoint'] ?? ''}'.isNotEmpty) {
        activeEndpoint = '${e['endpoint']}';
        final ms = (e['inicioMs'] as int?) ?? 0;
        espejoInicio = ms > 0
            ? DateTime.fromMillisecondsSinceEpoch(ms)
            : DateTime.now();
        espejoPings = (e['pingsOk'] as int?) ?? 0;
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
    } catch (_) {}
  }

  // COMENTADO: autodetect desactivado, el ping es solo manual.
  // Se deja sin borrar.
  bool autoDetect = false;
  // Timer? _watchdog;
  // void _arrancarWatchdog() {}
  // Future<void> _vigilar() async {}
}
