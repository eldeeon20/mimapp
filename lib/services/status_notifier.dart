import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../ai/laurelia_chat.dart';
import '../services/colab_service.dart';
import 'notification_service.dart';

/// Notificación de ESTADO de la app (estilo Cleaner / Snaptube):
/// un "dashboard" informativo persistente, aparte del servicio en primer
/// plano y aparte de la notificación de reproducción de medios.
///
/// Muestra: consumo de datos REAL si existe (↓/↑), estado de conexión,
/// estado de Colab y un mensaje extra (tokens generados por Laurelia IA).
///
/// Sin números simulados: ↓/↑ se muestran solo si hay bytes reales cargados.
class StatusNotifier {
  static final StatusNotifier instance = StatusNotifier._();
  StatusNotifier._();

  /// ID público para que el botón Salir pueda cancelarla desde cualquier
  /// isolate (el panel "Estado de Secure App").
  static const notificationId = 777;
  static const _id = notificationId;
  static const _channelId = 'pr_app_status';
  static const _channelName = 'Estado de la app';

  Timer? _timer;

  // Contadores reales (los alimenta una fuente externa vía refresh()).
  int downloadedBytes = 0;
  int uploadedBytes = 0;
  String connection = 'WiFi';
  String extra = 'Sin actividad';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Crear canal propio.
    await NotificationService.plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Panel de estado de la app',
            importance: Importance.low,
            showBadge: false,
          ),
        );

    await show();

    // Sin tráfico simulado: solo re-pinta por si cambió el estado real.
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      _safeShow();
    });
  }

  /// Refresca con estado real (Colab, Laurelia) y re-pinta la notificación.
  void refresh() {
    final cs = ColabService();
    // Laurelia: tokens generados (contador estático).
    final tokens = LaureliaChat.generatedTokens;

    final active = cs.keepAlive.isRunning;
    final count = cs.activeSessionCount;
    final colabLine = active
        ? 'Colab: ACTIVO (${cs.activeEndpoint ?? ''})'
        : (count > 0 ? 'Colab: $count sesión(es)' : 'Colab: inactivo');

    extra = '$colabLine · Laurelia: $tokens tokens';
    connection = active ? 'Online (Colab)' : 'WiFi';

    show();
  }

  Future<void> show() async => _safeShow();

  Future<void> _safeShow() async {
    // ↓/↑ solo si hay bytes reales; nada de números de mentira.
    final net = (downloadedBytes > 0 || uploadedBytes > 0)
        ? '↓ ${_fmt(downloadedBytes)}   ↑ ${_fmt(uploadedBytes)}\n'
        : '';
    final body = '$net Conexión: $connection\n$extra';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Panel de estado de la app',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        showWhen: false,
        styleInformation: BigTextStyleInformation(body),
      ),
    );
    try {
      await NotificationService.plugin.show(
        id: _id,
        title: 'Estado de Secure App',
        body: body,
        notificationDetails: details,
      );
    } catch (_) {}
  }

  Future<void> cancel() async {
    _timer?.cancel();
    await NotificationService.plugin.cancel(id: _id);
  }

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
