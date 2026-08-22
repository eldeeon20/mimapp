import 'dart:async';
import 'dart:math';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../ai/laurelia_chat.dart';
import '../services/colab_service.dart';
import 'notification_service.dart';

/// Notificación de ESTADO de la app (estilo Cleaner / Snaptube):
/// un "dashboard" informativo persistente, aparte del servicio en primer
/// plano y aparte de la notificación de reproducción de medios.
///
/// Muestra: consumo de datos (↓/↑), estado de conexión, estado de Colab y
/// un mensaje extra (tokens generados por Laurelia IA).
///
/// Los datos de consumo son simulados (mock) salvo donde se conecte con
/// estado real (Colab, Laurelia). La clase está preparada para alimentarse
/// de fuentes reales vía [refresh].
class StatusNotifier {
  static final StatusNotifier instance = StatusNotifier._();
  StatusNotifier._();

  static const _id = 777;
  static const _channelId = 'pr_app_status';
  static const _channelName = 'Estado de la app';

  final _rnd = Random();
  Timer? _timer;

  // Campos editables (mock o reales).
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

    // Simula tráfico de red para que el panel se vea "vivo".
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      downloadedBytes += _rnd.nextInt(400) * 1024;
      uploadedBytes += _rnd.nextInt(120) * 1024;
      _safeShow();
    });
  }

  /// Refresca con estado real (Colab, Laurelia) y re-pinta la notificación.
  void refresh() {
    // Colab: cantidad de sesiones activas.
    final count = ColabService().activeSessionCount;
    // Laurelia: tokens generados (contador estático).
    final tokens = LaureliaChat.generatedTokens;

    extra = count > 0
        ? 'Colab: $count sesión(es) · Laurelia: $tokens tokens'
        : 'Laurelia: $tokens tokens generados';
    connection = count > 0 ? 'Online (Colab)' : 'WiFi';

    show();
  }

  Future<void> show() async => _safeShow();

  Future<void> _safeShow() async {
    final body = '''↓ ${_fmt(downloadedBytes)}   ↑ ${_fmt(uploadedBytes)}
Conexión: $connection
$extra''';

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
