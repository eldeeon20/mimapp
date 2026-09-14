import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'notification_service.dart';
import 'status_notifier.dart';

/// SERVICIO en primer plano (archivo separado de las notificaciones).
///
/// La docu del plugin termina un servicio así:
/// - fondo: `service.on('stop').listen((_) => service.stopSelf())`
/// - UI: `FlutterBackgroundService().invoke('stop')`
/// Acá igual + confirmación por archivo (ver [esperarStop]): la UI
/// espera a verlo antes del kill para que Android no resucite el
/// service STICKY (ese era el bug de "no se detiene nunca").
///
/// Este isolate además lleva el ÚNICO ping a Colab (cada 60s). La app
/// solo ordena "mantené esto en ping" (startPing) y "cortá" (stopPing).
/// Si la app se cierra, el ping continúa.
class ServicioFondo {
  ServicioFondo._();

  /// Canal e id de la notificación del servicio (888).
  static const canalId = 'pr_app_channel';
  static const canalNombre = 'pr_app';
  static const notifId = 888;

  /// Configura el servicio (una vez en initApp). NO lo arranca ni
  /// postea nada: sin celda no hay servicio ni 888.
  static Future<void> iniciar() async {
    try {
      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: onServiceStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: canalId,
          initialNotificationTitle: 'Secure App',
          initialNotificationContent: 'Servicio activo',
          foregroundServiceNotificationId: notifId,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: onServiceStart,
        ),
      );
    } catch (e) {
      debugPrint('ServicioFondo init error: $e');
    }
  }

  /// Prende el servicio a pedido (hay celda en ping) y postea la 888
  /// con ✕ desde la UI principal (los taps viven ahí).
  static Future<void> prender() async {
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) await service.startService();
      await Future.delayed(const Duration(milliseconds: 1200));
      await mostrarX();
    } catch (_) {}
  }

  /// true si el servicio está corriendo.
  static Future<bool> corriendo() async {
    try {
      return await FlutterBackgroundService().isRunning();
    } catch (_) {
      return false;
    }
  }

  /// Archivo que el fondo escribe al procesar stopSelf.
  static Future<File> _flagStopFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/colab/service_stop_ok');
  }

  /// Espera (poll 200ms, tope 6s) a que el fondo confirme el stop.
  /// Si el servicio ni corre (sin celda), vuelve ya sin esperar.
  static Future<void> esperarStop() async {
    if (!await corriendo()) return;
    for (var i = 0; i < 30; i++) {
      try {
        if (await (await _flagStopFile()).exists()) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Lo llama el fondo al suicidarse: deja constancia para [esperarStop].
  /// También borra el espejo de ping para no mostrar fantasma al volver.
  static Future<void> confirmarStop() async {
    try {
      final f = await _flagStopFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(DateTime.now().toIso8601String());
    } catch (_) {}
    try {
      final dir = await getApplicationSupportDirectory();
      final espejo = File('${dir.path}/colab/colab_ping_estado.json');
      if (await espejo.exists()) await espejo.delete();
    } catch (_) {}
  }

  /// Limpia el flag al arrancar (un stop viejo no vale).
  static Future<void> limpiarFlagStop() async {
    try {
      final f = await _flagStopFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// La 888 del servicio CON su ✕. Vive acá (archivo del servicio):
  /// se postea UNA vez desde la UI principal con la MISMA instancia
  /// de FLN (sin inicializar otra: eso robaría los taps). Mismo id
  /// que usa el plugin (888).
  static Future<void> mostrarX() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        canalId,
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
    try {
      await NotificationService.plugin.show(
        id: notifId,
        title: 'Secure App',
        body: 'Servicio activo · toca ✕ para salir',
        notificationDetails: details,
      );
    } catch (_) {}
  }

  /// SALIR = KILL TOTAL (vive acá, en el archivo del servicio).
  /// 1) pide parada al fondo, 2) espera su confirmación por archivo
  /// (máx 6s) para que Android no resucite el STICKY, 3) da de baja
  /// las notificaciones, 4) mata el proceso.
  /// Escribe el progreso en la 777: si el texto cambia, el tap llegó;
  /// si no cambia, el tap no llega a Dart (diagnóstico).
  static Future<void> salir() async {
    try {
      StatusNotifier.instance.aviso('Saliendo… parando servicio');
    } catch (_) {}
    try {
      FlutterBackgroundService().invoke('stop');
    } catch (_) {}
    await esperarStop();
    try {
      StatusNotifier.instance.aviso('Saliendo… bajando notificaciones');
    } catch (_) {}
    try {
      await NotificationService.cancelPersistentes();
    } catch (_) {}
    try {
      await NotificationService.matarProceso();
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
Future<void> onServiceStart(ServiceInstance service) async {
  // Obligatorio en Flutter 3+ release: sin esto el isolate de fondo queda
  // sordo (los plugins no registran y el 'stop' nunca llega → el servicio
  // no se detenía nunca). FLN NO se inicializa acá: los taps de los
  // botones viven en la UI principal.
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
      final m =
          Map<String, dynamic>.from((e as Map?) ?? <String, dynamic>{});
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
    _svc.on('stop').listen((_) async {
      _timer?.cancel();
      // Confirmar por archivo ANTES de suicidarse: la UI espera verlo
      // y recién ahí mata el proceso (sin resurrección STICKY).
      try {
        await ServicioFondo.confirmarStop();
      } catch (_) {}
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
