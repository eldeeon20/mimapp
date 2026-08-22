import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lua_dardo_plus/lua.dart';
import 'package:pr_app/src/rust/api/simple.dart';

import '../ai/laurelia_chat.dart';
import '../media/media_player.dart';
import '../widgets/gui_node.dart';
import 'page_model.dart';
import 'state_store.dart';

part 'lua_rust.dart';
part 'lua_player.dart';
part 'lua_laurelia.dart';

/// Controlador Lua: lee la página desde Lua y controla los bucles (recorrido
/// de `page.body`) y las llamadas (handlers Lua y funciones Rust).
///
/// Lua puede llamar a:
///   - engine_get(id)               -> leer el valor actual de un widget
///   - engine_set(id, valor)        -> actualizar un widget (VALUE update)
///   - navigate("página")           -> cambiar de página (STRUCTURAL update)
///   - gui_* (guión inyectado)      -> construir la GUI llamando funciones
///   - rust_greet / rust_sum / rust_fibonacci -> llamar a Rust
///
/// Solo Lua toca el motor: cualquier cambio de valor pasa por [engine_set]
/// y cae en [StateStore]. NO hay setState global; el nodo enlazado se
/// reconstruye solo (ver [GuiRuntime]).
///
/// El archivo está dividido en partes:
///   - lua_rust.dart     (globals rust_*)
///   - lua_player.dart   (globals player_*)
///   - lua_laurelia.dart (globals laurelia_*)
class LuaController {
  late LuaState _lua;

  /// Estado de la GUI. Es el ÚNICO lugar donde viven los valores; se
  /// actualiza vía engine_set (o funciones que llaman a engine_set).
  final StateStore store = StateStore();

  /// Guión inyectado antes del script del usuario. Define la API `gui_*`
  /// (Godot-like): Lua construye la GUI llamando funciones en vez de
  /// declarar tablas con `type = "string"`.
  static const _prelude = '''
-- Motor pr_app: API de widgets (inyectada antes de tu script).
page = { title = "Pagina", body = {}, handlers = {} }

local function gui_add(tipo, props)
  props = props or {}
  props.type = tipo
  table.insert(page.body, props)
  page.body_count = #page.body
  return props
end

gui_heading = function(p) return gui_add("heading", p) end
gui_text    = function(p) return gui_add("text", p) end
gui_input   = function(p) return gui_add("input", p) end
gui_button  = function(p) return gui_add("button", p) end
gui_rect    = function(p) return gui_add("rect", p) end
gui_image   = function(p) return gui_add("rect_image", p) end
gui_divider = function(p) return gui_add("divider", p) end
gui_spacer  = function(p) return gui_add("spacer", p) end
gui_video   = function(p) return gui_add("video", p) end

function handler(nombre, fn)
  page.handlers[nombre] = fn
end
''';

  /// Reproductor compartido (media_kit) expuesto a Lua.
  MediaPlayer? mediaPlayer;

  /// Chat LLM Laurelia (descarga por HTTP + inferencia en Rust) expuesto a Lua.
  LaureliaChat? laureliaChat;

  /// Llamado por `navigate()` para cambiar de página.
  void Function(String page)? onNavigate;

  // Estado de tokens/vocab para los handlers laurelia_* (ver lua_laurelia.dart).
  Future<String>? _pendingGen;
  String _pendingGenId = '';
  int _lastTokenCount = -1;
  int _lastVocab = -1;

  /// Actualiza un valor (vía engine_set o internamente). Solo parchea el
  /// nodo enlazado; no reconstruye el árbol.
  void setInputValue(String id, String value) => store.set(id, value);

  void dispose() {
    store.clear();
  }

  /// Carga una página desde un asset empaquetado.
  Future<PageModel> loadFromAsset(String path) async {
    final code = await rootBundle.loadString(path);
    return load(code);
  }

