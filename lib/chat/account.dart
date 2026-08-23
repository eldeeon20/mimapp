import 'package:flutter/foundation.dart';

import 'models.dart';

/// Cuenta propia (perfil "yo"). Todo simulado, sin red.
class Account extends ChangeNotifier {
  Account._();
  static final Account instance = Account._();

  String nombre = 'Tú';
  String username = '@tu_usuario';
  String telefono = '+54 9 11 2345-6789';
  String bio = 'Demo offline de la réplica de Telegram.';
  ColorSeed color = ColorSeed.cyan;
  int coins = 1500;

  final Set<String> amigosIds = {};
  final Set<String> bloqueadosIds = {};

  bool esAmigo(String userId) => amigosIds.contains(userId);
  bool estaBloqueado(String userId) => bloqueadosIds.contains(userId);

  void toggleAmigo(String userId) {
    if (!amigosIds.remove(userId)) amigosIds.add(userId);
    notifyListeners();
  }

  /// Bloquear también saca de amigos.
  void toggleBloqueo(String userId) {
    if (!bloqueadosIds.remove(userId)) {
      bloqueadosIds.add(userId);
      amigosIds.remove(userId);
    }
    notifyListeners();
  }

  /// Compra un gift: devuelve false si no alcanzan las coins.
  bool comprar(Gift g) {
    if (coins < g.precio) return false;
    coins -= g.precio;
    notifyListeners();
    return true;
  }

  void editar({String? nombre, String? username, String? bio}) {
    if (nombre != null && nombre.isNotEmpty) this.nombre = nombre;
    if (username != null && username.isNotEmpty) this.username = username;
    if (bio != null) this.bio = bio;
    notifyListeners();
  }
}
