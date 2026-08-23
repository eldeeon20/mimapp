part of 'lua_controller.dart';

/// Globals gpu_*: WebGPU/WGSL desde Lua, con f16 real si el chip soporta.
///
///   id = gpu_init_start()
///   gpu_info()  / gpu_has_f16()   (valores cacheados tras init)
///   id = gpu_gelu_start(n, f16)
///   id = gpu_linear_start(m, n, k, f16)
///   id = gpu_attn_start(seq, dim, f16)
///   id = gpu_wgsl_start(code, n [, dx] [, px] [, py] [, pz])  🔥 shader en caliente
void registerGpuGlobals(LuaController c) {
  c._registerSync('gpu_init_start', (ls) => _luaGpuInit(ls, c));
  c._registerSync('gpu_info', (ls) => _luaGpuInfo(ls, c));
  c._registerSync('gpu_has_f16', (ls) => _luaGpuHasF16(ls, c));
  c._registerSync('gpu_gelu_start', (ls) => _luaGpuGelu(ls, c));
  c._registerSync('gpu_linear_start', (ls) => _luaGpuLinear(ls, c));
  c._registerSync('gpu_attn_start', (ls) => _luaGpuAttn(ls, c));
  c._registerSync('gpu_wgsl_start', (ls) => _luaGpuWgsl(ls, c));
}

int _luaGpuInit(LuaState ls, LuaController c) {
  ls.pushInteger(c.jobStart(() async {
    final ok = await GpuContext.instance.init();
    return ok
        ? 'OK: ${GpuContext.instance.info}'
        : 'ERROR: sin backend GPU disponible';
  }));
  return 1;
}

int _luaGpuInfo(LuaState ls, LuaController c) {
  ls.pushString(GpuContext.instance.info);
  return 1;
}

int _luaGpuHasF16(LuaState ls, LuaController c) {
  ls.pushBoolean(GpuContext.instance.hasF16);
  return 1;
}

List<double> _randData(int n) {
  final r = Random(7);
  return List.generate(n, (_) => r.nextDouble() * 4 - 2);
}

int _luaGpuGelu(LuaState ls, LuaController c) {
  final n = (ls.checkInteger(1) ?? 65536).clamp(64, 4194304);
  var f16 = false;
  if (ls.isBoolean(2)) f16 = ls.toBoolean(2);
  ls.pop(2);
  ls.pushInteger(c.jobStart(() async {
    try {
      if (!await GpuContext.instance.init()) return 'ERROR: sin GPU';
      final r = await GpuGelu().run(_randData(n), f16: f16);
      return jobJson({
        'ok': true,
        'ms': r.elapsedMs.toStringAsFixed(2),
        'n': n,
        'f16': f16,
        'head': [for (final v in r.data.take(6)) v.toStringAsFixed(4)],
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaGpuLinear(LuaState ls, LuaController c) {
  final m = (ls.checkInteger(1) ?? 256).clamp(8, 4096);
  final n2 = (ls.checkInteger(2) ?? 256).clamp(8, 4096);
  final k = (ls.checkInteger(3) ?? 256).clamp(8, 4096);
  var f16 = false;
  if (ls.isBoolean(4)) f16 = ls.toBoolean(4);
  ls.pop(4);
  ls.pushInteger(c.jobStart(() async {
    try {
      if (!await GpuContext.instance.init()) return 'ERROR: sin GPU';
      final r = await GpuLinear().run(
        input: _randData(m), weights: _randData(n2 * k),
        bias: _randData(n2), m: m, n: n2, k: k, f16: f16,
      );
      return jobJson({
        'ok': true, 'ms': r.elapsedMs.toStringAsFixed(2),
        'shape': '$m×$k·$k×$n2', 'f16': f16,
        'head': [for (final v in r.data.take(6)) v.toStringAsFixed(3)],
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaGpuAttn(LuaState ls, LuaController c) {
  final s = (ls.checkInteger(1) ?? 128).clamp(4, 2048);
  final d = (ls.checkInteger(2) ?? 64).clamp(8, 512);
  var f16 = false;
  if (ls.isBoolean(3)) f16 = ls.toBoolean(3);
  ls.pop(3);
  ls.pushInteger(c.jobStart(() async {
    try {
      if (!await GpuContext.instance.init()) return 'ERROR: sin GPU';
      final r = await GpuAttention().run(
        q: _randData(s * d), k: _randData(s * d), v: _randData(s * d),
        seq: s, dim: d, f16: f16,
      );
      return jobJson({
        'ok': true, 'ms': r.elapsedMs.toStringAsFixed(2),
        'seq': s, 'dim': d, 'f16': f16,
        'head': [for (final v in r.data.take(6)) v.toStringAsFixed(4)],
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaGpuWgsl(LuaState ls, LuaController c) {
  final code = ls.checkString(1) ?? '';
  final n = (ls.checkInteger(2) ?? 1024).clamp(8, 1048576);
  final dx = ls.checkInteger(3) ?? ((n + 63) ~/ 64);
  final px = ls.checkNumber(4)?.toDouble() ?? 0;
  final py = ls.checkNumber(5)?.toDouble() ?? 0;
  final pz = ls.checkNumber(6)?.toDouble() ?? 0;
  ls.pop(ls.getTop());
  ls.pushInteger(c.jobStart(() async {
    try {
      if (!await GpuContext.instance.init()) return 'ERROR: sin GPU';
      final r = await GpuShaderLab().run(
        code: code,
        input: List.generate(n, (i) => i.toDouble()),
        dispatchX: dx.clamp(1, 65535), dispatchY: 1, dispatchZ: 1,
        paramX: px, paramY: py, paramZ: pz,
      );
      if (!r.ok) return jobJson({'ok': false, 'error': r.error});
      return jobJson({
        'ok': true,
        'ms': r.elapsedMs.toStringAsFixed(2),
        'head': [for (final v in r.data.take(8)) v.toStringAsFixed(3)],
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}
