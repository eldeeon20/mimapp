import 'package:flutter/material.dart';

import 'colab_auth.dart';
import 'colab_keep_alive.dart';
import 'colab_sessions.dart';

/// Diálogo de gestión de Colab: autenticación, sesiones, keep-alive.
Future<void> showColabDialog(BuildContext context) async {
  final auth = ColabAuth();
  final keepAlive = ColabKeepAlive(auth);
  final sessions = ColabSessions(auth);

  await auth.loadTokens();

  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => _ColabDialogBody(
      auth: auth,
      keepAlive: keepAlive,
      sessions: sessions,
    ),
  );

  keepAlive.stop();
}

class _ColabDialogBody extends StatefulWidget {
  final ColabAuth auth;
  final ColabKeepAlive keepAlive;
  final ColabSessions sessions;

  const _ColabDialogBody({
    required this.auth,
    required this.keepAlive,
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

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.authenticate();
      await _loadSessions();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSessions() async {
    try {
      _sessions = await widget.sessions.list();
    } catch (e) {
      setState(() => _error = 'Error cargando sesiones: $e');
    }
    if (mounted) setState(() {});
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
              const SizedBox(height: 16),
              if (_loading) const CircularProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ] else ...[
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
                  const Text('Sesiones activas: ${0}'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loading ? null : _loadSessions,
                    tooltip: 'Recargar sesiones',
                  ),
                ],
              ),
              if (_sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No hay sesiones activas',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              if (widget.keepAlive.isRunning)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.timer, size: 16, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text(
                          'Keep-alive: ${widget.keepAlive.currentEndpoint} '
                          '(${widget.keepAlive.elapsed.inMinutes} min)'),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          widget.keepAlive.stop();
                          setState(() {});
                        },
                        child: const Text('Detener'),
                      ),
                    ],
                  ),
                ),
            ],
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
            onPressed: _loading ? null : _login,
            child: const Text('Iniciar sesión'),
          ),
      ],
    );
  }
}
