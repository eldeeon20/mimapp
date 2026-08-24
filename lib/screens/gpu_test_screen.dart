import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/gpu/gpu_attention.dart';
import '../services/gpu/gpu_context.dart';
import '../services/gpu/gpu_gelu.dart';
import '../services/gpu/gpu_linear.dart';
import '../services/gpu/gpu_shader_lab.dart';

/// GPU compute: tabs [Operaciones] (GELU/Linear/Attention F32 vs F16) y
/// [Shader Lab] (celda estilo Colab para correr WGSL en caliente).
class GpuTestScreen extends StatelessWidget {
  const GpuTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const TabBar(tabs: [
          Tab(text: 'Operaciones'),
          Tab(text: 'Shader Lab'),
        ], labelStyle: TextStyle(fontSize: 12)),
        const Expanded(
          child: TabBarView(children: [_OpsTab(), _LabTab()]),
        ),
      ]),
    );
  }
}

// ======================================================================
// TAB OPERACIONES
// ======================================================================

class _OpCard {
  final String title;
  final bool ok;
  final double ms;
  final String detail;
  final List<double> preview;
  _OpCard(this.title, this.ok, this.ms, this.detail, this.preview);
}

class _OpsTab extends StatefulWidget {
  const _OpsTab();

  @override
  State<_OpsTab> createState() => _OpsTabState();
}

class _OpsTabState extends State<_OpsTab>
    with AutomaticKeepAliveClientMixin {
  final _gelu = GpuGelu();
  final _linear = GpuLinear();
  final _attn = GpuAttention();

  bool _initing = false;
  bool _ready = false;
  bool _f16 = false;
  int _n = 65536;
  final _results = <_OpCard>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _doInit();
  }

  Future<void> _doInit() async {
    setState(() => _initing = true);
    await GpuContext.instance.init();
    if (!mounted) return;
    setState(() {
      _ready = GpuContext.instance.ready;
      _initing = false;
    });
  }

  List<double> _randData(int n) {
    final r = math.Random(42);
    return List.generate(n, (_) => r.nextDouble() * 4 - 2);
  }

  Future<void> _runGelu() async {
    try {
      final useF16 = _f16 && GpuContext.instance.hasF16;
      final input = _randData(_n);
      final r = await _gelu.run(input, f16: useF16);
      setState(() {
        _results.insert(
            0,
            _OpCard('GELU ${useF16 ? "F16" : "F32"}${_f16 && !useF16 ? " (auto)" : ""}',
                true,
                r.elapsedMs,
                '${input.length} elementos · ${(input.length * (useF16 ? 2 : 4) / 1024).toStringAsFixed(0)} KB',
                r.data.take(8).toList()));
      });
    } catch (e) {
      _err('GELU', '$e');
    }
  }

  Future<void> _runLinear() async {
    try {
      const m = 256, k = 256, n = 256;
      final useF16 = _f16 && GpuContext.instance.hasF16;
      final input = _randData(m * k);
      final weights = _randData(n * k);
      final bias = _randData(n);
      final r = await _linear.run(
          input: input, weights: weights, bias: bias, m: m, n: n, k: k,
          f16: useF16);
      setState(() {
        _results.insert(
            0,
            _OpCard('LINEAR ${useF16 ? "F16" : "F32"}${_f16 && !useF16 ? " (auto)" : ""}',
                true,
                r.elapsedMs,
                '($m×$k)·($k×$n)ᵀ+b → ${(m * k + n * k) * (useF16 ? 2 : 4) / 1024} KB pesos',
                r.data.take(8).toList()));
      });
    } catch (e) {
      _err('LINEAR', '$e');
    }
  }

  Future<void> _runAttention() async {
    try {
      const s = 128, d = 64;
      final useF16 = _f16 && GpuContext.instance.hasF16;
      final q = _randData(s * d);
      final kk = _randData(s * d);
      final v = _randData(s * d);
      final r =
          await _attn.run(q: q, k: kk, v: v, seq: s, dim: d, f16: useF16);
      setState(() {
        _results.insert(
            0,
            _OpCard('ATTENTION ${useF16 ? "F16" : "F32"}${_f16 && !useF16 ? " (auto)" : ""}',
                true,
                r.elapsedMs,
                'seq=$s dim=$d softmax(QKᵀ/√d)·V',
                r.data.take(8).toList()));
      });
    } catch (e) {
      _err('ATTENTION', '$e');
    }
  }

  void _err(String op, String msg) {
    if (!mounted) return;
    setState(() => _results.insert(0, _OpCard(op, false, 0, msg, [])));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ctx = GpuContext.instance;
    return Column(children: [
      _header(ctx),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          Text('Buffer N: $_n',
              style: const TextStyle(fontSize: 11)),
          Expanded(
            child: Slider(
              value: _n.toDouble(),
              min: 1024,
              max: 1048576,
              divisions: 10,
              label: '$_n',
              onChanged: (v) => setState(() => _n = v.round()),
            ),
          ),
          const Text('F16',
              style: TextStyle(fontSize: 11)),
          Switch(
            value: _f16,
            onChanged: (v) => setState(() => _f16 = v),
          ),
        ]),
      ),
      Wrap(spacing: 8, children: [
        _btn('GELU', Icons.functions_rounded, Colors.cyanAccent, _runGelu),
        _btn('LINEAR', Icons.grid_on_rounded, Colors.orangeAccent, _runLinear),
        _btn('ATTN', Icons.center_focus_strong_rounded,
            Colors.deepPurpleAccent, _runAttention),
      ]),
      Expanded(
        child: _results.isEmpty
            ? Center(
                child: Text(_ready
                    ? 'elegí una operación'
                    : 'esperando GPU…',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)))
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _results.length,
                itemBuilder: (_, i) => _card(_results[i]),
              ),
      ),
    ]);
  }

  Widget _header(GpuContext ctx) {
    final color = _ready
        ? (ctx.hasF16 ? Colors.greenAccent : Colors.orangeAccent)
        : Colors.redAccent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: _initing
          ? const Row(children: [
              SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('inicializando GPU…',
                  style: TextStyle(fontSize: 11)),
            ])
          : Text(
              _ready ? ctx.info : 'GPU no disponible en este dispositivo',
              style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: color)),
    );
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback fn) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: .08),
      side: BorderSide(color: color.withValues(alpha: .5)),
      onPressed: _ready ? fn : null,
    );
  }

  Widget _card(_OpCard c) {
    final color = c.ok ? Colors.greenAccent : Colors.redAccent;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF0B1226),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: .4))),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(c.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: color, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(c.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
            Text('${c.ms.toStringAsFixed(2)} ms',
                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: color)),
          ]),
          Text(c.detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
          if (c.preview.isNotEmpty)
            Text(c.preview.map((x) => x.toStringAsFixed(4)).join('  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9,
                    fontFamily: 'monospace', color: Colors.white38)),
        ]),
      ),
    );
  }
}

