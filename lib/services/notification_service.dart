import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'servicio_fondo.dart';
import 'status_notifier.dart';

/// NOTIFICACIONES (archivo separado del servicio).
/// Handler para cuando tocan "Salir" con la app EN SEGUNDO PLANO.
/// Obligatorio top-level con vm:entry-point; sin esto el botón no hace
/// nada salvo que la app esté abierta en primer plano.
///
/// OJO: esto corre en OTRO isolate (el de fondo de FLN): los static
/// están vacíos acá. Por eso NO usa el callback [salidaFondo] (nulo
/// en este isolate → antes caía al exit(0) pelado: mataba sin parar
/// el servicio y Android lo resucitaba). Llama directo a
/// ServicioFondo.salir con plugins registrados.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  if (response.actionId == 'exit') {
    DartPluginRegistrant.ensureInitialized();
    ServicioFondo.salir();
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

  /// Callback de salida que pone bootstrap (ServicioFondo.salir).
  /// Así este archivo no importa nada del servicio.
  static Future<void> Function()? salidaFondo;

  /// Da de baja todas las notificaciones persistentes conocidas.
  /// La docu da de baja así: cancel(id) una por una. La 888 del
  /// servicio NO sale con cancel mientras el servicio corre: por eso
  /// ServicioFondo primero para el servicio y espera su confirmación.
  static Future<void> cancelPersistentes() async {
    for (final id in [
      serviceNotificationId,
      StatusNotifier.notificationId,
      ...List.generate(50, (i) => 9000 + i), // rango de descargas
    ]) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
  }

  /// Cierra la app de verdad: quitar tarea + kill del proceso.
  static Future<void> matarProceso() async {
    try {
      await SystemNavigator.pop();
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));
    exit(0);
  }

  static Future<void> init({
    Future<void> Function()? onExitAction,
    Future<void> Function()? onExitBg,
  }) async {
    salidaFondo = onExitBg;
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
          } else if (salidaFondo != null) {
            salidaFondo!();
          }
        }
        // 'abrir' no hace nada acá: showsUserInterface:true ya trae la
        // app al frente solo.
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

  // COMENTADO: no usar, la notificación activa ya existe
  // (Estado de Secure App 777). Se deja el código sin borrar.
  // static Future<void> showColabEvento(String titulo, String cuerpo) async {
  //   const details = NotificationDetails(
  //     android: AndroidNotificationDetails(
  //       _channelId,
  //       _channelName,
  //       channelDescription: 'Avisos de Colab',
  //       importance: Importance.high,
  //       priority: Priority.high,
  //       ongoing: false,
  //       showWhen: true,
  //     ),
  //   );
  //   try {
  //     await _plugin.show(
  //       id: 778,
  //       title: titulo,
  //       body: cuerpo,
  //       notificationDetails: details,
  //     );
  //   } catch (_) {}
  // }

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
