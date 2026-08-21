import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pr_app/src/rust/frb_generated.dart';

import 'gui/engine_shell.dart';
import 'services/colab_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const _notifChannelId = 'pr_app_channel';
const _notifChannelName = 'pr_app';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } catch (_) {}
  MediaKit.ensureInitialized();

  await _initNotifications();
  await _initBackgroundService();

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

Future<void> _initNotifications() async {
  try {
    const androidSettings = AndroidInitializationSettings('ic_bg_service_small');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _notifChannelId,
          _notifChannelName,
          importance: Importance.high,
        ),
      );
      await androidPlugin.requestNotificationsPermission();
    }
  } catch (e) {
    debugPrint('Notificaciones init error: $e');
  }
}

Future<void> _initBackgroundService() async {
  try {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: false,
        isForegroundMode: false,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onServiceStart,
      ),
    );
  } catch (e) {
    debugPrint('BackgroundService init error: $e');
  }
}

@pragma('vm:entry-point')
Future<void> _onServiceStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
  service.on('stop').listen((_) {
    service.stopSelf();
  });
}
