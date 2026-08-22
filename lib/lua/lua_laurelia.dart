part of 'lua_controller.dart';

/// Globals de Laurelia (chat LLM en Rust/Candle). Solo se registran si hay
/// un [LaureliaChat] conectado. El progreso de descarga escribe directo en
/// [StateStore] (el nodo enlazado se repinta solo), sin setState global.
void _registerLaureliaGlobals(LuaController c) {
  if (c.laureliaChat == null) return;
  c._registerSync('laurelia_download', (ls) => _luaLaureliaDownload(ls, c));
  c._registerSync(
      'laurelia_download_and_load', (ls) => _luaLaureliaDownloadAndLoad(ls, c));
  c._registerSync('laurelia_load', (ls) => _luaLaureliaLoad(ls, c));
  c._registerSync('laurelia_generate', (ls) => _luaLaureliaGenerate(ls, c));
  c._registerSync(
      'laurelia_count_tokens', (ls) => _luaLaureliaCountTokens(ls, c));
  c._registerSync('laurelia_status', (ls) => _luaLaureliaStatus(ls, c));
  c._registerSync('laurelia_is_loaded', (ls) => _luaLaureliaIsLoaded(ls, c));
  c._registerSync('laurelia_vocab', (ls) => _luaLaureliaVocab(ls, c));
  c._registerSync('laurelia_unload', (ls) => _luaLaureliaUnload(ls, c));
  c._registerSync('laurelia_info', (ls) => _luaLaureliaInfo(ls, c));
  c._registerSync('laurelia_set_model', (ls) => _luaLaureliaSetModel(ls, c));
  c._registerSync(
      'laurelia_delete_model', (ls) => _luaLaureliaDeleteModel(ls, c));
}

/// Descarga el modelo por HTTP (streaming). El progreso actualiza el store
/// (solo el nodo enlazado se repinta) y al terminar escribe el estado real.
int _luaLaureliaDownload(LuaState ls, LuaController c) {
  ls.pop(0);
  final chat = c.laureliaChat!;
  chat.onProgress = (msg) => c.store.set('laurelia_status', msg);
  c.store.set('laurelia_status', 'Descargando…');
  chat.download().then((ok) {
    if (ok) {
      c.store.set('laurelia_status',
          '${chat.modelName} descargado. Tocá "Cargar en Rust".');
    } else {
      c.store.set('laurelia_status', chat.status);
    }
    _refreshLaureliaInfo(c);
  });
  return 0;
}

/// Descarga el modelo por HTTP (streaming) y luego lo carga en Rust desde
/// disco en una sola acción.
int _luaLaureliaDownloadAndLoad(LuaState ls, LuaController c) {
  ls.pop(0);
  final chat = c.laureliaChat!;
  chat.onProgress = (msg) => c.store.set('laurelia_status', msg);
  chat.download().then((ok) {
    if (!ok) {
      c.store.set('laurelia_status', chat.status);
      _refreshLaureliaInfo(c);
      return;
    }
    chat.load().then((loaded) {
      c.store.set('laurelia_status',
          loaded ? 'Modelo cargado en Rust. Tocá Generar.' : chat.status);
      _refreshLaureliaInfo(c);
    });
  });
  return 0;
}

/// Carga el modelo descargado en Rust.
int _luaLaureliaLoad(LuaState ls, LuaController c) {
  ls.pop(0);
  final chat = c.laureliaChat!;
  chat.onProgress = (msg) => c.store.set('laurelia_status', msg);
  c.store.set('laurelia_status', 'Cargando en Rust…');
  chat.load().then((ok) {
    c.store.set('laurelia_status',
        ok ? 'Modelo cargado en Rust. Tocá Generar.' : chat.status);
    _refreshLaureliaInfo(c);
  });
  return 0;
}

/// Cambia el modelo seleccionado (base/fine).
int _luaLaureliaSetModel(LuaState ls, LuaController c) {
  final name = ls.checkString(1) ?? 'base';
  ls.pop(1);
  final chat = c.laureliaChat!;
  chat.setModel(name).then((_) {
    c.store
        .set('laurelia_status', 'Modelo seleccionado: ${chat.modelName}');
    _refreshLaureliaInfo(c);
  });
  return 0;
}

