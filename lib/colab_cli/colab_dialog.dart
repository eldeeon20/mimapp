import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colab_auth.dart';
import 'colab_cells_screen.dart';
import 'colab_config.dart';
import 'colab_keep_alive.dart';
import 'colab_sessions.dart';
import 'colab_tasks_screen.dart';
import '../services/colab_service.dart';
import '../services/nativo.dart';
import '../services/settings.dart';
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

  /// Repinta el log del ping cada 5s mientras el diálogo siga abierto.
  Timer? _relojLog;

  @override
  void initState() {
    super.initState();
    if (widget.auth.isAuthenticated) {
      _loadSessions();
    }
    _relojLog = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) return;
      try {
        await ColabService().refrescarEspejo();
      } catch (_) {}
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    try {
      _relojLog?.cancel();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _startLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.signInInteractive();
      if (!mounted) return;
      setState(() {});
      await _loadSessions();
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSessions() async {
    if (mounted) setState(() => _loading = true);
    try {
      _sessions = await widget.sessions.list();
      ColabService().activeSessionCount = _sessions.length;
      StatusNotifier.instance.refresh();
      // Listar no arranca nada (así está bien): el auto-inicio es solo
      // al CREAR la celda (ver _createSession).
      // Servicio muerto = celda que se quita sola: si el nativo murió
      // pineando un endpoint que sigue listado, se desasigna solo.
      try {
        await ColabService().refrescarEspejo();
        final muerto = ColabService().espejoUltimoEndpoint;
        if (!ColabService().pingActivo &&
            muerto.isNotEmpty &&
            _sessions.any((s) => s.endpoint == muerto)) {
          await widget.sessions.unassign(muerto);
          _sessions = await widget.sessions.list();
          ColabService().activeSessionCount = _sessions.length;
          if (mounted) {
            setState(() {
              _error = 'Celda muerta (${ColabService().espejoError}): '
                  'se quitó sola. Solo queda la X del servicio.';
            });
          }
        }
      } catch (_) {}
    } catch (e) {
      if (mounted) setState(() => _error = 'Error cargando sesiones: $e');
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
      final antes = _sessions.map((s) => s.endpoint).toSet();
      await widget.sessions.assign(accel: choice);
      await _loadSessions();
      // AUTO-INICIO: la celda nueva entra en ping sola (servicio nativo).
      // Si ya había algo pineando no se roba: solo si no hay ping activo.
      if (!ColabService().pingActivo) {
        final nuevas = _sessions.where((s) => !antes.contains(s.endpoint));
        final primera = nuevas.isNotEmpty ? nuevas.first : null;
        final destino = primera ??
            (_sessions.isNotEmpty ? _sessions.first : null);
        if (destino != null) {
          try {
            await ColabService().startKeepAlive(destino.endpoint);
          } catch (e) {
            _error = 'Celda creada pero el ping no arrancó: $e';
          }
        }
      }
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

  /// Editor manual de llaves OAuth (Client ID + Client Secret propios).
  /// Vacío = usar las embebidas. Se guardan cifradas en Settings.
  Future<void> _showKeysDialog() async {
    final idCtrl =
        TextEditingController(text: ColabConfig.customClientId);
    final secCtrl =
        TextEditingController(text: ColabConfig.customClientSecret);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Llaves de Colab'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Client ID y Client Secret de tu proyecto de Google Cloud '
                '(credenciales OAuth). Dejá vacío para usar las embebidas.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  labelText: 'Client ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: secCtrl,
                decoration: const InputDecoration(
                  labelText: 'Client Secret',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Settings.instance.colabClientId = '';
              Settings.instance.colabClientSecret = '';
              await Settings.instance.save();
              if (dctx.mounted) Navigator.pop(dctx, true);
            },
            child: const Text('Restablecer'),
          ),
          FilledButton(
            onPressed: () async {
              Settings.instance.colabClientId = idCtrl.text.trim();
              Settings.instance.colabClientSecret = secCtrl.text.trim();
              await Settings.instance.save();
              if (dctx.mounted) Navigator.pop(dctx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    idCtrl.dispose();
    secCtrl.dispose();
    if (saved == true && mounted) setState(() {});
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
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _loading ? null : _showKeysDialog,
                icon: const Icon(Icons.key, size: 18),
                label: Text(
                  ColabConfig.usingCustomKeys
                      ? 'Llaves: manuales (+)'
                      : 'Llaves: embebidas (+)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
            if (widget.auth.isAuthenticated) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Autenticado')),
                  IconButton(
                    onPressed: _loading ? null : _showKeysDialog,
                    tooltip: ColabConfig.usingCustomKeys
                        ? 'Llaves manuales (+)'
                        : 'Llaves embebidas (+)',
                    icon: const Icon(Icons.key, size: 20),
                  ),
                  TextButton(
                    onPressed: () async {
                      await widget.auth.logout();
                      if (mounted) setState(() {});
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
                          if (ColabService().pingActivo &&
                              ColabService().activeEndpoint == s.endpoint)
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
                                case 'unassign':
                                  if (mounted) {
                                    setState(() => _loading = true);
                                  }
                                  try {
                                    await widget.sessions.unassign(s.endpoint);
                                    // Soltada: se frena TODO el ping (Dart +
                                    // nativo). Soltar = quitar ping.
                                    final svc = ColabService();
                                    if (svc.activeEndpoint == s.endpoint) {
                                      try {
                                        svc.pingDart.stop();
                                      } catch (_) {}
                                      try {
                                        await Nativo.stopPing();
                                      } catch (_) {}
                                      svc.activeEndpoint = null;
                                      svc.espejoDart = '';
                                    }
                                    await _loadSessions();
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() {
                                        _error = 'Error soltando: $e';
                                        _loading = false;
                                      });
                                    }
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
              if (!ColabService().pingActivo &&
                  ColabService().espejoError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(ColabService().espejoError,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey))),
                    ],
                  ),
                ),
              if (ColabService().pingActivo)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.timer, size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              'Ping cada 60s: ${ColabService().activeEndpoint} '
                              '(${ColabKeepAlive.fmtDur(ColabService().espejoElapsed)} · '
                              '${ColabService().espejoPings} pings)'
                              '${ColabService().espejoUltimoPing.isNotEmpty ? '\nlog: ${ColabService().espejoUltimoPing}' : ''}'
                              '${ColabService().espejoDart.isNotEmpty ? '\n${ColabService().espejoDart}' : ''}'
                              '${ColabService().pingLog.isNotEmpty ? '\nlog:\n${ColabService().pingLog.reversed.take(8).join('\n')}' : ''}',
                              style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                ),
              // COMENTADO: autodetect desactivado, el ping es solo manual
              // (botón Keep-alive de cada celda). Se deja sin borrar.
              // Row(children: [
              //   Switch(
              //       value: ColabService().autoDetect,
              //       onChanged: (v) {
              //         ColabService().autoDetect = v;
              //         setState(() {});
              //       }),
              //   const Expanded(
              //       child: Text(
              //           'Autodetectar celdas nuevas y mantenerlas vivas (avisa al enganchar/desconectar)',
              //           style: TextStyle(fontSize: 11, color: Colors.grey))),
              // ]),
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
