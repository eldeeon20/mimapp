import 'package:flutter/foundation.dart';

/// Ajustes del chat (toggles estilo Telegram > Ajustes).
class AjustesChat extends ChangeNotifier {
  AjustesChat._();
  static final AjustesChat instance = AjustesChat._();

  bool notificaciones = true;
  bool sonidos = true;
  bool vibrar = true;
  double tamanoTexto = 15.5;
  bool mostrarEstados = true;
  bool autodownloadMedia = true;

  void set({
    bool? notificaciones,
    bool? sonidos,
    bool? vibrar,
    double? tamanoTexto,
    bool? mostrarEstados,
    bool? autodownloadMedia,
  }) {
    if (notificaciones != null) this.notificaciones = notificaciones;
    if (sonidos != null) this.sonidos = sonidos;
    if (vibrar != null) this.vibrar = vibrar;
    if (tamanoTexto != null) this.tamanoTexto = tamanoTexto.clamp(12, 22);
    if (mostrarEstados != null) this.mostrarEstados = mostrarEstados;
    if (autodownloadMedia != null) this.autodownloadMedia = autodownloadMedia;
    notifyListeners();
  }
}
