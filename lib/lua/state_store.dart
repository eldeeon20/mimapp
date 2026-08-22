import 'package:flutter/foundation.dart';

/// Almacén de estado de la GUI Lua. Reemplaza el antiguo `_values` +
/// `onUpdate -> setState` que reconstruía TODO el árbol.
///
/// Cada clave (id/bind de un nodo) tiene su propio [ValueNotifier]. Al
/// hacer [set], SOLO los widgets enlazados a esa clave se reconstruyen, no
/// el árbol completo.
///
/// Esto separa:
///   - Structural update  -> cambia el árbol (GuiRuntime.setTree)
///   - Value update      -> StateStore.set(id) -> solo ese nodo
class StateStore {
  final Map<String, String> _values = {};
  final Map<String, ValueNotifier<String>> _notifiers = {};

  /// Valor actual de una clave (o '').
  String get(String id) => _values[id] ?? '';

  /// Todos los valores (snapshot). Útil para inputs sin binding.
  Map<String, String> get values => Map.unmodifiable(_values);

  /// Notificador dirigido a una clave: solo el widget que escucha este
  /// listenable se reconstruye cuando cambia.
  ValueListenable<String> listenableFor(String id) {
    return _notifiers.putIfAbsent(
      id,
      () => ValueNotifier<String>(_values[id] ?? ''),
    );
  }

  /// Actualización de VALOR: no reconstruye el árbol, solo el nodo enlazado.
  /// Es la vía de ticks de alta frecuencia (progreso, player, tokens…).
  void set(String id, String value) {
    _values[id] = value;
    final n = _notifiers[id];
    // Evita notificar si el valor no cambió (evita rebuilds inútiles).
    if (n != null && n.value != value) n.value = value;
  }

  /// Limpia todo (al recargar una página nueva).
  void clear() {
    _values.clear();
    for (final n in _notifiers.values) n.dispose();
    _notifiers.clear();
  }
}
