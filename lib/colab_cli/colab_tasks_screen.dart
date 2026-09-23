import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colab_prefabs.dart';
import 'colab_runtime.dart';
import 'colab_tareas_sql.dart';
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
    _connect();
    // Tareas desde su SQL con pass (pide al abrir). Nada del config.pr.
    WidgetsBinding.instance.addPostFrameCallback((_) => _abrirStore());
  }

  /// Abre la SQL de tareas (pide pass si falta) y vuelca a pantalla.
  /// SOLO SQL: del config.pr no se lee nada.
  Future<void> _abrirStore() async {
    final r = await ColabTareasSql.cargar(context);
    if (!mounted) return;
    if (r == null) {
      setState(() {
        _tasks = [];
        _pockets = [];
      });
      return;
    }
    final tasks = r.tasks;
    final pockets = r.pockets;
    setState(() {
      _tasks = tasks;
      // Pockets que quedaron 'running' de una sesión anterior vuelven a la cola.
      _pockets = pockets;
      for (final p in _pockets) {
        if (p.status == 'running') p.status = 'pendiente';
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtime.close();
    super.dispose();
  }

  /// La app se va a fondo / se cierra: guardar YA en la SQL (sin
  /// pedir pass en fondo: si no hay pass en memoria, se omite; en
  /// memoria no se pierde nada y el próximo Guardar lo escribe).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!mounted) return;
      ColabTareasSql.guardar(context, _tasks, _pockets, silencioso: true);
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

  /// Guarda en la SQL de tareas (pide pass si falta, con await: el
  /// "✓ guardado" sale DESPUÉS de escribir).
  /// [silencioso]: fondo (cola) → sin pass NO pide, retorna sin
  /// escribir (en memoria sigue todo; el próximo Guardar lo baja).
  Future<void> _persist({bool silencioso = false}) async {
    if (!mounted) return;
    await ColabTareasSql.guardar(context, _tasks, _pockets,
        silencioso: silencioso);
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
    await _persist(silencioso: true);
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

  /// ¿Es slot CDN? Por FIRMA (5 campos), no por id: las copias y
  /// las viejas pierden el prefijo y el picker las ignoraba.
  bool _esSlotCdn(ColabTask t) =>
      t.id.startsWith('prefab-cdn-hf') ||
      (t.hasArg && t.campos.length == 5);

  /// Resumen para el picker CDN: "3/5 campos · primera línea…".
  String _resumenArg(ColabTask m) {
    final ls =
        m.lastArg.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (ls.isEmpty) return 'vacía';
    final primero = ls.first.trim();
    final corto =
        primero.length > 40 ? '${primero.substring(0, 40)}…' : primero;
    return '${ls.length}/${m.campos.length} campos · $corto';
  }

  /// Preset CDN → cifrar → HF (5 args: URL, maestro, lote, token, repo).
  /// Con guardadas pregunta CUÁL abrir (o crear nueva). Nada es
  /// automático: abrir no guarda, solo Guardar/Mandar escriben.
  Future<void> _agregarPrefabCdnHf() async {
    // Tocar CDN pide la pass (si falta) y trae lo guardado si la
    // pantalla arrancó vacía (canceló al abrir).
    await ColabTareasSql.asegurar(context);
    if (!mounted) return;
    if (_tasks.isEmpty) {
      final r = await ColabTareasSql.cargar(context);
      if (!mounted) return;
      if (r != null && (r.tasks.isNotEmpty || r.pockets.isNotEmpty)) {
        setState(() {
          _tasks = r.tasks;
          _pockets = r.pockets;
        });
      }
    }
    final mias = [
      for (var i = _tasks.length - 1; i >= 0; i--)
        if (_esSlotCdn(_tasks[i])) _tasks[i]
    ];
    if (mias.isNotEmpty) {
      // dynamic: ColabTask = abrirla, 'nueva' = crear, null = cancelar.
      final elegido = await showDialog<dynamic>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CDN → HF: ¿cuál?'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in mias)
                  ListTile(
                    dense: true,
                    title: Text(m.nombre),
                    subtitle: Text(
                      _resumenArg(m),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    onTap: () => Navigator.pop(ctx, m),
                  ),
                const Divider(),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add),
                  title: const Text('Nueva (vacía)'),
                  onTap: () => Navigator.pop(ctx, 'nueva'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
          ],
        ),
      );
      if (!mounted) return;
      if (elegido is ColabTask) {
        await _enviar(elegido);
        return;
      }
      // Cancelar (null) = no hacer nada. Solo 'nueva' sigue a crear.
      if (elegido != 'nueva') return;
    }
    final t = ColabPrefabs.cdnCifrarHf();
    t.id = 'prefab-cdn-hf-${taskUid()}';
    t.nombre = 'CDN → HF ${_tasks.where(_esSlotCdn).length + 1}';
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
  /// Los SLOTS se abren SIEMPRE (rellenar/guardar no necesita
  /// conexión); solo MANDAR exige runtime conectado.
  Future<void> _enviar(ColabTask t) async {
    if (!t.hasArg) {
      if (!_connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Sin conexión al runtime: no se puede enviar')),
          );
        }
        return;
      }
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
    // 'mandar' | 'guardar' | null: NADA es automático (cancelar
    // descarta sin tocar lo guardado; Guardar/Mandar son explícitos).
    final sent = await showDialog<String>(
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'guardar'),
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Guardar')),
            FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'mandar'),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Mandar')),
          ],
        ),
      ),
    );
    // NADA es automático: Cancelar descarta sin tocar lastArg ni
    // disco. Guardar/Mandar aplican lo escrito (con await: el cartel
    // sale DESPUÉS de escribir). Vacíos JAMÁS pisan data previa.
    void descartar() {
      for (final c in campoCtrls) {
        c.dispose();
      }
      argCtrl.dispose();
      codeCtrl.dispose();
    }

    final campoVals = campoCtrls.map((c) => c.text.trim()).toList();
    if (sent != 'mandar' && sent != 'guardar') {
      descartar();
      return;
    }
    if (codeCtrl.text != t.code) t.code = codeCtrl.text;
    final nuevoArg =
        t.campos.isNotEmpty ? campoVals.join('\n') : argCtrl.text;
    final todoVacio = t.campos.isNotEmpty
        ? campoVals.every((v) => v.isEmpty)
        : nuevoArg.trim().isEmpty;
    if (!todoVacio || t.lastArg.trim().isEmpty) {
      t.lastArg = nuevoArg;
      await _persist();
      // Prueba visible en el celu: si esto sale, quedó en la SQL.
      if (mounted) {
        final n = t.campos.isNotEmpty
            ? ' (${campoVals.where((v) => v.isNotEmpty).length}/${campoVals.length} campos)'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ "${t.nombre}" guardado$n')),
        );
      }
    } else if (mounted) {
      // Vacíos + había data: no se pisa, se mantiene el envío.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('↩ "${t.nombre}": se mantiene el último envío')),
      );
    }
    if (sent == 'guardar' || !mounted) {
      descartar();
      return;
    }
    // sent == 'mandar': slots listos pero sin runtime → no se manda.
    if (!_connected) {
      descartar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Sin conexión: valores guardados, no mandados')),
        );
      }
      return;
    }
    // Une las cajas (o el campo único) y confirma antes de mandar.
    // (lastArg ya trae lo guardado explícito de arriba.)
    // Mandar pregunta UNA sola vez (el diálogo de slots ya es la
    // confirmación): sin segundo "¿Mandar así?".
    for (final c in campoCtrls) {
      c.dispose();
    }
    // lastArg ya quedó guardado arriba (Guardar/Mandar explícitos);
    // acá solo se manda. Sin doble persist.
    if (!mounted) {
      descartar();
      return;
    }
    final aMandar = t.lastArg;
    descartar();
    _addPocket(t, aMandar);
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
            IconButton(
              tooltip: 'Olvidar pass de tareas (candado)',
              onPressed: () {
                ColabTareasSql.olvidar();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Pass olvidada: lo próximo la pide de nuevo')),
                  );
                }
              },
              icon: const Icon(Icons.lock_outline, size: 20),
            ),
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
        // Con campos (slots): el subtítulo muestra los VALORES
        // guardados, no el código (el slot se ve en la lista).
        final preview = t.campos.isNotEmpty
            ? _resumenArg(t)
            : t.code.trim().split('\n').take(2).join(' ⏎ ');
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
                onPressed: () => _enviar(t),
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
}
