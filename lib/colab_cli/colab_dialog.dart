import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colab_auth.dart';
import 'colab_cells_screen.dart';
import 'colab_keep_alive.dart';
import 'colab_sessions.dart';
import 'colab_tasks_screen.dart';
import '../services/colab_service.dart';
import '../services/status_notifier.dart';

/// Diálogo de gestión de Colab: autenticación (loopback), sesiones, keep-alive.
/// El keep-alive vive en [ColabService] (singleton), por eso NO se detiene
/// al cerrar este diálogo: sigue corriendo en segundo plano.
Future<void> showColabDialog(BuildContext context) async {
  final auth = ColabAuth();
  final sessions = ColabSessions(auth);

  await auth.loadTokens();

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => _ColabDialogBody(
      auth: auth,
      sessions: sessions,
    ),
  );
}

class _ColabDialogBody extends StatefulWidget {
  final ColabAuth auth;
  final ColabSessions sessions;

  const _ColabDialogBody({
    required this.auth,
    required this.sessions,
  });

  @override
  State<_ColabDialogBody> createState() => _ColabDialogBodyState();
}

class _ColabDialogBodyState extends State<_ColabDialogBody> {
  bool _loading = false;
  String? _error;
  List<ColabSession> _sessions = [];

  @override
  void initState() {
    super.initState();
    if (widget.auth.isAuthenticated) {
      _loadSessions();
    }
  }

  Future<void> _startLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.signInInteractive();
      setState(() {});
      await _loadSessions();
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      _sessions = await widget.sessions.list();
      ColabService().activeSessionCount = _sessions.length;
      StatusNotifier.instance.refresh();
    } catch (e) {
      setState(() => _error = 'Error cargando sesiones: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createSession() async {
    // Elegir acelerador antes de asignar.
    if (!mounted) return;
    final choice = await showModalBottomSheet<ColabAccelerator>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Elegí el runtime',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...ColabAccelerator.values.map((a) => ListTile(
                  leading: Icon(
                    a == ColabAccelerator.cpu
                        ? Icons.memory
                        : a == ColabAccelerator.tpu
                            ? Icons.grid_view
                            : Icons.bolt,
                    color: a == ColabAccelerator.cpu
                        ? Colors.grey
                        : Colors.amber,
                  ),
                  title: Text(a.label),
                  subtitle: a == ColabAccelerator.cpu
                      ? const Text('Gratis, siempre disponible',
                          style: TextStyle(fontSize: 11))
                      : a == ColabAccelerator.a100
                          ? const Text('Requiere Pro+',
                              style: TextStyle(fontSize: 11))
                          : null,
                  onTap: () => Navigator.pop(sheetCtx, a),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.sessions.assign(accel: choice);
      await _loadSessions();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error creando sesión: $e';
          _loading = false;
        });
      }
    }
  }

  void _openPython(ColabSession s) {
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.pop(context);
    nav.push(MaterialPageRoute(
      builder: (_) => ColabCellsScreen(
        serverUrl: s.proxyUrl,
        proxyToken: s.proxyToken,
      ),
    ));
  }

  void _openTasks(ColabSession s) {
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.pop(context);
    nav.push(MaterialPageRoute(
      builder: (_) => ColabTasksScreen(
        serverUrl: s.proxyUrl,
        proxyToken: s.proxyToken,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Google Colab'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.auth.isAuthenticated) ...[
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No autenticado con Google Colab'),
              const SizedBox(height: 8),
              const Text(
                'Se abrirá el navegador de Google para iniciar sesión.\n'
                'El código se captura solo, no tenés que copiar nada.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
            if (widget.auth.isAuthenticated) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Autenticado')),
                  TextButton(
                    onPressed: () async {
                      await widget.auth.logout();
                      setState(() {});
                    },
                    child: const Text('Salir'),
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  Text('Sesiones: ${_sessions.length}'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loading ? null : _loadSessions,
                    tooltip: 'Recargar',
                  ),
                  FilledButton.icon(
                    onPressed: _loading ? null : _createSession,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Crear',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              if (_sessions.isEmpty && !_loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No hay sesiones activas.\n'
                      'Tocá "Crear" para iniciar un runtime.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              ..._sessions.map((s) => Card(
                    color: const Color(0xFF0B1220),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        s.accelerator == 'NONE'
                            ? Icons.memory
                            : Icons.bolt,
                        color: s.accelerator == 'NONE'
                            ? Colors.grey
                            : Colors.amber,
                        size: 22,
                      ),
                      title: Text(s.endpoint,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${s.variant} · ${s.machineShape == 1 ? "High-RAM" : "Std"}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ColabService().keepAlive.isRunning &&
                              ColabService().keepAlive.currentEndpoint == s.endpoint)
                            const Icon(Icons.timer,
                                size: 16, color: Colors.blue),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              switch (v) {
                                case 'python':
                                  _openPython(s);
                                  break;
                                case 'tareas':
                                  _openTasks(s);
                                  break;
                                case 'keepalive':
                                  ColabService().startKeepAlive(s.endpoint);
                                  StatusNotifier.instance.refresh();
                                  setState(() {});
                                  break;
                                case 'unassign':
                                  setState(() => _loading = true);
                                  try {
                                    await widget.sessions.unassign(s.endpoint);
                                    await _loadSessions();
                                  } catch (e) {
                                    setState(() {
                                      _error = 'Error soltando: $e';
                                      _loading = false;
                                    });
                                  }
                                  break;
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'python',
                                  child: Row(children: [
                                    Icon(Icons.terminal, size: 18),
                                    SizedBox(width: 8),
                                    Text('Python'),
                                  ])),
                              PopupMenuItem(
                                  value: 'tareas',
                                  child: Row(children: [
                                    Icon(Icons.playlist_add, size: 18),
                                    SizedBox(width: 8),
                                    Text('Tareas'),
                                  ])),
                              PopupMenuItem(
                                  value: 'keepalive',
                                  child: Row(children: [
                                    Icon(Icons.timer, size: 18),
                                    SizedBox(width: 8),
                                    Text('Keep-alive'),
                                  ])),
                              PopupMenuItem(
                                  value: 'unassign',
                                  child: Row(children: [
                                    Icon(Icons.link_off,
                                        size: 18, color: Colors.redAccent),
                                    SizedBox(width: 8),
                                    Text('Soltar'),
                                  ])),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
              if (ColabService().keepAlive.isRunning)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.timer, size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              'Keep-alive: ${ColabService().keepAlive.currentEndpoint} '
                              '(${ColabService().keepAlive.elapsed.inMinutes} min)')),
                      TextButton(
                        onPressed: () {
                          ColabService().stopKeepAlive();
                          StatusNotifier.instance.refresh();
                          setState(() {});
                        },
                        child: const Text('Detener'),
                      ),
                    ],
                  ),
                ),
            ],
            if (_loading) ...[
              const SizedBox(height: 12),
              const CircularProgressIndicator(),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copiar error',
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _error!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Copiado'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (!widget.auth.isAuthenticated)
          FilledButton(
            onPressed: _loading ? null : _startLogin,
            child: const Text('Iniciar sesión'),
          ),
      ],
    );
  }
}
