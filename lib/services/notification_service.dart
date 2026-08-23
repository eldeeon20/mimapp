import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  static Future<void> init({
    Future<void> Function()? onExitAction,
  }) async {
    const androidSettings = AndroidInitializationSettings('ic_bg_service_small');

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.actionId == 'exit') {
          // Botón "Salir": detener el servicio en primer plano y limpiar
          // TODAS las notificaciones persistentes (888 + estado 777).
          // El teardown completo lo pasa el caller (bootstrap) porque ahí
          // viven StatusNotifier/FlutterBackgroundService sin ciclos.
          if (onExitAction != null) {
            onExitAction();
          } else {
            FlutterBackgroundService().invoke('stop');
            _plugin.cancel(id: serviceNotificationId);
          }
        }
      },
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

  @pragma('vm:entry-point')
  static void notificationTapBackground(NotificationResponse response) {
    // Manejar tap en background
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
            'Salir',
            showsUserInterface: false,
          ),
        ],
      ),
    );
    await _plugin.show(
      id: serviceNotificationId,
      title: 'Secure App',
      body: 'Servicio activo · toca Salir para detener',
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
