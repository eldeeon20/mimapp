import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'status_notifier.dart';

/// Handler para cuando tocan "Salir" con la app EN SEGUNDO PLANO.
/// Obligatorio top-level con vm:entry-point; sin esto el botón no hace
/// nada salvo que la app esté abierta en primer plano.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  if (response.actionId == 'exit') {
    NotificationService.exitApp();
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'default_channel';
  static const _channelName = 'Notificaciones';

  /// Canal del servicio en primer plano (id = el de bootstrap._notifChannelId).
  static const _serviceChannelId = 'pr_app_channel';

  /// ID de la notificación de servicio en primer plano (debe coincidir con
  /// el foregroundServiceNotificationId de flutter_background_service).
  static const serviceNotificationId = 888;

  /// SALIR = KILL TOTAL. Detiene el servicio en primer plano, cancela
  /// TODAS las notificaciones (servicio 888, estado 777, descargas 9000+)
  /// y mata el proceso de la app. Funciona igual desde primer o segundo
  /// plano (es static puro, sin UI).
  static Future<void> exitApp() async {
    // 1) parar el foreground service
    try {
      FlutterBackgroundService().invoke('stop');
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));

    // 2) cancelar todas las notificaciones persistentes conocidas
    for (final id in [
      serviceNotificationId,
      StatusNotifier.notificationId,
      ...List.generate(50, (i) => 9000 + i), // rango de descargas
    ]) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }

    // 3) cerrar la app de verdad: quitar tarea + kill del proceso
    try {
      await SystemNavigator.pop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));
    exit(0);
  }

  static Future<void> init({
    Future<void> Function()? onExitAction,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_bg_service_small'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.actionId == 'exit') {
          // App en primer plano: mismo kill total.
          if (onExitAction != null) {
            onExitAction();
          } else {
            exitApp();
          }
        }
      },
      // Camino CRÍTICO: tocar "Salir" con la app en segundo plano.
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundHandler,
    );

    // Crear canal en Android
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Canal principal de la app',
            importance: Importance.high,
          ),
        );

    // Pedir permiso en Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static FlutterLocalNotificationsPlugin get plugin => _plugin;
  static String get channelId => _channelId;
  static String get channelName => _channelName;

  /// Notificación de servicio en primer plano con botón "Salir".
  /// Debe mostrarse con el mismo id que usa flutter_background_service.
  static Future<void> showServiceNotification() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _serviceChannelId,
        'Servicio',
        channelDescription: 'Servicio en primer plano de la app',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        showWhen: false,
        actions: [
          AndroidNotificationAction(
            'exit',
            '✕',
            showsUserInterface: false,
          ),
        ],
      ),
    );
    await _plugin.show(
      id: serviceNotificationId,
      title: 'Secure App',
      body: 'Servicio activo · toca ✕ para salir',
      notificationDetails: details,
    );
  }

  // ------------------------------------------------------------- descargas

  static int _downloadSeq = 0;

  /// Id único para una notificación de descarga (9000+).
  static int nextDownloadId() => 9000 + (++_downloadSeq);

  /// Muestra/actualiza una notificación de progreso en el canal principal.
  /// [progress] 0..1; null = indeterminada. Con [finished] la notificación
  /// deja de ser ongoing (queda como resultado final).
  static Future<void> showDownloadProgress({
    required int id,
    required String title,
    required String body,
    double? progress,
    bool finished = false,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Progreso de descargas',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: !finished,
        onlyAlertOnce: true,
        showWhen: false,
        autoCancel: finished,
        showProgress: progress != null,
        maxProgress: 100,
        progress: progress == null ? 0 : (progress.clamp(0, 1) * 100).round(),
        indeterminate: progress == null && !finished,
      ),
    );
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (_) {}
  }

  /// Quita una notificación de descarga terminada/cancelada.
  static Future<void> cancelDownload(int id) =>
      _plugin.cancel(id: id);
}
