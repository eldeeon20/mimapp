part of 'lua_controller.dart';

/// Globals de Rust (flutter_rust_bridge): greet / sum / fibonacci.
/// Registrados solo si el script los invoca; no dependen de estado del
/// controller salvo el VM subyacente.
void _registerRustGlobals(LuaController c) {
  c._registerSync('rust_greet', (ls) => _luaRustGreet(ls, c));
  c._registerSync('rust_sum', (ls) => _luaRustSum(ls, c));
  c._registerSync('rust_fibonacci', (ls) => _luaRustFibonacci(ls, c));
}

int _luaRustGreet(LuaState ls, LuaController c) {
  final name = ls.checkString(1) ?? '';
  ls.pop(1);
  ls.pushString(greet(name: name));
  return 1;
}

int _luaRustSum(LuaState ls, LuaController c) {
  final a = ls.checkInteger(1) ?? 0;
  final b = ls.checkInteger(2) ?? 0;
  ls.pop(2);
  ls.pushInteger(sum(a: a, b: b));
  return 1;
}

int _luaRustFibonacci(LuaState ls, LuaController c) {
  final n = ls.checkInteger(1) ?? 0;
  ls.pop(1);
  ls.pushInteger(fibonacci(n: n));
  return 1;
}
