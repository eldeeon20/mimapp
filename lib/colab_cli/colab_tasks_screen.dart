import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/settings.dart';
import 'colab_prefabs.dart';
import 'colab_runtime.dart';
import 'colab_task_models.dart';

void _copyTxt(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
        content: Text('Copiado al portapapeles'),
        duration: Duration(seconds: 1)),
  );
}

/// Tareas Colab: plantillas Python (Tareas) + envíos con argumento
/// (Pockets) en cola secuencial. Los errores no frenan la cola.
class ColabTasksScreen extends StatefulWidget {
  final String serverUrl;
  final String proxyToken;

  const ColabTasksScreen({
    super.key,
    required this.serverUrl,
    required this.proxyToken,
  });

  @override
  State<ColabTasksScreen> createState() => _ColabTasksScreenState();
}

class _ColabTasksScreenState extends State<ColabTasksScreen>
    with WidgetsBindingObserver {
  late final ColabRuntime _runtime;
  List<ColabTask> _tasks = [];
  List<ColabPocket> _pockets = [];
  bool _connected = false;
  bool _connecting = false;
  String _connStatus = 'Conectando...';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runtime =
        ColabRuntime(serverUrl: widget.serverUrl, proxyToken: widget.proxyToken);
    _runtime.onInputRequest = _askInput;
    final s = Settings.instance;
    _tasks = s.tasks.map(ColabTask.fromMap).toList();
    // Pockets que quedaron 'running' de una sesión anterior vuelven a la cola.
    _pockets = s.pockets.map(ColabPocket.fromMap).toList();
    for (final p in _pockets) {
      if (p.status == 'running') p.status = 'pendiente';
    }
    _connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// La app se va a fondo / se cierra: guardar YA (best effort). Sin
  /// esto, cerrar justo después de "guardado" perdía todo porque el
  /// save() async no había terminado de escribir el config.pr.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      Settings.instance.tasks = _tasks.map((t) => t.toMap()).toList();
      Settings.instance.pockets = _pockets.map((p) => p.toMap()).toList();
      Settings.instance.save();
    }
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _connStatus = 'Conectando...';
    });
    try {
      await _runtime.start();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _connecting = false;
        _connStatus = 'Conectado ●';
      });
      _maybeRunNext();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _connecting = false;
        _connStatus = 'Sin conexión: $e';
      });
    }
  }

  /// Guarda en config.pr. SE ESPERA (await): antes era fuego y olvido
  /// y el "✓ guardado" salía ANTES de escribir el archivo; cerrar la
  /// app en ese hueco lo perdía todo (PBKDF2 200k tarda segundos).
  Future<void> _persist() async {
    Settings.instance.tasks = _tasks.map((t) => t.toMap()).toList();
    Settings.instance.pockets = _pockets.map((p) => p.toMap()).toList();
    await Settings.instance.save();
  }

  ColabTask? _taskById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  // ---------------- Cola ----------------

  Future<void> _maybeRunNext() async {
    if (_running || !_connected || !mounted) return;
    ColabPocket? next;
    for (final p in _pockets) {
      if (p.status == 'pendiente') {
        next = p;
        break;
      }
    }
    if (next == null) return;
    final task = _taskById(next.taskId);
    setState(() => _running = true);
    if (task == null) {
      next.status = 'error';
      next.output = '(la tarea origen fue borrada)';
    } else {
      next.status = 'running';
      final code = task.hasArg
          ? 'ARG = ${jsonEncode(next.argumento)}\n${task.code}'
          : task.code;
      try {
        final r = await _runtime.execute(code,
            onTick: (partial) {
              if (!mounted) return;
              setState(() => next!.output = partial);
            });
        next.output = r.output.isEmpty ? '(sin salida)' : r.output;
        next.status = r.isError ? 'error' : 'ok';
      } catch (e) {
        next.status = 'error';
        next.output = 'Error: $e';
      }
    }
    next.updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _persist();
    if (!mounted) return;
    setState(() => _running = false);
    _maybeRunNext(); // termina una, manda la otra (el error no frena)
  }

  void _addPocket(ColabTask t, String arg) {
    setState(() {
      _pockets.add(ColabPocket(id: taskUid(), taskId: t.id, argumento: arg));
    });
    _persist();
    _maybeRunNext();
  }

  void _clearFinished() {
    setState(() {
      _pockets.removeWhere((p) => p.status == 'ok' || p.status == 'error');
    });
    _persist();
  }

  // ---------------- Diálogos ----------------

  Future<String?> _askInput(String prompt, bool password) async {
    final ctrl = TextEditingController();
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
          onSubmitted: (_) => Navigator.pop(ctx),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Enviar')),
        ],
      ),
    );
    final v = ctrl.text;
    ctrl.dispose();
    return v;
  }

  /// Preset CDN → cifrar → HF (5 args: URL, maestro, lote, token, repo).
  /// Cada toque = OTRA tarea (ids únicos) y se abre directo para
  /// rellenar. Antes: si ya había una no hacía nada en silencio.
  Future<void> _agregarPrefabCdnHf() async {
    final t = ColabPrefabs.cdnCifrarHf();
    t.id = 'prefab-cdn-hf-${taskUid()}';
    t.nombre = 'CDN → HF ${_tasks.where((x) => x.id.startsWith('prefab-cdn-hf')).length + 1}';
    setState(() => _tasks.add(t));
    await _persist();
    if (!mounted) return;
    await _enviar(t);
  }

  Future<void> _createTaskDialog() async {    final nombre = TextEditingController();
    final code = TextEditingController(text: '# Código Python...\nprint("hola", ARG if "ARG" in dir() else "")');
    bool hasArg = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Nueva tarea'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombre,
                  decoration: const InputDecoration(
                      labelText: 'Nombre (opcional)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(child: Text('Pide argumento al enviar')),
                  Switch(value: hasArg, onChanged: (v) => setD(() => hasArg = v)),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: code,
                  maxLines: null,
                  minLines: 5,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Python (si hay argumento, leelo con ARG)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _tasks.add(ColabTask(
        id: taskUid(),
        nombre: nombre.text.trim().isEmpty
            ? 'Tarea ${_tasks.length + 1}'
            : nombre.text.trim(),
        code: code.text,
        hasArg: hasArg,
      ));
    });
    await _persist();
  }

  Future<void> _editTaskDialog(ColabTask t) async {
    final nombre = TextEditingController(text: t.nombre);
    final code = TextEditingController(text: t.code);
    bool hasArg = t.hasArg;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Editar tarea'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombre,
                  decoration: const InputDecoration(
                      labelText: 'Nombre', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Expanded(child: Text('Pide argumento al enviar')),
                  Switch(value: hasArg, onChanged: (v) => setD(() => hasArg = v)),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: code,
                  maxLines: null,
                  minLines: 5,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(
                      labelText: 'Python', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  setState(() => _tasks.remove(t));
                  _persist();
                },
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                child: const Text('Borrar tarea')),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  t.nombre = nombre.text.trim();
                  t.code = code.text;
                  t.hasArg = hasArg;
                  Navigator.pop(ctx);
                },
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    await _persist();
  }

  /// Enviar: crea un pocket de la tarea. Con argumento pide el valor
  /// (con lápiz opcional para tocar el Python de la plantilla).
  Future<void> _enviar(ColabTask t) async {
    if (!_connected) {
      // Ruidoso: antes volvía en silencio y parecía que el botón
      // no hacía nada (ni abría ni guardaba).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Sin conexión al runtime: no se puede enviar')),
        );
      }
      return;
    }
    if (!t.hasArg) {
      _addPocket(t, '');
      return;
    }
    final argCtrl = TextEditingController(text: t.lastArg);
    final codeCtrl = TextEditingController(text: t.code);
    // Una caja por campo (preset): prefill con el último envío por línea.
    final ultimas = t.lastArg.split('\n');
    final campoCtrls = [
      for (var i = 0; i < t.campos.length; i++)
        TextEditingController(
            text: i < ultimas.length ? ultimas[i] : ''),
    ];
    bool showCode = false;
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Enviar "${t.nombre}"'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.campos.isNotEmpty) ...[
                  for (var i = 0; i < t.campos.length; i++) ...[
                    TextField(
                      controller: campoCtrls[i],
                      decoration: InputDecoration(
                        labelText: '${i + 1}. ${t.campos[i]}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(children: [
                    const Expanded(
                      child: Text('Valores del último envío '
                          '(tocá solo lo que cambia)')),
                    IconButton(
                      tooltip: 'Editar Python',
                      onPressed: () => setD(() => showCode = !showCode),
                      icon: Icon(showCode ? Icons.close : Icons.edit),
                    ),
                  ]),
                ] else
                  Row(children: [
                  Expanded(
                    child: TextField(
                      controller: argCtrl,
                      autofocus: t.campos.isEmpty,
                      maxLines: 6,
                      minLines: 3,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: 'Argumento (una por línea)',
                        hintText: 'URL\npass\ntoken\nrepo\n...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar Python',
                    onPressed: () => setD(() => showCode = !showCode),
                    icon: Icon(showCode ? Icons.close : Icons.edit),
                  ),
                ]),
                if (t.ayuda.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      t.ayuda,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.lightBlueAccent),
                    ),
                  ),
                ],
                if (showCode) ...[
                  const SizedBox(height: 8),
                  // Caja fija con scroll PROPIO: antes el campo crecía
                  // sin límite y el scroll del diálogo le robaba el
                  // gesto (no se podía editar el script).
                  SizedBox(
                    height: 280,
                    child: TextField(
                    controller: codeCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    scrollPhysics:
                        const AlwaysScrollableScrollPhysics(),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                        labelText: 'Python (deslizá acá adentro)',
                        border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Mandar')),
          ],
        ),
      ),
    );
    // Lo editado se guarda siempre (aunque cancele): la próxima
    // viene pre-rellenada con esto. Solo se MANDA con confirmar.
    // El "✓ guardado" sale DESPUÉS de escribir (await): antes mentía.
    final campoVals = campoCtrls.map((c) => c.text.trim()).toList();
    if (t.campos.isNotEmpty) {
      t.lastArg = campoVals.join('\n');
      await _persist();
      // Prueba visible en el celu: si esto sale, quedó en config.pr.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '✓ "${t.nombre}" guardado (${campoVals.where((v) => v.isNotEmpty).length}/${campoVals.length} campos)')),
        );
      }
    }
    if (sent != true || !mounted) {
      for (final c in campoCtrls) {
        c.dispose();
      }
      return;
    }
    // Une las cajas (o el campo único) y confirma antes de mandar.
    final argFinal = t.campos.isNotEmpty
        ? campoVals.join('\n')
        : argCtrl.text;
    for (final c in campoCtrls) {
      c.dispose();
    }
    if (t.campos.isNotEmpty) {
      final ok2 = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Mandar así?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < t.campos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${i + 1}. ${t.campos[i]}:\n'
                    '${campoVals[i].isEmpty ? '—' : campoVals[i]}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Atrás')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mandar')),
          ],
        ),
      );
      if (ok2 != true || !mounted) return;
    }
    t.lastArg = argFinal;
    if (codeCtrl.text != t.code) t.code = codeCtrl.text;
    await _persist();
    _addPocket(t, t.lastArg);
  }

  void _duplicateTask(ColabTask t) {
    setState(() {
      _tasks.add(ColabTask(
        id: taskUid(),
        nombre: '${t.nombre} (copia)',
        code: t.code,
        hasArg: t.hasArg,
        lastArg: t.lastArg,
        ayuda: t.ayuda,
        campos: List.of(t.campos),
      ));
    });
    _persist();
  }

  void _rerunPocket(ColabPocket p) {
    if (_running) return;
    setState(() => p.status = 'pendiente');
    _persist();
    _maybeRunNext();
  }

  void _deletePocket(ColabPocket p) {
    if (p.status == 'running') return;
    setState(() => _pockets.remove(p));
    _persist();
  }

  Future<void> _pocketDetail(ColabPocket p) async {
    final task = _taskById(p.taskId);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(task?.nombre ?? 'Tarea borrada'),
        content: SizedBox(
          width: 440,
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${task?.hasArg == true ? "ARG" : "sin arg"}: '
                  '${p.argumento.isEmpty && task?.hasArg != true ? "-" : p.argumento}'),
              const SizedBox(height: 6),
              const Text('Código Python:',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      task?.code ?? '(borrada)',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text('Resultado:',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(
                        color: p.status == 'error'
                            ? Colors.redAccent.withValues(alpha: .4)
                            : Colors.greenAccent.withValues(alpha: .25)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      p.output.isEmpty ? '(sin salida)' : p.output,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: p.status == 'error'
                              ? Colors.redAccent[100]
                              : Colors.greenAccent[100]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              _copyTxt(ctx, p.output);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePocket(p);
            },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Borrar'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _rerunPocket(p);
            },
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Ejecutar'),
          ),
        ],
      ),
    );
  }

  // ---------------- UI ----------------

  Widget _statusIcon(String status) {
    switch (status) {
      case 'pendiente':
        return const Icon(Icons.schedule, size: 20, color: Colors.grey);
      case 'running':
        return const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2));
      case 'ok':
        return const Icon(Icons.check_circle, size: 20, color: Colors.greenAccent);
      default:
        return const Icon(Icons.error, size: 20, color: Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Tareas Colab ${_connected ? "●" : "○"}'),
          bottom: TabBar(tabs: const [
            Tab(text: 'Tareas'),
            Tab(child: Text('Pockets (cola)')),
          ]),
          actions: [
            if (_running)
              IconButton(
                tooltip: 'Frenar pocket actual',
                onPressed: () => _runtime.interruptCurrent(),
                icon: const Icon(Icons.stop, color: Colors.redAccent),
              ),
            IconButton(
              tooltip: 'Borrar terminados',
              onPressed: _pockets.isEmpty ? null : _clearFinished,
              icon: const Icon(Icons.cleaning_services, size: 20),
            ),
            IconButton(
              tooltip: 'Preset CDN → cifrar → HF',
              onPressed: _agregarPrefabCdnHf,
              icon: const Icon(Icons.auto_awesome, size: 20),
            ),
            IconButton(
              tooltip: 'Nueva tarea',
              onPressed: _createTaskDialog,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                Icon(_connected ? Icons.check_circle : Icons.error,
                    size: 13,
                    color:
                        _connected ? Colors.greenAccent : Colors.redAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_connStatus,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                if (!_connected && !_connecting)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Reintentar',
                    onPressed: _connect,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
              ]),
            ),
            Expanded(
              child: TabBarView(children: [
                _buildTasksTab(),
                _buildPocketsTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksTab() {
    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.playlist_add, size: 44, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('Sin tareas.\nTocá + para crear una plantilla Python.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _createTaskDialog,
              icon: const Icon(Icons.add),
              label: const Text('Crear tarea'),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _tasks.length,
      itemBuilder: (context, i) {
        final t = _tasks[i];
        final preview =
            t.code.trim().split('\n').take(2).join(' ⏎ ');
        return Card(
          color: const Color(0xFF0B1220),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text(t.nombre,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${t.hasArg ? "con argumento" : "sin argumento"} · $preview',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Editar',
                onPressed: () => _editTaskDialog(t),
                icon: const Icon(Icons.edit, size: 18),
              ),
              IconButton(
                tooltip: 'Duplicar',
                onPressed: () => _duplicateTask(t),
                icon: const Icon(Icons.copy, size: 18),
              ),
              IconButton(
                tooltip: 'Enviar',
                onPressed: _connected ? () => _enviar(t) : null,
                icon:
                    const Icon(Icons.send, size: 18, color: Colors.blueAccent),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _buildPocketsTab() {
    if (_pockets.isEmpty) {
      return const Center(
        child: Text('Sin pockets.\nEnviá una tarea desde la pestaña Tareas.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pockets.length,
      itemBuilder: (context, i) {
        final p = _pockets[i];
        final task = _taskById(p.taskId);
        return Card(
          color: const Color(0xFF0B1220),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _statusIcon(p.status),
            title: Text(
              '${task?.nombre ?? "(tarea borrada)"}'
              '${task?.hasArg == true ? " · ${p.argumento}" : ""}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              p.output.isEmpty ? p.status : p.output,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            onTap: () => _pocketDetail(p),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Re-ejecutar',
                onPressed: p.status == 'running' ? null : () => _rerunPocket(p),
                icon: const Icon(Icons.play_arrow,
                    size: 18, color: Colors.greenAccent),
              ),
              IconButton(
                tooltip: 'Borrar pocket',
                onPressed: p.status == 'running' ? null : () => _deletePocket(p),
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.redAccent),
              ),
            ]),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _runtime.close();
    super.dispose();
  }
}
