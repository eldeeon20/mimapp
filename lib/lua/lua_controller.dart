import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lua_dardo_plus/lua.dart';
import 'package:pr_app/src/rust/api/simple.dart';

import '../ai/laurelia_chat.dart';
import '../media/media_player.dart';
import '../services/hf.dart';
import '../services/kem.dart';
import '../services/gpu/gpu_attention.dart';
import '../services/gpu/gpu_context.dart';
import '../services/gpu/gpu_gelu.dart';
import '../services/gpu/gpu_linear.dart';
import '../services/gpu/gpu_shader_lab.dart';
import '../services/nostr_chat.dart';
import '../services/nostr_keys.dart';
import '../services/nostr_peer_chat.dart';
import '../services/shamir.dart';
import '../widgets/gui_node.dart';
import 'downloads/download_manager.dart';
import 'lua_theme.dart';
import 'page_model.dart';
import 'page_router.dart';
import 'state_store.dart';

part 'lua_rust.dart';
part 'lua_player.dart';
part 'lua_laurelia.dart';
part 'lua_shamir.dart';
part 'lua_kem.dart';
part 'lua_hf.dart';
part 'lua_gpu.dart';
part 'lua_nostr.dart';
part 'lua_downloads.dart';

/// Controlador Lua: lee la página desde Lua y controla los bucles (recorrido
/// de `page.body`) y las llamadas (handlers Lua y funciones Rust).
///
/// Lua puede llamar a:
///   - engine_get(id) / engine_set(id, v)
///   - navigate(uri)                 -> pasa por [PageRouter] (lua://, http, tcp, udp, nostrn…)
///   - gui_* (guión inyectado)       -> construir la GUI
///   - rust_* / player_* / laurelia_*
///   - shamir_* / kem_* / hf_* / gpu_* / nostr_dm_* / nostr_obs_*
///   - job_start(fn) genérico + job_poll(id); resultados también llegan a
///     `handlers.on_event(job_id, result)` (drenaje cada 300ms).
class LuaController {
  late LuaState _lua;

  /// Estado de la GUI. Es el ÚNICO lugar donde viven los valores; se
  /// actualiza vía engine_set (o funciones que llaman a engine_set).
  final StateStore store = StateStore();

  /// Router de páginas compartido.
  final PageRouter router = PageRouter.instance;

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

-- contenedores con children
gui_card  = function(p) p.children = p.children or {}; return gui_add("card", p) end
gui_grid  = function(p) p.children = p.children or {}; return gui_add("grid", p) end
gui_scroll= function(p) p.children = p.children or {}; return gui_add("scroll", p) end

-- hipervínculo: botón que navega por el router
gui_link = function(p)
  local href = p.href or ""
  return gui_add("button", { text = p.text or href, on_click = "__nav__ " .. href })
end

-- imagen con pinch-zoom
gui_zoom_image = function(p) return gui_add("zoom_image", p) end

-- tema en caliente
theme_apply = function(p) __theme_apply(p or {}) end

function handler(nombre, fn)
  page.handlers[nombre] = fn
end

-- helper: espera un job sin bloquear (yield cooperativo no disponible;
-- usar handlers.on_event para no busy-wait).
function job_result_or_nil(id)
  local done, res = job_poll(id)
  if done then return res end
  return nil
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

  // ------------------------------------------------------------- jobs

  final Map<int, _Job> _jobs = {};
  int _jobSeq = 0;
  Timer? _drainTimer;

  /// Lanza [work] como job; retorna el id inmediatamente. Al completar,
  /// el resultado viaja a `handlers.on_event(id, resumen)` (drenaje).
  int jobStart(Future<Object?> Function() work) {
    final id = ++_jobSeq;
    _jobs[id] = _Job();
    work().then((r) {
      final j = _jobs[id];
      if (j != null) {
        j.done = true;
        j.result = r?.toString() ?? 'ok';
      }
    }).catchError((Object e) {
      final j = _jobs[id];
      if (j != null) {
        j.done = true;
        j.result = 'ERROR: $e';
      }
    });
    return id;
  }

  void _ensureDrainTimer() {
    _drainTimer ??=
        Timer.periodic(const Duration(milliseconds: 300), (_) => _drainJobs());
  }

  /// Entrega jobs terminados a `handlers.on_event(id, result)` en orden.
  void _drainJobs() {
    if (_jobs.isEmpty || _luaStateDead) return;
    for (final entry in _jobs.entries.toList()) {
      final j = entry.value;
      if (!j.done || j.delivered) continue;
      invokeHandlerArgs('on_event', [entry.key.toString(), j.result]);
      j.delivered = true;
    }
    _jobs.removeWhere((_, j) => j.delivered);
  }

  bool get _luaStateDead => !_jobsInitialized;

  bool _jobsInitialized = false;

  /// Poll manual desde Lua: done, result.
  int _luaJobPoll(LuaState ls) {
    final id = ls.checkInteger(1) ?? 0;
    ls.pop(1);
    final j = _jobs[id];
    if (j == null) {
      ls.pushBoolean(true);
      ls.pushString('ERROR: job inexistente');
      return 2;
    }
    ls.pushBoolean(j.done);
    ls.pushString(j.done ? j.result : '');
    return 2;
  }

  /// job_count() -> cantidad de jobs vivos.
  int _luaJobCount(LuaState ls) {
    ls.pushInteger(_jobs.values.where((j) => !j.delivered).length);
    return 1;
  }

  // ------------------------------------------------------------- lifecycle

  void setInputValue(String id, String value) => store.set(id, value);

  void dispose() {
    _drainTimer?.cancel();
    _jobsInitialized = false;
    store.clear();
  }

  /// Carga una página desde un asset empaquetado.
  Future<PageModel> loadFromAsset(String path) async {
    final code = await rootBundle.loadString(path);
    return load(code);
  }

