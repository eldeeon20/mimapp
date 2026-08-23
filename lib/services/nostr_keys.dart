import 'dart:typed_data';

import '../src/rust/api/nostr_keys.dart' as rust;
import 'settings.dart';

/// Generador/convertidor de claves Nostr — porte del `Keyl` de Gtool.
///
/// Todas las llamadas al codegen FRB son async.
class NostrKeys {
  /// Clave privada aleatoria (32 bytes).
  Future<Uint8List> generate() async =>
      Uint8List.fromList(await rust.nostrGenerateKey());

  /// Clave determinística desde semilla textual (SHA256 → 32 bytes).
  Future<Uint8List> fromSeed(String seed) async =>
      Uint8List.fromList(await rust.nostrSeedToKey(seed: seed));

  /// Bytes del secreto → nsec bech32 ('' si inválido).
  Future<String> toNsec(Uint8List secret) => rust.nostrToNsec(secret: secret);

  /// Bytes del secreto → npub bech32 ('' si inválido).
  Future<String> toNpub(Uint8List secret) => rust.nostrToNpub(secret: secret);

  /// npub (bech32 o hex) → hex.
  Future<String> hexNpub(String npub) => rust.nostrHexNpub(npub: npub);

  /// nsec (bech32 o hex) → hex.
  Future<String> hexNsec(String nsec) => rust.nostrHexNsec(nsec: nsec);

  /// Valida y normaliza a bech32. '' = inválido.
  Future<String> validateNpub(String input) =>
      rust.nostrValidateNpub(input: input);

  Future<String> validateNsec(String input) =>
      rust.nostrValidateNsec(input: input);

  /// Hex de la pública desde bytes del secreto.
  Future<String> pubkeyHexFromSecret(Uint8List secret) =>
      rust.nostrPubkeyHexFromSecret(secret: secret);

  // ---------------- Identidades guardadas (cifrado en config.pr) --------

  /// Genera identidad nueva con nombre; retorna {npub, nsec}.
  Future<Map<String, String>> createIdentity(String nombre, {String? seed}) async {
    final secret = seed == null ? await generate() : await fromSeed(seed);
    final npub = await toNpub(secret);
    final nsec = await toNsec(secret);
    await saveIdentity(nombre, secret);
    return {'npub': npub, 'nsec': nsec};
  }

  Future<void> saveIdentity(String nombre, Uint8List secret) async {
    final s = Settings.instance;
    s.nostrKeys.removeWhere((k) => k['nombre'] == nombre);
    s.nostrKeys.add({
      'nombre': nombre,
      'secretHex': _toHex(secret),
      'npub': await toNpub(secret),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    await s.save();
  }

  List<Map<String, dynamic>> listIdentities() => Settings.instance.nostrKeys;

  Uint8List? loadSecret(String nombre) {
    for (final k in listIdentities()) {
      if (k['nombre'] == nombre && '${k['secretHex']}'.isNotEmpty) {
        return _fromHex('${k['secretHex']}');
      }
    }
    return null;
  }

  Future<bool> deleteIdentity(String nombre) async {
    final s = Settings.instance;
    final before = s.nostrKeys.length;
    s.nostrKeys.removeWhere((k) => k['nombre'] == nombre);
    await s.save();
    return s.nostrKeys.length != before;
  }
}

String _toHex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
