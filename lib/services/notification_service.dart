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

  static Future<void> init() async {
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
          // Botón "Salir": detiene el servicio en primer plano y quita
          // la notificación.
          FlutterBackgroundService().invoke('stop');
          _plugin.cancel(id: serviceNotificationId);
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
            icon: 'ic_bg_service_small',
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
}
