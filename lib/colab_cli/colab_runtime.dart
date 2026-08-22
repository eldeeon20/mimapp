import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Resultado de ejecutar código Python en el kernel.
class ColabExecResult {
  final StringBuffer stdoutBuf = StringBuffer();
  final StringBuffer stderrBuf = StringBuffer();
  final List<String> results = [];
  final StringBuffer errorBuf = StringBuffer();
  String status = 'ok'; // ok | error | timeout

  String get output => [
        if (stdoutBuf.isNotEmpty) stdoutBuf.toString(),
        if (results.isNotEmpty) results.join('\n'),
        if (stderrBuf.isNotEmpty) stderrBuf.toString(),
        if (errorBuf.isNotEmpty) errorBuf.toString(),
      ].join('\n').trim();

  bool get isError => status != 'ok';
}

/// Cliente mínimo del kernel Jupyter de Colab sobre el proxy del runtime.
///
/// Flujo (igual que google-colab-cli / jupyter_kernel_client):
///   1. POST {serverUrl}/api/sessions          → crea kernel python3
///   2. WS   {serverUrl}/api/channels           → canal único multiplexado
///   3. execute_request → recolecta iopub hasta idle/reply
class ColabRuntime {
  /// URL del proxy del runtime (runtimeProxyInfo.url del assignment).
  final String serverUrl;

  /// Token del proxy (runtimeProxyInfo.token).
  final String proxyToken;

  WebSocketChannel? _channel;
  String? _kernelId;
  final String _sessionId = _uuid();
  bool _started = false;

  ColabRuntime({required this.serverUrl, required this.proxyToken});

  bool get started => _started;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Colab-Client-Agent': 'pr_app',
        'X-Colab-Runtime-Proxy-Token': proxyToken,
      };

  /// Crea el kernel y abre el WebSocket.
  ///
  /// Igual que jupyter_kernel_client (Google):
  ///   1. POST /api/kernels {'name': 'python3'}  → {id}
  ///   2. WS   /api/kernels/{id}/channels?session_id=..&token=..
  ///      con headers extra del proxy.
  Future<void> start() async {
    if (_started) return;

    final resp = await http.post(
      Uri.parse('$serverUrl/api/kernels'),
      headers: {..._headers, 'Authorization': 'Bearer $proxyToken'},
      body: jsonEncode({
        'name': 'python3',
        'path': '',
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      var body = resp.body.replaceAll(RegExp(r'<[^>]*>'), ' ');
      body = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      throw Exception(
          'Error creando kernel (${resp.statusCode}): '
          '${body.length > 150 ? '${body.substring(0, 150)}…' : body}');
    }
    final data = jsonDecode(resp.body);
    _kernelId = data['id'] as String?;
    if (_kernelId == null || _kernelId!.isEmpty) {
      throw Exception('Respuesta sin kernel id: ${resp.body.substring(0, 120)}');
    }

    // Canal único multiplexado POR KERNEL (no /api/channels).
    final base = serverUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    final wsUri = Uri.parse(
      '$base/api/kernels/$_kernelId/channels',
    ).replace(queryParameters: {
      'session_id': _sessionId,
      'token': proxyToken,
    });
    _channel = IOWebSocketChannel.connect(
      wsUri,
      headers: {..._headers, 'Authorization': 'Bearer $proxyToken'},
      pingInterval: const Duration(seconds: 30),
    );
    await _channel!.ready;
    _started = true;
  }

  /// Ejecuta código y espera la salida completa.
  Future<ColabExecResult> execute(
    String code, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (!_started || _channel == null) {
      await start();
    }
    final result = ColabExecResult();
    final msgId = _uuid();
    _send('execute_request', {
      'code': code,
      'silent': false,
      'store_history': true,
      'user_expressions': {},
      'allow_stdin': false,
      'stop_on_error': true,
    }, msgId: msgId);

    final completer = Completer<void>();
    late final StreamSubscription sub;
    sub = _channel!.stream.listen((raw) {
      try {
        final msg = (jsonDecode(raw as String) as List).toList();
        final header = (msg[0] as Map).cast<String, dynamic>();
        final content =
            msg.length > 3 && msg[3] is Map ? (msg[3] as Map).cast<String, dynamic>() : <String, dynamic>{};
        final type = header['msg_type'];

        // Solo mensajes hijos de NUESTRA ejecución (o globales).
        final parent = header['parent_header'];
        final ours = parent is Map &&
            (parent as Map)['msg_id'] == msgId;

        switch (type) {
          case 'stream':
            result.stdoutBuf.write('${content['text']}');
            break;
          case 'execute_result':
          case 'display_data':
            final dataMap = (content['data'] ?? {}).cast<String, dynamic>();
            final text = dataMap['text/plain'];
            if (text is String && ours) result.results.add(text);
            break;
          case 'error':
            final tb = content['traceback'];
            if (tb is List) result.errorBuf.writeln(tb.join('\n'));
            result.status = 'error';
            break;
          case 'status':
            if (content['execution_state'] == 'idle') {
              if (!ours) break;
              if (!completer.isCompleted) completer.complete();
              unawaited(sub.cancel());
            }
            break;
          case 'execute_reply':
            if (!ours) break;
            final st = content['status'];
            if (st == 'error' || st == 'abort') result.status = 'error';
            if (!completer.isCompleted) completer.complete();
            unawaited(sub.cancel());
            break;
          case 'error_output':
            result.stderrBuf.write('${content['text']}');
            break;
        }
      } catch (_) {
        // Mensaje no parseable: ignorar.
      }
    }, onError: (Object e) {
      result.errorBuf.writeln('WS error: $e');
      result.status = 'error';
      if (!completer.isCompleted) completer.complete();
    }, onDone: () {
      if (!completer.isCompleted) {
        result.errorBuf.writeln('Conexión cerrada por el servidor');
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      result.status = 'timeout';
      result.errorBuf.writeln('Timeout: la celda siguió ejecutando');
      await sub.cancel();
    }
    return result;
  }

  void _send(String type, Map<String, dynamic> content, {String? msgId}) {
    final id = msgId ?? _uuid();
    final now =
        DateTime.now().toUtc().toIso8601String().replaceAll('000Z', 'Z');
    final frame = [
      {
        'msg_id': id,
        'username': 'pr_app',
        'session': _sessionId,
        'date': now,
        'msg_type': type,
        'version': '5.3',
      },
      {},
      {},
      content,
      [],
    ];
    _channel!.sink.add(jsonEncode(frame));
  }

  Future<void> close() async {
    try {
      if (_kernelId != null && _started) {
        await http.delete(
          Uri.parse('$serverUrl/api/kernels/$_kernelId'),
          headers: {..._headers, 'Authorization': 'Bearer $proxyToken'},
        ).timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _kernelId = null;
    _started = false;
  }

  static final _rnd = Random();
  static String _uuid() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
