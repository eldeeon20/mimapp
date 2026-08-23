part of 'lua_controller.dart';

/// Globals hf_*: cliente HuggingFace vía jobs.
///
///   id = hf_init_start(token)            token vacío = anónimo
///   id = hf_search_start(autor [, n])
///   id = hf_range_start(repo, archivo, start, end)
///   id = hf_download_start(repo, archivo, dirLocal)
void registerHfGlobals(LuaController c) {
  c._registerSync('hf_init_start', (ls) => _luaHfInit(ls, c));
  c._registerSync('hf_search_start', (ls) => _luaHfSearch(ls, c));
  c._registerSync('hf_range_start', (ls) => _luaHfRange(ls, c));
  c._registerSync('hf_download_start', (ls) => _luaHfDownload(ls, c));
}

int _luaHfInit(LuaState ls, LuaController c) {
  final token = ls.isString(1) ? (ls.toStr(1) ?? '') : '';
  ls.pop(ls.getTop());
  ls.pushInteger(c.jobStart(() async {
    try {
      await HuggingFace().init(token);
      return 'OK: cliente inicializado (${token.isEmpty ? "anónimo" : "con token"})';
    } catch (e) {
      return 'ERROR: $e';
    }
  }));
  return 1;
}

int _luaHfSearch(LuaState ls, LuaController c) {
  final author = ls.checkString(1) ?? '';
  final limit = ls.checkInteger(2) ?? 10;
  ls.pop(2);
  ls.pushInteger(c.jobStart(() async {
    try {
      final models = await HuggingFace()
          .searchModels(author: author, limit: limit.clamp(1, 50));
      return jobJson({'ok': true, 'models': models});
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaHfRange(LuaState ls, LuaController c) {
  final repo = ls.checkString(1) ?? '';
  final file = ls.checkString(2) ?? '';
  final start = ls.checkInteger(3) ?? 0;
  final end = ls.checkInteger(4) ?? 4096;
  ls.pop(4);
  ls.pushInteger(c.jobStart(() async {
    try {
      final bytes = await HuggingFace.downloadFileRange(
        repoId: repo,
        filename: file,
        start: start,
        end: end,
      );
      final printable =
          bytes.take(200).every((b) => b == 9 || b == 10 || b == 13 || (b >= 32 && b < 127));
      return jobJson({
        'ok': true,
        'bytes': bytes.length,
        'preview': printable
            ? latin1.decode(bytes.take(300).toList())
            : bytes.take(24).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' '),
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaHfDownload(LuaState ls, LuaController c) {
  final repo = ls.checkString(1) ?? '';
  final file = ls.checkString(2) ?? '';
  final dir = ls.checkString(3) ?? '';
  ls.pop(3);
  ls.pushInteger(c.jobStart(() async {
    try {
      final path = await HuggingFace().downloadFile(
        repoId: repo,
        filename: file,
        localDir: dir,
      );
      return jobJson({'ok': true, 'path': path});
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}
