import 'package:flutter/foundation.dart';

/// (antes llamada ChatStorage) Uso de almacenamiento simulado por categoría (Telegram > Datos y almacenamiento).
class ChatStorage extends ChangeNotifier {
  ChatStorage._();
  static final ChatStorage instance = ChatStorage._();

  /// Total simulado del dispositivo en MB.
  static const double totalMb = 65536; // 64 GB

  double fotosMb = 812.4;
  double videosMb = 2340.8;
  double docsMb = 156.2;
  double otrosMb = 74.9;

  double get usadoMb => fotosMb + videosMb + docsMb + otrosMb;
  double get libreMb => totalMb - usadoMb;

  String _fmt(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  String get fotosTxt => _fmt(fotosMb);
  String get videosTxt => _fmt(videosMb);
  String get docsTxt => _fmt(docsMb);
  String get otrosTxt => _fmt(otrosMb);
  String get libreTxt => _fmt(libreMb);

  /// Registra media enviada/recibida (para que el gráfico se mueva).
  void registrar(String categoria, int bytes) {
    final mb = bytes / (1024 * 1024);
    switch (categoria) {
      case 'imagen':
        fotosMb += mb;
      case 'video':
        videosMb += mb;
      case 'archivo' || 'audio':
        docsMb += mb;
      default:
        otrosMb += mb;
    }
    notifyListeners();
  }

  /// "Limpiar caché": resetea la categoría Otros.
  void limpiarCache() {
    otrosMb = 0;
    notifyListeners();
  }
}