/// Elimina el modelo indicado (borra su carpeta en disco).
int _luaLaureliaDeleteModel(LuaState ls, LuaController c) {
  final name = ls.checkString(1) ?? '';
  ls.pop(1);
  final chat = c.laureliaChat!;
  chat.deleteModel(name).then((ok) {
    c.store.set('laurelia_status',
        ok ? 'Modelo $name eliminado.' : 'Modelo $name: no existe.');
    _refreshLaureliaInfo(c);
  });
  return 0;
}

/// Refresca `laurelia_info` (detalle en disco + Rust) sin esperar al usuario.
void _refreshLaureliaInfo(LuaController c) {
  final chat = c.laureliaChat;
  if (chat == null) return;
  chat.detailedStatus().then((s) => c.store.set('laurelia_info', s));
}

/// Genera texto con el prompt del argumento 1. El resultado queda en
/// `laurelia_out` (lo muestra un gui_text con id "laurelia_out").
int _luaLaureliaGenerate(LuaState ls, LuaController c) {
  final prompt = ls.checkString(1) ?? '';
  final maxTokens = ls.checkInteger(2) ?? 50;
  ls.pop(2);
  final chat = c.laureliaChat;
  if (chat == null) {
    c.store.set('laurelia_out', 'Chat no disponible');
    return 0;
  }
  if (!chat.loaded) {
    c.store.set('laurelia_out', 'Primero tocá "Cargar en Rust".');
    return 0;
  }
  c.store.set('laurelia_out', 'Generando… (puede tardar)');
  chat.generate(prompt, maxNewTokens: maxTokens).then((s) {
    c.store.set('laurelia_out',
        s.isEmpty ? 'Generación vacía (¿modelo cargado?).' : s);
  });
  return 0;
}

/// Devuelve la cantidad de tokens del texto (o -1 si no hay tokenizer).
int _luaLaureliaCountTokens(LuaState ls, LuaController c) {
  final text = ls.checkString(1) ?? '';
  ls.pop(1);
  final n = c.laureliaChat!.countTokens(text);
  n.then((v) => c._lastTokenCount = v);
  ls.pushInteger(c._lastTokenCount);
  return 1;
}

/// Estado del chat (texto). La UI lo muestra en un gui_text.
int _luaLaureliaStatus(LuaState ls, LuaController c) {
  ls.pop(0);
  ls.pushString(_luaChatStatus(c));
  return 1;
}

/// Info detallada: ruta, tamaño de archivos, si descarga completa y si el
/// modelo está cargado en Rust. Escribe el resultado en `laurelia_info`.
int _luaLaureliaInfo(LuaState ls, LuaController c) {
  ls.pop(0);
  c.store.set('laurelia_info', 'Leyendo disco…');
  c.laureliaChat!.detailedStatus().then((s) => c.store.set('laurelia_info', s));
  ls.pushString(c.store.get('laurelia_info'));
  return 1;
}

int _luaLaureliaIsLoaded(LuaState ls, LuaController c) {
  ls.pop(0);
  ls.pushBoolean(c.laureliaChat!.loaded);
  return 1;
}

/// Vocabulario del tokenizer (o -1).
int _luaLaureliaVocab(LuaState ls, LuaController c) {
  ls.pop(0);
  ls.pushInteger(c._lastVocab);
  c.laureliaChat!.vocabSize().then((v) => c._lastVocab = v);
  return 1;
}

int _luaLaureliaUnload(LuaState ls, LuaController c) {
  ls.pop(0);
  final chat = c.laureliaChat!;
  chat.unload().then((_) {
    c.store.set('laurelia_status', 'Modelo liberado.');
    _refreshLaureliaInfo(c);
  });
  return 0;
}

/// Texto de estado del chat para mostrar en la UI.
String _luaChatStatus(LuaController c) {
  final chat = c.laureliaChat;
  if (chat == null) return 'Chat no disponible';
  final base = chat.status;
  final extra = <String>[];
  if (c._lastTokenCount >= 0) extra.add('tokens: ${c._lastTokenCount}');
  if (c._lastVocab > 0) extra.add('vocab: ${c._lastVocab}');
  if (chat.loaded) extra.add('cargado');
  return extra.isEmpty ? base : '$base | ${extra.join(', ')}';
}
