import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colab_runtime.dart';

void _copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Copiado al portapapeles'),
        duration: Duration(seconds: 1)),
  );
}

class _Cell {
  final TextEditingController code;
  String output = '';
  bool running = false;
  String status = ''; // '', 'ok', 'error', 'running'

  _Cell([String initial = '']) : code = TextEditingController(text: initial);
}

/// Notebook simple: celdas Python ejecutadas en el kernel de Colab.
class ColabCellsScreen extends StatefulWidget {
  final String serverUrl;
  final String proxyToken;

  const ColabCellsScreen({
    super.key,
    required this.serverUrl,
    required this.proxyToken,
  });

  @override
  State<ColabCellsScreen> createState() => _ColabCellsScreenState();
}

class _ColabCellsScreenState extends State<ColabCellsScreen> {
  late final ColabRuntime _runtime;
  final List<_Cell> _cells = [];
  String _connStatus = 'Conectando...';
  bool _connected = false;
  bool _connecting = false;
  String? _lastConnError;
  int? _runningIndex;

  static const _helloWorld = '''# Ejemplo de prueba
print("Hola Mundo desde Colab 🚀")
import sys
print("Python:", sys.version.split()[0])''';

  @override
  void initState() {
    super.initState();
    _runtime =
        ColabRuntime(serverUrl: widget.serverUrl, proxyToken: widget.proxyToken);
    // Input interactivo: cuando el kernel pide datos (input()), abrir diálogo.
    _runtime.onInputRequest = _askInput;
    // Celda de ejemplo precargada para probar al instante.
    _cells.add(_Cell(_helloWorld));
    _connect();
  }

  Future<String?> _askInput(String prompt, bool password) async {
    final ctrl = TextEditingController();
    String? value;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('El programa pide datos'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: password,
          decoration: InputDecoration(
            labelText: prompt.isEmpty ? 'Ingresá un valor:' : prompt,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Enviar')),
        ],
      ),
    );
    value = ctrl.text;
    ctrl.dispose();
    return value;
  }

  Future<void> _connect() async {
    try {
      await _runtime.start();
      setState(() {
        _connected = true;
        _connecting = false;
        _connStatus = 'Kernel conectado';
      });
    } catch (e) {
      setState(() {
        _connStatus = 'Error: $e';
        _connecting = false;
      });
      _lastConnError = e.toString();
    }
  }

  Future<void> _runCell(int i) async {
    final cell = _cells[i];
    if (!_connected || cell.running) return;
    setState(() {
      cell.running = true;
      cell.status = 'running';
      cell.output = '';
      _runningIndex = i;
    });
    try {
      final res = await _runtime.execute(
        cell.code.text,
        onTick: (partial) {
          // Salida EN VIVO: se pinta a medida que el kernel emite mensajes.
          if (partial.isNotEmpty && mounted) {
            setState(() => cell.output = partial);
          }
        },
      );
      setState(() {
        cell.output = res.output.isEmpty ? '(sin salida)' : res.output;
        cell.status = res.isError ? 'error' : 'ok';
      });
    } catch (e) {
      setState(() {
        cell.output = 'Error: $e';
        cell.status = 'error';
      });
    } finally {
      if (mounted) {
        setState(() {
          cell.running = false;
          _runningIndex = null;
        });
      }
    }
  }

  void _stopCell() => _runtime.interruptCurrent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Colab Python ${_connected ? "●" : "○"}'),
        actions: [
          if (_runningIndex != null)
            IconButton(
              tooltip: 'Frenar celda',
              onPressed: _stopCell,
              icon: const Icon(Icons.stop, color: Colors.redAccent),
            ),
          IconButton(
            tooltip: 'Nueva celda',
            onPressed: () => setState(() => _cells.add(_Cell())),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(_connected ? Icons.check_circle : Icons.error,
                    size: 14,
                    color: _connected ? Colors.greenAccent : Colors.redAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_connStatus,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                if (_lastConnError != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copiar error',
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => _copyText(context, _lastConnError!),
                  ),
                if (!_connected && !_connecting)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Reintentar conexión',
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () {
                      setState(() {
                        _connStatus = 'Conectando...';
                        _lastConnError = null;
                        _connecting = true;
                      });
                      _connect();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _cells.length,
              itemBuilder: (context, i) {
                final cell = _cells[i];
                return Card(
                  color: const Color(0xFF0B1220),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text('[${i + 1}]',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                    fontFamily: 'monospace')),
                            const Spacer(),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: cell.running || !_connected
                                  ? null
                                  : () => _runCell(i),
                              icon: cell.running
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.play_arrow,
                                      color: Colors.greenAccent),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: _cells.length <= 1
                                  ? null
                                  : () =>
                                      setState(() => _cells.removeAt(i)),
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.redAccent),
                            ),
                          ],
                        ),
                        TextField(
                          controller: cell.code,
                          maxLines: null,
                          minLines: 3,
                          style: const TextStyle(
                              fontSize: 13, fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFF111827),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            hintText: 'Código Python...',
                          ),
                        ),
                        if (cell.output.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            constraints:
                                const BoxConstraints(minHeight: 40),
                            padding:
                                const EdgeInsets.fromLTRB(8, 4, 4, 8),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: cell.status == 'error'
                                    ? Colors.redAccent.withValues(alpha: .4)
                                    : Colors.greenAccent
                                        .withValues(alpha: .25),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cell.output,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: cell.status == 'error'
                                        ? Colors.redAccent[100]
                                        : Colors.greenAccent[100],
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.bottomRight,
                                  child: IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Copiar salida',
                                    icon: const Icon(Icons.copy, size: 14),
                                    onPressed: () =>
                                        _copyText(context, cell.output),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _runtime.close();
    for (final c in _cells) {
      c.code.dispose();
    }
    super.dispose();
  }
}
