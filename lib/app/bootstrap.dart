import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pr_app/src/rust/frb_generated.dart';

import '../media/media_library.dart';
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
  // Servicio en primer plano SORDO: mantiene el proceso vivo en fondo para
  // que el keep-alive de Colab siga pineando. Sin FLN en el fondo y sin
  // botones en la 888 (los botones Salir/Abrir viven en la 777 de Estado,
  // que se postea desde la UI principal donde los taps sí andan).
  // El botón Salir lo mata vía NotificationService.exitApp ('stop' + kill).
  await _initBackgroundService();
  // Notificación ✕ fuera: queda SOLO "Estado de Secure App" (777).
  // await NotificationService.showServiceNotification();
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
  // Obligatorio en Flutter 3+ release: sin esto el isolate de fondo queda
  // sordo (los plugins no registran y el 'stop' nunca llega → el servicio
  // no se detenía nunca). FLN NO se inicializa acá: los taps de los
  // botones viven en la 777 posteada desde la UI principal.
  DartPluginRegistrant.ensureInitialized();
  ColabPingMotor(service).arrancar();
}

/// Motor de ping a Colab DENTRO del isolate del servicio: UN solo ping
/// (cada 60s). La app solo le dice "mantené esto en ping" vía
/// invoke('startPing', {...}) y "cortá" vía invoke('stopPing').
/// Si la app se cierra, este isolate sigue y el ping continúa.
/// Todo lo que necesita (tokens + endpoint) llega por invoke: NO usa
/// plugins salvo http/path_provider (registrados arriba).
class ColabPingMotor {
  final ServiceInstance _svc;
  Timer? _timer;
  String? _endpoint;
  String? _access;
  String? _refresh;
  DateTime? _expiry;
  String? _clientId;
  String? _clientSecret;
  DateTime? _inicio;
  int _consec4xx = 0;
  int _pingsOk = 0;

  static const _intervalo = Duration(seconds: 60);
  static const _timeout = Duration(seconds: 10);
  static const _maximo = Duration(hours: 24);

  ColabPingMotor(this._svc);

  void arrancar() {
    _svc.on('startPing').listen((e) {
      final m = (e is Map) ? e : <String, dynamic>{};
      _empezar(
        endpoint: '${m['endpoint'] ?? ''}',
        access: '${m['accessToken'] ?? ''}',
        refresh: '${m['refreshToken'] ?? ''}',
        expiryIso: '${m['expiry'] ?? ''}',
        clientId: '${m['clientId'] ?? ''}',
        clientSecret: '${m['clientSecret'] ?? ''}',
      );
    });
    _svc.on('stopPing').listen((_) => _parar(origen: 'manual'));
    _svc.on('stop').listen((_) {
      _timer?.cancel();
      _svc.stopSelf();
    });
  }

  void _empezar({
    required String endpoint,
    required String access,
    required String refresh,
    required String expiryIso,
    required String clientId,
    required String clientSecret,
  }) {
    if (endpoint.isEmpty || access.isEmpty) return;
    _parar(origen: '');
    _endpoint = endpoint;
    _access = access;
    _refresh = refresh;
    _clientId = clientId;
    _clientSecret = clientSecret;
    try {
      _expiry = DateTime.parse(expiryIso);
    } catch (_) {
      _expiry = null;
    }
    _inicio = DateTime.now();
    _consec4xx = 0;
    _pingsOk = 0;
    _ping(); // inmediato
    _timer = Timer.periodic(_intervalo, (_) => _ping());
    _info('Secure App · Colab vivo', '$endpoint · 0s · ping del servicio');
    _guardarEstado(vivo: true);
  }

  void _parar({String origen = 'manual'}) {
    _timer?.cancel();
    _timer = null;
    if (origen.isNotEmpty) {
      _guardarEstado(vivo: false);
      _info('Secure App', 'Colab en pausa ($origen)');
    }
    _endpoint = null;
    _inicio = null;
    _consec4xx = 0;
  }

  Future<void> _ping() async {
    final ep = _endpoint;
    if (ep == null) return;
    if (_inicio != null && DateTime.now().difference(_inicio!) >= _maximo) {
      _parar(origen: 'límite 24h');
      return;
    }
    try {
      var token = _access ?? '';
      if (_expiry != null &&
          DateTime.now().isAfter(_expiry!.subtract(const Duration(seconds: 60)))) {
        token = await _refrescar();
      }
      final url = Uri.https(
        'colab.research.google.com',
        '/tun/m/$ep/keep-alive/',
        {'authuser': '0'},
      );
      final r = await http.get(url, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'X-Colab-Client-Agent': 'pr_app',
        'X-Colab-Tunnel': 'Google',
      }).timeout(_timeout);
      if (r.statusCode >= 400 && r.statusCode < 500) {
        _consec4xx++;
        if (_consec4xx >= 2) {
          _parar(origen: 'celda muerta (${r.statusCode})');
          return;
        }
      } else {
        _consec4xx = 0;
        _pingsOk++;
      }
      final dur = _inicio != null ? _formatoDur(DateTime.now().difference(_inicio!)) : '?';
      _info('Secure App · Colab vivo', '$ep · $dur · $_pingsOk pings');
      _guardarEstado(vivo: true);
    } catch (_) {
      // red/timeout: reintenta en el próximo ciclo, no cuenta error
    }
  }

  /// Refresca el access_token por HTTP puro (sin plugins).
  Future<String> _refrescar() async {
    final r = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      body: {
        'refresh_token': _refresh ?? '',
        'client_id': _clientId ?? '',
        'client_secret': _clientSecret ?? '',
        'grant_type': 'refresh_token',
      },
    ).timeout(_timeout);
    if (r.statusCode != 200) throw Exception('refresh ${r.statusCode}');
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    _access = '${d['access_token']}';
    _expiry = DateTime.now().add(Duration(seconds: (d['expires_in'] as int?) ?? 3600));
    return _access!;
  }

  void _info(String titulo, String cuerpo) {
    try {
      if (_svc is AndroidServiceInstance) {
        (_svc as AndroidServiceInstance)
            .setForegroundNotificationInfo(title: titulo, content: cuerpo);
      }
    } catch (_) {}
  }

  /// Estado para que la UI al abrir muestre lo que el servicio pinea.
  Future<void> _guardarEstado({required bool vivo}) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/colab/colab_ping_estado.json');
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'vivo': vivo,
        'endpoint': _endpoint ?? '',
        'inicio': _inicio?.toIso8601String() ?? '',
        'pingsOk': _pingsOk,
        'cuando': DateTime.now().toIso8601String(),
      }));
    } catch (_) {}
  }

  static String _formatoDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