  /// Carga una página Lua desde una URL (script descargado de la web).
  Future<PageModel> loadFromUrl(String url) async {
    url = _normalizeUrl(url);
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode} al cargar $url');
    }
    final body = utf8.decode(res.bodyBytes);
    if (body.trimLeft().startsWith('<')) {
      throw Exception(
        'La URL devolvió HTML, no código Lua. '
        'Usa la URL "raw" del archivo, p. ej. '
        'https://raw.githubusercontent.com/eduardo-bertey/fluweru/main/assets/pages/demo.lua',
      );
    }
    return load(body);
  }

  /// Convierte URLs de GitHub (blob o raw) a raw.githubusercontent.com.
  String _normalizeUrl(String url) {
    final match = RegExp(
      r'^https?://github\.com/([^/]+/[^/]+)/(blob|raw)/(.+)$',
    ).firstMatch(url);
    if (match == null) return url;
    return 'https://raw.githubusercontent.com/${match.group(1)}/${match.group(3)}';
  }

  /// Ejecuta el script Lua, recorre `page.body` (bucle) y devuelve el modelo.
  PageModel load(String code) {
    store.clear();
    _lua = LuaState.newState();
    _lua.openLibs();
    _registerGlobals();
    final status = _lua.loadString(_prelude + code);
    if (status != ThreadStatus.luaOk) {
      throw Exception('El script Lua no compiló (status: $status)');
    }
    _lua.call(0, 0);
    return _parsePage();
  }

  /// Invoca un handler (función Lua) definido en `page.handlers`.
  void invokeHandler(String name) {
    _lua.getGlobal('page');
    _lua.getField(-1, 'handlers');
    if (!_lua.isTable(-1)) {
      _lua.pop(2); // handlers no definido + page
      return;
    }
    _lua.getField(-1, name);
    if (_lua.isFunction(-1)) {
      _lua.pCall(0, 0, 0);
      _lua.pop(2); // fn + handlers + page
    } else {
      _lua.pop(3); // fn no-función + handlers + page
    }
  }

  // ---------------------------------------------------------------- globals

  void _registerGlobals() {
    _registerSync('engine_get', _luaEngineGet);
    _registerSync('engine_set', _luaEngineSet);
    _registerSync('navigate', _luaNavigate);
    _registerRustGlobals(this);
    _registerPlayerGlobals(this);
    _registerLaureliaGlobals(this);
  }

  void _registerSync(String name, int Function(LuaState) fn) {
    _lua.pushDartFunction(fn);
    _lua.setGlobal(name);
  }

  int _luaEngineGet(LuaState ls) {
    final id = ls.checkString(1) ?? '';
    ls.pop(1);
    ls.pushString(store.get(id));
    return 1;
  }

  int _luaEngineSet(LuaState ls) {
    final id = ls.checkString(1) ?? '';
    final value = ls.checkString(2) ?? '';
    ls.pop(2);
    store.set(id, value);
    return 0;
  }

  // ----------------------------------------------------------- navegación

  /// `navigate("player")` cambia de página (llama a onNavigate).
  int _luaNavigate(LuaState ls) {
    final page = ls.checkString(1) ?? '';
    ls.pop(1);
    if (page.isNotEmpty) onNavigate?.call(page);
    return 0;
  }

  // ---------------------------------------------------------------- parsing

  /// Lee la tabla global `page` y recorre `page.body` (bucle sobre
  /// `body_count`) convirtiendo cada nodo en un [GuiNode].
  PageModel _parsePage() {
    _lua.getGlobal('page');
    if (!_lua.isTable(-1)) {
      final got = _lua.isNil(-1) ? 'nil' : _lua.typeName2(-1);
      _lua.pop(1);
      throw Exception('El script no definió la tabla global "page" ($got)');
    }
    final title = _field(-1, 'title') as String? ?? 'Página';
    final count = (_field(-1, 'body_count') as num?)?.toInt() ?? 0;

    _lua.getField(-1, 'body');
    final body = <GuiNode>[];
    for (var i = 1; i <= count; i++) {
      _lua.getI(-1, i);
      body.add(GuiNode.fromMap(_readNodeMap()));
      _lua.pop(1);
    }
    _lua.pop(1); // body
    _lua.pop(1); // page
    return PageModel(title: title, body: body);
  }

  /// Lee los campos de un nodo (la tabla en el tope de la pila) a un mapa.
  Map<String, Object?> _readNodeMap() {
    final m = <String, Object?>{};
    for (final k in [
      'type', 'id', 'bind', 'text', 'label', 'value', 'on_click', 'align',
      'color', 'bg_color', 'border_color', 'src', 'fit',
    ]) {
      final v = _field(-1, k);
      if (v != null) m[k] = v;
    }
    for (final k in ['width', 'height', 'padding', 'radius', 'border_width', 'space']) {
      final v = _field(-1, k);
      if (v != null) m[k] = v;
    }
    for (final k in ['bold', 'italic', 'multiline']) {
      final v = _field(-1, k);
      if (v != null) m[k] = v;
    }
    final font = _fieldTable(-1, 'font');
    if (font != null) m['font'] = font;
    return m;
  }

  /// Lee un campo escalar (string/número/booleano) de la tabla en `idx`.
  Object? _field(int idx, String key) {
    _lua.getField(idx, key);
    Object? v;
    // OJO: en lua_dardo `isString` devuelve true también para números, así
    // que los números deben chequearse ANTES que los strings.
    if (_lua.isInteger(-1)) {
      v = _lua.toIntegerX(-1);
    } else if (_lua.isNumber(-1)) {
      v = _lua.toNumberX(-1);
    } else if (_lua.isString(-1)) {
      v = _lua.toStr(-1);
    } else if (_lua.isBoolean(-1)) {
      v = _lua.toBoolean(-1);
    }
    _lua.pop(1);
    return v;
  }

  /// Lee un campo que es una sub-tabla (p. ej. `font`) y devuelve su mapa.
  Map<String, Object?>? _fieldTable(int idx, String key) {
    _lua.getField(idx, key);
    if (!_lua.isTable(-1)) {
      _lua.pop(1);
      return null;
    }
    final m = <String, Object?>{};
    for (final k in ['family', 'size', 'bold', 'italic', 'color']) {
      final v = _field(-1, k);
      if (v != null) m[k] = v;
    }
    _lua.pop(1);
    return m;
  }
}
