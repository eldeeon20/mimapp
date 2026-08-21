import 'package:flutter/material.dart';

import 'colab_auth.dart';
import 'colab_keep_alive.dart';
import 'colab_sessions.dart';

/// Diálogo de gestión de Colab: autenticación (copy-paste), sesiones, keep-alive.
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
  String? _info;
  List<ColabSession> _sessions = [];
  bool _waitingCode = false;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.auth.isAuthenticated) {
      _loadSessions();
    }
  }

  String? _authUrl;

  Future<void> _startLogin() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
      _waitingCode = false;
      _authUrl = null;
    });
    try {
      await widget.auth.openBrowser();
      setState(() {
        _waitingCode = true;
        _loading = false;
        _info = 'Copiá el código de la página de Google y pegalo acá abajo';
      });
    } catch (e) {
      setState(() {
        _authUrl = widget.auth.buildAuthUrl();
        _error = 'No se pudo abrir el navegador. Tocá la URL de abajo para copiarla.';
        _waitingCode = true;
        _loading = false;
      });
    }
  }

  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.auth.exchangeCode(code);
      _codeCtrl.clear();
      setState(() => _waitingCode = false);
      await _loadSessions();
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      _sessions = await widget.sessions.list();
    } catch (e) {
      setState(() => _error = 'Error cargando sesiones: $e');
    }
    if (mounted) setState(() => _loading = false);
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
            if (!widget.auth.isAuthenticated && !_waitingCode) ...[
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No autenticado con Google Colab'),
              const SizedBox(height: 8),
              const Text(
                'Se abrirá el navegador de Google. Copiá el código de\n'
                'autorización y pegalo acá.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
            if (_waitingCode) ...[
              const Icon(Icons.content_paste, size: 48, color: Colors.amber),
              const SizedBox(height: 12),
              if (_info != null)
                Text(_info!,
                    style: const TextStyle(fontSize: 12, color: Colors.blue)),
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Código de autorización',
                  hintText: '4/0A... pegalo acá',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submitCode(),
              ),
            ],
            if (widget.auth.isAuthenticated && !_waitingCode) ...[
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
                ],
              ),
              if (_sessions.isEmpty && !_loading)
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
                      Expanded(
                          child: Text(
                              'Keep-alive: ${widget.keepAlive.currentEndpoint} '
                              '(${widget.keepAlive.elapsed.inMinutes} min)')),
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
            if (_loading) ...[
              const SizedBox(height: 12),
              const CircularProgressIndicator(),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        if (_waitingCode)
          FilledButton(
            onPressed: _loading || _codeCtrl.text.trim().isEmpty
                ? null
                : _submitCode,
            child: const Text('Canjear código'),
          ),
        if (!widget.auth.isAuthenticated && !_waitingCode)
          FilledButton(
            onPressed: _loading ? null : _startLogin,
            child: const Text('Iniciar sesión'),
          ),
      ],
    );
  }
}
