import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pr_app/src/rust/frb_generated.dart';

import '../services/colab_service.dart';
import '../services/nat_service.dart';
import '../services/notification_service.dart';
import '../services/settings.dart';
import '../services/status_notifier.dart';
import '../media/media_player.dart';

const _notifChannelId = 'pr_app_channel';
const _notifChannelName = 'pr_app';

final FlutterLocalNotificationsPlugin _notifPlugin =
    FlutterLocalNotificationsPlugin();

/// Inicializa todos los servicios de la app antes del runApp.
Future<void> initApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initSystemUi();
  MediaKit.ensureInitialized();
  await _initMediaService();
  await _initServiceChannel();
  await _initNotifications();
  // SERVICIO EN SEGUNDO PLANO DESACTIVADO (el botón Salir no funcionaba).
  // await _initBackgroundService();
  // Notificación ✕ fuera: queda SOLO "Estado de Secure App" (777).
  // await NotificationService.showServiceNotification();
  await _initRust();
  await _initColab();
  await Settings.instance.load();
  await NatService.instance.init();
  await StatusNotifier.instance.init();
}

/// Pantalla completa inmersiva: sin barra de estado (sin hora/batería)
/// y el contenido cubre también la zona del notch/punch-hole
/// (el modo cutout SHORT_EDGES se configura en MainActivity.kt).
Future<void> _initSystemUi() async {
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  } catch (_) {}
}

/// Servicio de medios: playlist + notificación con controles.
Future<void> _initMediaService() async {
  try {
    await AudioService.init(
      builder: () => MediaPlayer.instance,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'pr_app_media',
        androidNotificationChannelName: 'Reproducción de medios',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint('AudioService init error: $e');
  }
}

/// Canal del servicio en segundo plano (obligatorio crearlo ANTES).
Future<void> _initServiceChannel() async {
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
}

Future<void> _initNotifications() async {
  try {
    await NotificationService.init(onExitAction: _handleExitAction);
  } catch (e) {
    debugPrint('NotificationService init error: $e');
  }
}

/// Botón "Salir" = KILL TOTAL de la app (servicio, todas las
/// notificaciones y proceso). Misma rutina que el camino en segundo plano.
Future<void> _handleExitAction() => NotificationService.exitApp();

Future<void> _initBackgroundService() async {
  try {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onServiceStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: _notifChannelId,
        initialNotificationTitle: 'Secure App',
        initialNotificationContent: 'Servicio activo',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onServiceStart,
      ),
    );
    // Postear UNA vez desde el isolate PRINCIPAL (con el botón "Salir")
    // para pisar la notificación inicial del plugin, que sale sin acciones.
    // IMPORTANTE: NO inicializar FLN dentro del isolate del servicio —
    // eso le roba a la UI principal los callbacks de las acciones.
    await Future.delayed(const Duration(milliseconds: 1200));
    await NotificationService.showServiceNotification();
  } catch (e) {
    debugPrint('BackgroundService init error: $e');
  }
}

Future<void> _initRust() async {
  try {
    await RustLib.init();
  } catch (e) {
    debugPrint('Rust init error: $e');
  }
}

Future<void> _initColab() async {
  try {
    await ColabService().init();
  } catch (e) {
    debugPrint('ColabService init error: $e');
  }
}

@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  // ÚNICA responsabilidad del isolate del servicio: escuchar la orden de
  // parada. FLN NO se inicializa acá (si no, los taps/acciones de las
  // notificaciones dejan de llegar al isolate principal).
  service.on('stop').listen((_) => service.stopSelf());
}