  /// Carga desde código ya obtenido (el router hace fetch).
  PageModel loadFromSource(String code, {String uri = ''}) => load(code);

  /// Carga una página Lua desde una URL (compat vieja; usa el router).
  Future<PageModel> loadFromUrl(String url) async {
    final src = await router.resolve(url);
    return load(src.code);
  }

  /// Ejecuta el script Lua, recorre `page.body` (bucle) y devuelve el modelo.
  PageModel load(String code) {
    store.clear();
    _jobs.clear();
    _lua = LuaState.newState();
    _lua.openLibs();
    _registerGlobals();
    _jobsInitialized = true;
    final status = _lua.loadString(_prelude + code);
    if (status != ThreadStatus.luaOk) {
      throw Exception('El script Lua no compiló (status: $status)');
    }
    _lua.call(0, 0);
    _ensureDrainTimer();
    return _parsePage();
  }

  /// Invoca un handler (función Lua) definido en `page.handlers`.
  void invokeHandler(String name) => invokeHandlerArgs(name, const []);

  /// Invoca handler pasándole argumentos string simples.
  void invokeHandlerArgs(String name, List<String> args) {
    try {
      _lua.getGlobal('page');
      _lua.getField(-1, 'handlers');
      if (!_lua.isTable(-1)) {
        _lua.pop(2);
        return;
      }
      _lua.getField(-1, name);
      if (_lua.isFunction(-1)) {
        for (final a in args) {
          _lua.pushString(a);
        }
        _lua.pCall(args.length, 0, 0);
        _lua.pop(2); // fn+args consumidos; queda handlers + page
      } else {
        _lua.pop(3);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- globals

  void _registerGlobals() {
    _registerSync('engine_get', _luaEngineGet);
    _registerSync('engine_set', _luaEngineSet);
    _registerSync('navigate', _luaNavigate);
    _registerSync('job_poll', _luaJobPoll);
    _registerSync('job_count', _luaJobCount);
    _registerSync('__theme_apply', _luaThemeApply);
    _registerRustGlobals(this);
    _registerPlayerGlobals(this);
    _registerLaureliaGlobals(this);
    registerShamirGlobals(this);
    registerKemGlobals(this);
    registerHfGlobals(this);
    registerGpuGlobals(this);
    registerNostrGlobals(this);
    registerDownloadsGlobals(this);
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

  /// theme_apply{} desde el prelude.
  int _luaThemeApply(LuaState ls) {
    // lee tabla tope como mapa simple clave->valor escalar
    final m = <String, Object?>{};
    if (ls.isTable(-1)) {
      ls.pushNil();
      while (ls.next(-2) != 0) {
        final k = ls.toStr(-2);
        Object? v;
        if (ls.isNumber(-1)) {
          v = ls.toNumberX(-1);
        } else if (ls.isString(-1)) {
          v = ls.toStr(-1);
        }
        if (k != null && v != null) m[k] = v;
        ls.pop(1);
      }
    }
    ls.pop(1);
    luaTheme.apply(m);
    return 0;
  }

  final LuaTheme luaTheme = LuaTheme.instance;

  // ----------------------------------------------------------- navegación

  /// `navigate(uri)` pasa SIEMPRE por el PageRouter (plug-and-play).
  /// El fetch es async: al llegar el código llama onNavigate con uri;
  /// quien implementa onNavigate usa `router.resolve`.
  int _luaNavigate(LuaState ls) {
    final page = ls.checkString(1) ?? '';
    ls.pop(1);
    if (page.isNotEmpty) onNavigate?.call(page);
    return 0;
  }

  /// Fetch real para onNavigate del host: resuelve por el router.
  Future<String> fetchViaRouter(String uri) async {
    final src = await router.resolve(uri);
    return src.uri; // el host vuelve a llamar resolve o usa loadFromSource
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
      'color', 'bg_color', 'border_color', 'src', 'fit', 'href',
    ]) {
      final v = _field(-1, k);
      if (v != null) m[k] = v;
    }
    for (final k in [
      'width', 'height', 'padding', 'radius', 'border_width', 'space',
      'columns',
    ]) {
      final v = _field(-1, k);
      if (v != null) m[k] = v;
    }
    for (final k in ['bold', 'italic', 'multiline']) {
      final v = _field(-1, k);
      if (v != null) m[k] = v;
    }
    final font = _fieldTable(-1, 'font');
    if (font != null) m['font'] = font;

    final children = _childrenTable(-1);
    if (children != null) m['children'] = children;
    return m;
  }

  /// Lee `children = { nodo, nodo, ... }` recursivamente.
  List<Map<String, Object?>>? _childrenTable(int idx) {
    _lua.getField(idx, 'children');
    if (!_lua.isTable(-1)) {
      _lua.pop(1);
      return null;
    }
    final lenObj = _field(-1, 'n') as num?;
    final n = lenObj?.toInt() ?? _tableLength(-1);
    final out = <Map<String, Object?>>[];
    for (var i = 1; i <= n; i++) {
      _lua.getI(-1, i);
      if (_lua.isTable(-1)) {
        out.add(_readNodeMap());
      }
      _lua.pop(1);
    }
    _lua.pop(1); // children
    return out;
  }

  int _tableLength(int idx) {
    // iteración con next() (lua_dardo no expone el operador #)
    var n = 0;
    _lua.pushNil();
    while (_lua.next(idx) != 0) {
      n++;
      _lua.pop(1);
    }
    return n;
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

/// Job asíncrono visible para Lua.
class _Job {
  bool done = false;
  bool delivered = false;
  String result = '';
}

/// Helper para parts: convierte mapa a JSON compacto como resultado.
String jobJson(Map<String, Object?> m) => jsonEncode(m);
