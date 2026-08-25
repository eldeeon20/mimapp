import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/needle_service.dart';

/// Probador de Needle v2 (45M, on-device): query + tools JSON → llamada.
/// Tools de ejemplo editables y propias; sin sumar iconos al radial:
/// se abre desde Agentes IA.
class NeedleTestScreen extends StatefulWidget {
  const NeedleTestScreen({super.key});

  @override
  State<NeedleTestScreen> createState() => _NeedleTestScreenState();
}

class _NeedleTestScreenState extends State<NeedleTestScreen> {
  final _queryCtrl = TextEditingController(text: '¿Qué tiempo hace en París?');
  final _toolsCtrl = TextEditingController();
  final _tempCtrl = TextEditingController(text: '0.0');
  final _seedCtrl = TextEditingController(text: '0');
  final _maxCtrl = TextEditingController(text: '128');

  bool _constrain = true;
  bool _busy = false;
  String _engine = 'v2';
  double? _confidence;
  String? _resultJson;
  String? _thinking;
  String? _stop;
  int? _promptTokens;
  int _ms = 0;

  static const _presets = <String, Map<String, Object>>{
    'Clima': {
      'query': '¿Qué tiempo hace en París?',
      'tools': [
        {
          "name": "get_weather",
          "parameters": {
            "type": "object",
            "properties": {
              "city": {"type": "string"},
              "unit": {"type": "string"}
            },
            "required": ["city"]
          }
        }
      ],
    },
    'Música': {
      'query': 'Ponme Theme From Shaft',
      'tools': [
        {
          "name": "play_music",
          "parameters": {
            "type": "object",
            "properties": {
              "song": {"type": "string"},
              "artist": {"type": "string"}
            },
            "required": ["song"]
          }
        },
        {
          "name": "set_volume",
          "parameters": {
            "type": "object",
            "properties": {
              "level": {"type": "number"}
            },
            "required": ["level"]
          }
        }
      ],
    },
    'Calendario': {
      'query': 'Agendá dentista el viernes a las 10',
      'tools': [
        {
          "name": "create_event",
          "parameters": {
            "type": "object",
            "properties": {
              "title": {"type": "string"},
              "date": {"type": "string"},
              "time": {"type": "string"}
            },
            "required": ["title", "date"]
          }
        }
      ],
    },
    'Nostr + IPFS': {
      'query': 'Buscá en nostr gente que hable de webgpu y subí el resumen a ipfs',
      'tools': [
        {
          "name": "search_nostr",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {"type": "string"},
              "limit": {"type": "integer"}
            },
            "required": ["query"]
          }
        },
        {
          "name": "ipfs_add",
          "parameters": {
            "type": "object",
            "properties": {
              "content": {"type": "string"},
              "pin": {"type": "boolean"}
            },
            "required": ["content"]
          }
        }
      ],
    },
    'Casa': {
      'query': 'Apagá la luz del living y poné calefacción a 21',
      'tools': [
        {
          "name": "set_light",
          "parameters": {
            "type": "object",
            "properties": {
              "room": {"type": "string"},
              "on": {"type": "boolean"},
              "brightness": {"type": "integer"}
            },
            "required": ["room", "on"]
          }
        },
        {
          "name": "set_thermostat",
          "parameters": {
            "type": "object",
            "properties": {
              "celsius": {"type": "number"}
            },
            "required": ["celsius"]
          }
        }
      ],
    },
    'Transfer': {
      'query': 'Mandale 25 dólares en BTC a ana@ejemplo.com',
      'tools': [
        {
          "name": "send_money",
          "parameters": {
            "type": "object",
            "properties": {
              "amount": {"type": "number"},
              "currency": {"type": "string"},
              "to": {"type": "string"}
            },
            "required": ["amount", "currency", "to"]
          }
        }
      ],
    },
  };

  @override
  void initState() {
    super.initState();
    _applyPreset('Clima');
    NeedleService.instance.refresh().then((_) => mounted ? setState(() {}) : null);
  }

  void _applyPreset(String name) {
    final p = _presets[name]!;
    setState(() {
      _queryCtrl.text = p['query'] as String;
      _toolsCtrl.text =
          const JsonEncoder.withIndent('  ').convert(p['tools']);
    });
  }

  Future<void> _guard(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      _show('ERROR: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m,
            style: TextStyle(color: error ? Colors.redAccent : Colors.greenAccent)),
        backgroundColor: Colors.black));
  }

  Future<void> _download() => _guard(() async {
        if (_engine == 'v2') {
          await NeedleService.instance.downloadModel();
        } else {
          await NeedleService.instance.downloadModelV1();
        }
        _show('modelo $_engine descargado · tocá Cargar');
      });

  Future<void> _load() => _guard(() async {
        final msg = _engine == 'v2'
            ? await NeedleService.instance.load()
            : await NeedleService.instance.loadV1();
        _show(msg);
      });

  void _unload() {
    if (_engine == 'v2') {
      NeedleService.instance.unload();
    } else {
      NeedleService.instance.unloadV1();
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _resultJson = null;
      _thinking = null;
      _stop = null;
      _promptTokens = null;
      _confidence = null;
    });
    try {
      final sw = Stopwatch()..start();
      final out = await (_engine == 'v2'
          ? NeedleService.instance.run(
              query: _queryCtrl.text.trim(),
              toolsJson: _toolsCtrl.text,
              constrain: _constrain,
              maxNewTokens: int.tryParse(_maxCtrl.text) ?? 128,
              temperature: double.tryParse(_tempCtrl.text) ?? 0.0,
              seed: int.tryParse(_seedCtrl.text) ?? 0,
            )
          : NeedleService.instance.runV1(
              query: _queryCtrl.text.trim(),
              toolsJson: _toolsCtrl.text,
            ));
      sw.stop();
      setState(() {
        _ms = sw.elapsedMilliseconds;
        _resultJson = out.toolCall != null
            ? NeedleService.pretty(out.toolCall!)
            : '(sin tool_call)\n${out.text}';
        _thinking = out.thinking;
        _stop = out.stop;
        _promptTokens = out.promptTokens;
      });
    } catch (e) {
      _show('ERROR: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confide() async {
    try {
      final raw = _resultJson ?? '';
      final c = await NeedleService.instance.confidence(
        query: _queryCtrl.text.trim(),
        toolsJson: _toolsCtrl.text,
        completion: raw,
      );
      setState(() => _confidence = c);
    } catch (e) {
      _show('ERROR: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = NeedleService.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Needle v2 · tools on-device')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          // ---------- selector de motor
          Row(children: [
            for (final e in const [('v2', 'Needle v2 · 45M'), ('v1', 'Needle v1 · 26M')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                    label: Text(e.$2, style: const TextStyle(fontSize: 11)),
                    selected: _engine == e.$1,
                    onSelected: (_) => setState(() => _engine = e.$1)),
              ),
          ]),
          const SizedBox(height: 8),
          // ---------- estado del modelo
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                switch (_engine) {
                  'v2' when s.loaded => 'motor v2 cargado ✓',
                  'v2' when s.downloaded =>
                    'v2 descargado (13.7 MB) · sin cargar',
                  'v1' when s.loadedV1 => 'motor v1 cargado ✓',
                  'v1' when s.downloadedV1 =>
                    'v1 descargado (22 MB + vocab) · sin cargar',
                  _ => 'sin modelo $_engine en el dispositivo',
                },
                style: const TextStyle(fontSize: 11),
              ),
              if (s.busy && !s.downloaded)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(value: s.progress),
                ),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                if (!(_engine == 'v2' ? s.downloaded : s.downloadedV1))
                  FilledButton.icon(
                      onPressed: s.busy ? null : _download,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label:
                          Text(_engine == 'v2' ? 'Descargar 13.7 MB' : 'Descargar 22 MB')),
                if ((_engine == 'v2'
                        ? s.downloaded && !s.loaded
                        : s.downloadedV1 && !s.loadedV1))
                  FilledButton.icon(
                      onPressed: s.busy ? null : _load,
                      icon: const Icon(Icons.memory_rounded, size: 18),
                      label: Text('Cargar motor $_engine')),
                if (_engine == 'v2'
                    ? s.loaded
                    : s.loadedV1)
                  OutlinedButton.icon(
                      onPressed: s.busy ? null : _unload,
                      icon: const Icon(Icons.eject_rounded, size: 18),
                      label: Text('Liberar $_engine')),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          // ---------- presets de tools
          Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _presets.keys
                  .map((k) => ActionChip(
                      label: Text(k, style: const TextStyle(fontSize: 11)),
                      onPressed: () => _applyPreset(k)))
                  .toList()),
          const SizedBox(height: 8),
          TextField(
            controller: _queryCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'query', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _toolsCtrl,
            maxLines: 8,
            style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
            decoration: const InputDecoration(
                labelText: 'tools JSON (editable, poné las tuyas)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                isDense: true),
          ),
          const SizedBox(height: 8),
          // ---------- opciones (v2 solamente: v1 es greedy y siempre restringido)
          if (_engine == 'v2')
            Row(children: [
              Switch(
                  value: _constrain,
                  onChanged: (v) => setState(() => _constrain = v)),
              const Text('constrain', style: TextStyle(fontSize: 11)),
              const Spacer(),
              _miniField(_maxCtrl, 'max tok', 60),
              const SizedBox(width: 6),
              _miniField(_tempCtrl, 'temp', 50),
              const SizedBox(width: 6),
              _miniField(_seedCtrl, 'seed', 55),
            ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ||
                    !(_engine == 'v2' ? s.loaded : s.loadedV1) ||
                    _queryCtrl.text.isEmpty
                ? null
                : _run,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded),
            label: Text('Correr con $_engine'),
          ),
          if (_stop != null) ...[
            const SizedBox(height: 4),
            Text('$_ms ms · prompt $_promptTokens tok · stop: $_stop'
                    + (_confidence != null ? ' · confianza ${(_confidence! * 100).toStringAsFixed(1)}%' : ''),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ],
          if (_resultJson != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(8)),
              child: SelectableText(_resultJson!,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      color: Colors.lightGreenAccent)),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              if (_engine == 'v2')
                OutlinedButton.icon(
                    onPressed: _busy ? null : _confide,
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label:
                        const Text('Confianza', style: TextStyle(fontSize: 11))),
            ]),
            if (_thinking != null)
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('<think>',
                      style: TextStyle(fontSize: 11, color: Colors.amberAccent)),
                  children: [
                    SelectableText(_thinking!,
                        style: TextStyle(
                            fontSize: 10.5, color: Colors.grey.shade300)),
                  ]),
          ],
        ]),
      ),
    );
  }

  Widget _miniField(TextEditingController c, String label, double w) =>
      SizedBox(
        width: w,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5),
          decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
        ),
      );
}
