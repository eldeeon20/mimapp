part of 'lua_controller.dart';

/// Globals dl_*: descargas reales (Dart puro) con notificación de MB.
/// El % vivo llega a la GUI vía engine_set("dl_<id>", pct) y el resultado
/// final también como job event.
///
///   id = dl_start(url [, nombre] [, ask=1])
///   dl_cancel(id)
///   dl_tasks()  -> json resumen
void registerDownloadsGlobals(LuaController c) {
  c._registerSync('dl_start', (ls) => _luaDlStart(ls, c));
  c._registerSync('dl_cancel', (ls) => _luaDlCancel(ls, c));
  c._registerSync('dl_tasks', (ls) => _luaDlTasks(ls, c));

  // puente progreso -> engine_set para nodos enlazados
  DownloadManager.instance.onProgress = (id, p, task) {
    c.setInputValue('dl_$id', p);
  };
}

int _luaDlStart(LuaState ls, LuaController c) {
  final url = ls.checkString(1) ?? '';
  String? name;
  var ask = false;
  if (ls.isString(2)) name = ls.toStr(2);
  if (ls.isInteger(3) || ls.isNumber(3)) ask = (ls.toNumberX(3) ?? 0) != 0;
  ls.pop(ls.getTop());

  if (url.isEmpty) {
    ls.pushInteger(c.jobStart(() async => 'ERROR: url vacía'));
    return 1;
  }
  ls.pushInteger(c.jobStart(() async {
    try {
      final tid =
          await DownloadManager.instance.start(url, fileName: name, askWhere: ask);
      // espera a que termine para disparar on_event con el resumen
      while (true) {
        final t = DownloadManager.instance.tasks.firstWhere((t) => t.id == tid);
        if (t.status != DlStatus.activa) {
          return jobJson({
            'ok': t.status == DlStatus.ok,
            'path': t.path,
            'mb': t.mb,
            'status': t.status.name,
            'error': t.error,
          });
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaDlCancel(LuaState ls, LuaController c) {
  final id = ls.checkInteger(1) ?? -1;
  ls.pop(1);
  try {
    DownloadManager.instance.cancel(id);
    c.setInputValue('dl_$id', 'cancelada');
  } catch (_) {}
  return 0;
}

int _luaDlTasks(LuaState ls, LuaController c) {
  ls.pushString(jobJson({
    'tasks': [
      for (final t in DownloadManager.instance.tasks)
        {
          'id': t.id,
          'url': t.url,
          'status': t.status.name,
          'pct': DownloadManager.pct(t),
          'mb': t.mb,
          'path': t.path,
        },
    ],
  }));
  return 1;
}
