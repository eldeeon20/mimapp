part of 'lua_controller.dart';

/// Globals kem_*: KEM post-cuántico vía jobs.
///
///   kem_algos()                        -> string "X25519,MlKem768,..."
///   id = kem_keygen_start(alg)         -> sk/pk hex truncados
///   id = kem_roundtrip_start(alg)      -> OK + timings + tamaños
void registerKemGlobals(LuaController c) {
  c._registerSync('kem_algos', (ls) => _luaKemAlgos(ls, c));
  c._registerSync('kem_keygen_start', (ls) => _luaKemKeygen(ls, c));
  c._registerSync('kem_roundtrip_start', (ls) => _luaKemRoundtrip(ls, c));
}

int _luaKemAlgos(LuaState ls, LuaController c) {
  // sync no posible (codegen async): job instantáneo
  ls.pushInteger(c.jobStart(() async {
    try {
      final algos = await Kem().listAlgorithms();
      return algos.join(',');
    } catch (e) {
      return 'ERROR: $e';
    }
  }));
  return 1;
}

int _luaKemKeygen(LuaState ls, LuaController c) {
  final alg = ls.checkString(1) ?? 'XWingKemDraft06';
  ls.pop(1);
  ls.pushInteger(c.jobStart(() async {
    try {
      final kp = await Kem().keyGen(alg);
      String hex(Uint8List b) =>
          b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      return jobJson({
        'ok': true,
        'alg': alg,
        'sk_len': kp.privateKey.length,
        'pk_len': kp.publicKey.length,
        'pk_head': hex(Uint8List.fromList(kp.publicKey.take(16).toList())),
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaKemRoundtrip(LuaState ls, LuaController c) {
  final alg = ls.checkString(1) ?? 'XWingKemDraft06';
  ls.pop(1);
  ls.pushInteger(c.jobStart(() async {
    try {
      final sw = Stopwatch()..start();
      final kem = Kem();
      final a = await kem.keyGen(alg);
      final keygenMs = sw.elapsedMicroseconds / 1000;
      sw.reset();
      final enc = await kem.encapsulate(algorithm: alg, publicKey: a.publicKey);
      final encMs = sw.elapsedMicroseconds / 1000;
      sw.reset();
      final ssB = await kem.decapsulate(
          algorithm: alg, ciphertext: enc.ciphertext, privateKey: a.privateKey);
      final decMs = sw.elapsedMicroseconds / 1000;
      final match = enc.sharedSecret.length == ssB.length &&
          List.generate(
                  enc.sharedSecret.length, (i) => enc.sharedSecret[i] == ssB[i])
              .every((x) => x);
      return jobJson({
        'ok': match,
        'alg': alg,
        'ms': '${keygenMs.toStringAsFixed(2)}/${encMs.toStringAsFixed(2)}/${decMs.toStringAsFixed(2)}',
        'bytes': 'sk=${a.privateKey.length} pk=${a.publicKey.length} ct=${enc.ciphertext.length}',
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}