// ======================================================================
// TAB SHADER LAB (celda estilo Colab)
// ======================================================================

class _LabTab extends StatefulWidget {
  const _LabTab();

  @override
  State<_LabTab> createState() => _LabTabState();
}

class _LabTabState extends State<_LabTab>
    with AutomaticKeepAliveClientMixin {
  final _lab = GpuShaderLab();
  final _codeCtrl = TextEditingController();
  final _pxCtrl = TextEditingController(text: '2');
  final _pyCtrl = TextEditingController(text: '1');
  final _pzCtrl = TextEditingController(text: '0');
  int _n = 1024;
  bool _running = false;
  bool? _ok;
  String _meta = '';
  String _preview = '';
  Color _resultColor = Colors.transparent;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  Future<void> _loadTemplate() async {
    try {
      final t = await _lab.template();
      if (mounted && _codeCtrl.text.isEmpty) {
        setState(() => _codeCtrl.text = t);
      }
    } catch (_) {}
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _ok = null;
      _meta = '';
      _preview = '';
    });
    try {
      final input =
          List<double>.generate(_n, (i) => (i % 17).toDouble() - 8);
      final wg = ((_n + 63) ~/ 64).clamp(1, 65535);
      final px = double.tryParse(_pxCtrl.text.trim()) ?? 0;
      final py = double.tryParse(_pyCtrl.text.trim()) ?? 0;
      final pz = double.tryParse(_pzCtrl.text.trim()) ?? 0;
      final r = await _lab.run(
        code: _codeCtrl.text,
        input: input,
        dispatchX: wg,
        dispatchY: 1,
        dispatchZ: 1,
        paramX: px,
        paramY: py,
        paramZ: pz,
      );
      setState(() {
        _ok = r.ok;
        if (r.ok) {
          _resultColor = Colors.greenAccent;
          _meta = '${r.mode} · ${r.elapsedMs.toStringAsFixed(2)} ms · '
              '${r.data.length} elementos';
          _preview = r.data
              .take(12)
              .map((x) => x.toStringAsFixed(4))
              .join('  ');
        } else {
          _resultColor = Colors.redAccent;
          _meta = r.error;
          _preview = '';
        }
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _resultColor = Colors.redAccent;
        _meta = '$e';
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _pxCtrl.dispose();
    _pyCtrl.dispose();
    _pzCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Expanded(
        flex: 5,
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .5),
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _codeCtrl,
            maxLines: null,
            expands: true,
            style: const TextStyle(
                fontSize: 11, fontFamily: 'monospace', height: 1.4),
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.all(10),
              border: InputBorder.none,
              hintText: '// pegá tu kernel WGSL acá…',
              hintStyle: TextStyle(fontSize: 10),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          Text('N: $_n', style: const TextStyle(fontSize: 11)),
          Expanded(
            child: Slider(
              value: _n.toDouble(),
              min: 64,
              max: 65536,
              divisions: 10,
              onChanged: (v) => setState(() => _n = v.round()),
            ),
          ),
          _param('x', _pxCtrl, 60),
          _param('y', _pyCtrl, 60),
          _param('z', _pzCtrl, 60),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(children: [
          IconButton(
            onPressed: () async {
              final t = await _lab.template();
              if (mounted) setState(() => _codeCtrl.text = t);
            },
            icon: const Icon(Icons.restore_rounded, size: 20),
            tooltip: 'Plantilla',
          ),
          IconButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: _codeCtrl.text)),
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: 'Copiar shader',
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('RUN'),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.pinkAccent.withValues(alpha: .8)),
          ),
        ]),
      ),
      if (_ok != null)
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 60),
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _resultColor.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _resultColor.withValues(alpha: .5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(_meta,
                style: TextStyle(
                    fontSize: 10.5, fontFamily: 'monospace', color: _resultColor)),
            if (_preview.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(_preview,
                  style: const TextStyle(fontSize: 9.5,
                      fontFamily: 'monospace', color: Colors.white54)),
            ],
          ]),
        ),
    ]);
  }

  Widget _param(String label, TextEditingController ctrl, double w) {
    return SizedBox(
      width: w,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 9),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
