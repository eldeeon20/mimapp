part of 'lua_controller.dart';

/// Globals ring_*: firmas de anillo (nostringer) desde Lua vía jobs.
///
///   id = ring_keypair_start(['blsag'|'sag'])
///   id = ring_sign_start(msg, privkey, ring_csv [, variant])
///   id = ring_verify_start(firma, msg, ring_csv [, variant])
///   id = ring_kimatch_start(keyimage1, keyimage2)   -- anti doble-voto
///
/// El ring viaja como pubkeys separadas por "|" (mismo formato que relays).
/// El mensaje se pasa tal cual (se hashea adentro del lado Rust).
void registerNostrRingGlobals(LuaController c) {
  c._registerSync('ring_keypair_start', (ls) => _luaRingKeypair(ls, c));
  c._registerSync('ring_sign_start', (ls) => _luaRingSign(ls, c));
  c._registerSync('ring_verify_start', (ls) => _luaRingVerify(ls, c));
  c._registerSync('ring_kimatch_start', (ls) => _luaRingKiMatch(ls, c));
}

final Nostringer _ringSvc = Nostringer();

List<String> _ringArg(LuaState ls, int idx) {
  final csv = ls.isString(idx) ? (ls.toStr(idx) ?? '') : '';
  return csv
      .split('|')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

int _luaRingKeypair(LuaState ls, LuaController c) {
  final variant = ls.isString(1) ? (ls.toStr(1) ?? 'blsag') : 'blsag';
  ls.pop(ls.getTop());
  ls.pushInteger(c.jobStart(() async {
    try {
      final kp = await _ringSvc.generateKeypair(variant: variant);
      return jobJson({
        'ok': true,
        'variant': variant,
        'pubkey': kp.publicKey,
        'privkey': kp.privateKey,
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaRingSign(LuaState ls, LuaController c) {
  final msg = ls.checkString(1) ?? '';
  final priv = ls.checkString(2) ?? '';
  final ring = _ringArg(ls, 3);
  final variant = ls.isString(4) ? (ls.toStr(4) ?? 'blsag') : 'blsag';
  ls.pop(ls.getTop());
  if (priv.isEmpty || ring.length < 2) {
    // firma de anillo sin ring no tiene sentido; error inmediato
    ls.pushString('ERROR: faltan privkey o ring (≥2 pubkeys)');
    return 1;
  }
  ls.pushInteger(c.jobStart(() async {
    try {
      final s = await _ringSvc.sign(
        message: Uint8List.fromList(utf8.encode(msg)),
        privateKey: priv,
        ring: ring,
        variant: variant,
      );
      return jobJson({
        'ok': true,
        'signature': s.signature,
        'key_image': s.keyImage,
        'variant': variant,
        'n_ring': ring.length,
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaRingVerify(LuaState ls, LuaController c) {
  final sig = ls.checkString(1) ?? '';
  final msg = ls.checkString(2) ?? '';
  final ring = _ringArg(ls, 3);
  ls.pop(ls.getTop());
  ls.pushInteger(c.jobStart(() async {
    try {
      final r = await _ringSvc.verify(
        signature: sig,
        message: Uint8List.fromList(utf8.encode(msg)),
        ring: ring,
      );
      return jobJson({'ok': true, 'valid': r.valid, 'key_image': r.keyImage});
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaRingKiMatch(LuaState ls, LuaController c) {
  final ki1 = ls.checkString(1) ?? '';
  final ki2 = ls.checkString(2) ?? '';
  ls.pop(ls.getTop());
  ls.pushInteger(c.jobStart(() async {
    try {
      final same = await _ringSvc.keyImagesMatch(ki1, ki2);
      return jobJson({
        'ok': true,
        'match': same,
        'nota': same
            ? 'MISMA identidad (doble firmante / doble voto)'
            : 'identidades distintas',
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}
