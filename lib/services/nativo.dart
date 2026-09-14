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

  static Future<void> startPing({
    required String endpoint,
    required String accessToken,
    required String refreshToken,
    required String expiryIso,
    required String clientId,
    required String clientSecret,
  }) async {
    try {
      await _canal.invokeMethod('startPing', {
        'endpoint': endpoint,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiryIso': expiryIso,
        'clientId': clientId,
        'clientSecret': clientSecret,
      });
    } catch (_) {}
  }

  static Future<void> stopPing() async {
    try {
      await _canal.invokeMethod('stopPing');
    } catch (_) {}
  }

  /// Para el servicio nativo (sin celda no queda nada). No mata la app.
  static Future<void> stop() async {
    try {
      await _canal.invokeMethod('stop');
    } catch (_) {}
  }

  /// Espejo de lo que pinea el nativo (para la 777 de Dart).
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
