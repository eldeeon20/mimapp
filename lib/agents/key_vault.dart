import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../services/app_db.dart';
import '../services/crypto_vault.dart';
import '../services/settings.dart';
import 'provider_registry.dart';

/// Caja fuerte de API keys estilo FilosoIA: N keys por proveedor,
/// cifradas con CryptoVault (PRBX AES-GCM) en `app.db` (clave
/// `filosoia_keys`).
/// Rotación round-robin; ante 401/403 se marca la key mala y rota.
///
/// El viejo `filosoia_keys.pr` no importa: se borra sin migrar.
class KeyVault extends ChangeNotifier {
  KeyVault._();
  static final KeyVault instance = KeyVault._();

  static const _kv = 'filosoia_keys';

  /// Nombre del archivo viejo (solo migración, después se borra).
  static const _fileName = 'filosoia_keys.pr';

  /// providerId -> lista de keys (en memoria apenas; en disco cifradas).
  final Map<String, List<String>> _keys = {};
  final Map<String, String> _baseUrlOverrides = {};
  final Map<String, int> _rotation = {};
  final Set<String> _deadKeys = {}; // "provider:idx" que dieron 401/403
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    // El .pr no importa: se borra, app.db manda.
    await AppDb.tachar(_fileName);
    try {
      final raw = await AppDb.leer(_kv);
      if (raw == null) return;
      final plain = await CryptoVault.decrypt(
          raw, Settings.instance.masterKey);
      if (plain == null) return;
      final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      for (final e in (map['keys'] ?? {}).entries) {
        _keys[e.key] = List<String>.from(e.value as List);
      }
      for (final e in (map['urls'] ?? {}).entries) {
        _baseUrlOverrides[e.key] = e.value as String;
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final json = utf8.encode(jsonEncode({
        'keys': _keys,
        'urls': _baseUrlOverrides,
      }));
      final enc = await CryptoVault.encrypt(
          Uint8List.fromList(json), Settings.instance.masterKey);
      await AppDb.guardar(_kv, enc);
    } catch (_) {}
    notifyListeners();
  }

  // ------------------------------------------------------------- keys

  void addKey(String providerId, String key) {
    if (key.trim().isEmpty) return;
    (_keys[providerId] ??= []).add(key.trim());
    save();
  }

  void removeKey(String providerId, int index) {
    final list = _keys[providerId];
    if (list == null || index < 0 || index >= list.length) return;
    list.removeAt(index);
    save();
  }

  int keyCount(String providerId) => _keys[providerId]?.length ?? 0;

  String? keyAt(String providerId, int index) =>
      index >= 0 && index < (_keys[providerId]?.length ?? 0)
          ? _keys[providerId]![index]
          : null;

  /// Siguiente key viva del proveedor (round-robin). null si no hay.
  String? nextKey(String providerId) {
    final list = _keys[providerId];
    if (list == null || list.isEmpty) return null;
    for (var i = 0; i < list.length; i++) {
      final idx = ((_rotation[providerId] ?? 0) + i) % list.length;
      if (!_deadKeys.contains('$providerId:$idx')) {
        _rotation[providerId] = idx;
        return list[idx];
      }
    }
    return null; // todas muertas
  }

  /// Ante 401/403: marcar la actual como muerta y avanzar.
  void markDeadAndRotate(String providerId) {
    final cur = _rotation[providerId];
    if (cur != null) _deadKeys.add('$providerId:$cur');
    _rotation[providerId] = (cur ?? -1) + 1;
  }

  void reviveKeys(String providerId) => _deadKeys.removeAll(
      _deadKeys.where((k) => k.startsWith('$providerId:')));

  // ------------------------------------------------------------- urls

  String baseUrlFor(AiProvider p) => _baseUrlOverrides[p.id] ?? p.baseUrl;

  void setBaseUrl(String providerId, String url) {
    if (url.trim().isEmpty) return;
    _baseUrlOverrides[providerId] = url.trim().endsWith('/')
        ? url.trim().substring(0, url.trim().length - 1)
        : url.trim();
    save();
  }
}
