import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/crypto_vault.dart';
import '../services/settings.dart';
import 'provider_registry.dart';

/// Caja fuerte de API keys estilo FilosoIA: N keys por proveedor,
/// cifradas con CryptoVault (PRBX AES-GCM) en appSupport/filosoia_keys.pr.
/// Rotación round-robin; ante 401/403 se marca la key mala y rota.
class KeyVault extends ChangeNotifier {
  KeyVault._();
  static final KeyVault instance = KeyVault._();

  static const _fileName = 'filosoia_keys.pr';

  /// providerId -> lista de keys (en memoria apenas; en disco cifradas).
  final Map<String, List<String>> _keys = {};
  final Map<String, String> _baseUrlOverrides = {};
  final Map<String, int> _rotation = {};
  final Set<String> _deadKeys = {}; // "provider:idx" que dieron 401/403
  bool _loaded = false;

  bool get loaded => _loaded;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final raw = await f.readAsBytes();
      final plain = await CryptoVault.decrypt(
          Uint8List.fromList(raw), Settings.instance.masterKey);
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
      final f = await _file();
      final json = utf8.encode(jsonEncode({
        'keys': _keys,
        'urls': _baseUrlOverrides,
      }));
      final enc = await CryptoVault.encrypt(
          Uint8List.fromList(json), Settings.instance.masterKey);
      await f.writeAsBytes(enc, flush: true);
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
