part of 'lua_controller.dart';

/// Globals shamir_*: partir/reconstruir secretos vía jobs.
///
///   id = shamir_demo_start(texto, n, t)  -- parte, pierde una, reconstruye
///   id = shamir_split_start(texto, n, t) -- retorna shares hex (pipe-sep)
///   id = shamir_combine_start(s0|s1|...) -- reconstruye desde shares hex
void registerShamirGlobals(LuaController c) {
  c._registerSync('shamir_demo_start', (ls) => _luaShamirDemo(ls, c));
  c._registerSync('shamir_split_start', (ls) => _luaShamirSplit(ls, c));
  c._registerSync('shamir_combine_start', (ls) => _luaShamirCombine(ls, c));
}

int _luaShamirDemo(LuaState ls, LuaController c) {
  final text = ls.checkString(1) ?? 'secreto';
  final n = ls.checkInteger(2) ?? 5;
  final t = ls.checkInteger(3) ?? 3;
  ls.pop(3);
  ls.pushInteger(c.jobStart(() async {
    try {
      final data = latin1.encode(text);
      final padded = Uint8List(data.length < 64 ? 64 : data.length);
      padded.setAll(0, data);
      final parts = await Shamir().split(padded, n.clamp(2, 255), t.clamp(2, 255));
      // perder la primera participación y reconstruir con el resto
      final rest = parts.sublist(1);
      if (rest.length < t) {
        return jobJson({'ok': false, 'error': 'quedan ${rest.length} < umbral $t'});
      }
      final restored = await Shamir().combine(rest);
      final same = restored != null &&
          List.generate(padded.length, (i) => i < restored.length ? restored[i] : 0)
              .toString() ==
              padded.toString();
      return jobJson({
        'ok': same,
        'shares': parts.length,
        'umbral': t,
        'restaurado': same ? text : '',
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaShamirSplit(LuaState ls, LuaController c) {
  final text = ls.checkString(1) ?? '';
  final n = ls.checkInteger(2) ?? 5;
  final t = ls.checkInteger(3) ?? 3;
  ls.pop(3);
  ls.pushInteger(c.jobStart(() async {
    try {
      final data = latin1.encode(text);
      final padded = Uint8List(data.length < 64 ? 64 : data.length);
      padded.setAll(0, data);
      final parts =
          await Shamir().split(padded, n.clamp(2, 255), t.clamp(2, 255));
      String hex(Uint8List b) =>
          b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      return jobJson({
        'ok': true,
        'n': parts.length,
        'umbral': t,
        'shares': [for (final p in parts) hex(p)],
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaShamirCombine(LuaState ls, LuaController c) {
  final csv = ls.checkString(1) ?? '';
  ls.pop(1);
  ls.pushInteger(c.jobStart(() async {
    try {
      Uint8List fromHex(String h) {
        final clean = h.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
        final out = Uint8List(clean.length ~/ 2);
        for (var i = 0; i < out.length; i++) {
          out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
        }
        return out;
      }

      final shares = csv.split('|').map(fromHex).toList();
      final restored = await Shamir().combine(shares);
      if (restored == null) {
        return jobJson({'ok': false, 'error': 'secreto irrecuperable'});
      }
      final text = latin1
          .decode(restored.where((b) => b != 0).toList());
      return jobJson({'ok': true, 'texto': text});
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}
