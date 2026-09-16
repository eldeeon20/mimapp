import 'package:flutter/services.dart';

/// Puente al servicio nativo Kotlin de mimapp (888 + ping Colab en
/// nativo, sin flutter_background_service para 888/777).
class Nativo {
  Nativo._();

  static const _canal = MethodChannel('pr_app/nativo');

  static Future<void> prender() async {
    try {
      await _canal.invokeMethod('prender');
    } catch (_) {}
  }

  static Future<void> apagar() async {
    try {
      await _canal.invokeMethod('apagar');
    } catch (_) {}
  }

  /// X de la 888: DETIENE EL SERVICIO (corta ping, baja 888).
  /// La app sigue viva.
  static Future<void> salirTotal() async {
    try {
      await _canal.invokeMethod('salirTotal');
    } catch (_) {}
  }

  /// Salir de la 777: SOLO baja la notificación en nativo (acá no se
  /// postea 777). Cerrar la app lo hace Dart con SystemNavigator.pop
  /// para NO matar el servicio.
  static Future<void> cerrarStatus() async {
    try {
      await _canal.invokeMethod('cerrarStatus');
    } catch (_) {}
  }

  /// Crea el servicio `:ping` (proceso independiente) con el bundle.
  /// [expiryMs] = epoch en UTC (sin strings ni zonas).
  static Future<void> startPing({
    required String endpoint,
    required String accessToken,
    required String refreshToken,
    required int expiryMs,
    required String clientId,
    required String clientSecret,
  }) async {
    try {
      await _canal.invokeMethod('startPing', {
        'endpoint': endpoint,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiryMs': expiryMs,
        'clientId': clientId,
        'clientSecret': clientSecret,
      });
    } catch (_) {}
  }

  /// Token fresco empujado al servicio (pisa sin resetear el loop).
  /// El servicio lo ignora si no está pineando.
  static Future<void> updateToken({
    required String accessToken,
    required String refreshToken,
    required int expiryMs,
  }) async {
    try {
      await _canal.invokeMethod('updateToken', {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiryMs': expiryMs,
      });
    } catch (_) {}
  }

  /// Pide eximir a la app de la optimización de batería (una vez).
  /// Sin esto Android 12+ y las ROMs matan el servicio al barrer y no
  /// lo dejan revivir. true = ya exenta (no abre nada).
  static Future<bool> sinLimites() async {
    try {
      final r = await _canal.invokeMethod('sinLimites');
      return r == true;
    } catch (_) {
      return false;
    }
  }

  /// Para el servicio nativo (sin celda no queda nada). No mata la app.
  static Future<void> stop() async {
    try {
      await _canal.invokeMethod('stop');
    } catch (_) {}
  }

  /// Espejo de lo que pinea el nativo (para la 777 de Dart).
  /// El servicio vive en `:ping` (otro proceso): llega por broadcast
  /// (último push + pedido fresco). Incluye `ultimoEndpoint` para
  /// desasignar la celda muerta.
  static Future<Map<String, dynamic>> estado() async {
    try {
      final r = await _canal.invokeMethod('estado');
      if (r is Map) return Map<String, dynamic>.from(r);
    } catch (_) {}
    return {};
  }

  /// Aviso simple apilable SIN botones (Notis.kt): se cierra deslizando
  /// o con Limpiar de Android. Devuelve el id para quitarlo después.
  static Future<int?> avisar(String titulo, String cuerpo) async {
    try {
      final r = await _canal.invokeMethod('avisar', {
        'titulo': titulo,
        'cuerpo': cuerpo,
      });
      if (r is int) return r;
    } catch (_) {}
    return null;
  }

  static Future<void> quitarAviso(int id) async {
    try {
      await _canal.invokeMethod('quitarAviso', {'id': id});
    } catch (_) {}
  }

  /// Progreso apilable (ej. descargas): [progreso] 0..1, null =
  /// indeterminado. Con [terminado]=true queda deslizable.
  static Future<void> progresoAviso({
    required int id,
    required String titulo,
    required String cuerpo,
    double? progreso,
    bool terminado = false,
  }) async {
    try {
      await _canal.invokeMethod('progresoAviso', {
        'id': id,
        'titulo': titulo,
        'cuerpo': cuerpo,
        'progreso': progreso,
        'terminado': terminado,
      });
    } catch (_) {}
  }
}
