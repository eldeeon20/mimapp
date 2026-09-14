import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pr_app/src/rust/frb_generated.dart';

import '../media/media_library.dart';
import '../services/colab_service.dart';
import '../services/nat_service.dart';
import '../services/notification_service.dart';
import '../services/servicio_fondo.dart';
import '../services/settings.dart';
import '../services/status_notifier.dart';
import '../media/media_player.dart';

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
  // Limpia el flag de stop viejo (un stop anterior no vale).
  try {
    await ServicioFondo.limpiarFlagStop();
  } catch (_) {}
  // Servicio en primer plano (archivo separado servicio_fondo.dart):
  // mantiene el proceso vivo en fondo para que el ping a Colab del
  // isolate siga aunque la UI se cierre. Salir (777) mata vía
  // ServicioFondo.salir (espera confirmación, sin revivir).
  await _initBackgroundService();
  await _initRust();
  await _initColab();
  await Settings.instance.load();
  // Biblioteca del reproductor (historial + favoritos cifrados).
  try {
    await MediaLibraryStore.instance.load();
  } catch (e) {
    debugPrint('MediaLibrary init error: $e');
  }
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
            ServicioFondo.canalId,
            ServicioFondo.canalNombre,
            importance: Importance.low,
          ),
        );
  } catch (e) {
    debugPrint('Canal servicio error: $e');
  }
}

Future<void> _initNotifications() async {
  try {
    await NotificationService.init(
      onExitAction: _handleExitAction,
      onExitBg: ServicioFondo.salir,
    );
  } catch (e) {
    debugPrint('NotificationService init error: $e');
  }
}

/// Botón "Salir" = KILL TOTAL de la app (servicio, todas las
/// notificaciones y proceso). Vive en servicio_fondo.dart.
Future<void> _handleExitAction() => ServicioFondo.salir();

/// Servicio en primer plano: vive en servicio_fondo.dart (archivo
/// separado de las notificaciones). Solo configura; arranca a pedido
/// con celda en ping (la 888 con ✕ sale recién ahí).
Future<void> _initBackgroundService() => ServicioFondo.iniciar();

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

/// (El motor de ping vive en servicio_fondo.dart: ColabPingMotor.)
