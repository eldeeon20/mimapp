import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pr_app/src/rust/frb_generated.dart';

import 'app/app.dart';
import 'services/colab_service.dart';
import 'services/notification_service.dart';

const _notifChannelId = 'pr_app_channel';
const _notifChannelName = 'pr_app';

final FlutterLocalNotificationsPlugin _notifPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } catch (_) {}
  MediaKit.ensureInitialized();

  // Canal del servicio ANTES de arrancar el servicio (obligatorio)
  try {
    await _notifPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _notifChannelId,
            _notifChannelName,
            importance: Importance.low,
          ),
        );
  } catch (e) {
    debugPrint('Canal servicio error: $e');
  }

  // Notificaciones
  try {
    await NotificationService.init();
  } catch (e) {
    debugPrint('NotificationService init error: $e');
  }

  // Servicio en segundo plano
  try {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _notifChannelId,
        initialNotificationTitle: 'pr_app',
        initialNotificationContent: 'Servicio activo',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onServiceStart,
      ),
    );
  } catch (e) {
    debugPrint('BackgroundService init error: $e');
  }

  try {
    await RustLib.init();
  } catch (e) {
    debugPrint('Rust init error: $e');
  }

  try {
    await ColabService().init();
  } catch (e) {
    debugPrint('ColabService init error: $e');
  }

  runApp(const PrApp());
}

@pragma('vm:entry-point')
Future<void> _onServiceStart(ServiceInstance service) async {
  service.on('stop').listen((_) {
    service.stopSelf();
  });
}
