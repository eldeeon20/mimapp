import '../lua/lua_controller.dart';
import '../lua/page_model.dart';

/// Lua aislado para agentes: un [LuaController] dedicado donde los
/// agentes generan páginas con la API gui_* del motor. El usuario puede
/// previsualizar el resultado desde la tarjeta del agente ("Ver GUI").
class LuaSandbox {
  static final LuaSandbox instance = LuaSandbox._();
  LuaSandbox._();

  LuaController? _ctrl;
  PageModel? lastPage;
  bool _dirty = false;

  /// Ejecuta código del agente. Retorna null si no compiló/definió page.
  PageModel? run(String code) {
    try {
      _ctrl ??= LuaController();
      lastPage = _ctrl!.load(code);
      return lastPage;
    } catch (_) {
      return null;
    }
  }

  void markDirty() => _dirty = true;
  bool consumeDirty() {
    final d = _dirty;
    _dirty = false;
    return d;
  }

  void dispose() {
    _ctrl?.dispose();
    _ctrl = null;
    lastPage = null;
  }
}
