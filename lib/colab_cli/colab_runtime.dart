import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
/// Réplica de google-colab-cli (runtime.py + jupyter_kernel_client,
/// subprotocolo DEFAULT):
///   1. POST {serverUrl}/api/kernels        → crea kernel python3
///   2. WS   {serverUrl}/api/kernels/{id}/channels
///          ?session_id=..&colab-runtime-proxy-token=..
///          headers: X-Colab-Runtime-Proxy-Token + X-Colab-Client-Agent
///   3. mensajes: frames JSON texto [header, parent, metadata, content, []]
class ColabRuntime {
  final String serverUrl;
  final String proxyToken;

  WebSocketChannel? _channel;
  String? _kernelId;
  final String _sessionId = _uuid();
  bool _started = false;
  bool _closedByUs = false;

  /// Router de mensajes (1 sola suscripción al stream del canal).
  final StreamController<Map<String, dynamic>> _msgs =
      StreamController<Map<String, dynamic>>.broadcast();

  ColabRuntime({required this.serverUrl, required this.proxyToken});

  bool get started => _started;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Colab-Client-Agent': 'pr_app',
        'X-Colab-Runtime-Proxy-Token': proxyToken,
      };

  /// Crea el kernel y abre el WebSocket (un listener persistente).
  Future<void> start() async {
    if (_started) return;

    final resp = await http.post(
      Uri.parse('$serverUrl/api/kernels'),
      headers: _headers,
      body: jsonEncode({'name': 'python3', 'path': ''}),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      var body = resp.body.replaceAll(RegExp(r'<[^>]*>'), ' ');
      body = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      throw Exception('Error creando kernel (${resp.statusCode}): '
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
    final wsUri = Uri.parse('$base/api/kernels/$_kernelId/channels').replace(
      queryParameters: {
        'session_id': _sessionId,
        'colab-runtime-proxy-token': proxyToken,
      },
    );
    _channel = IOWebSocketChannel.connect(
      wsUri,
      headers: _headers,
      pingInterval: const Duration(seconds: 30),
    );
    _closedByUs = false;
    // Listener ÚNICO: enruta todos los frames al router _msgs.
    _channel!.stream.listen(
      _onFrame,
      onError: (e) => _msgs.add({'__error': true, 'text': e.toString()}),
      onDone: () {
        if (!_closedByUs) _msgs.add({'__closed': true});
      },
    );
    await _channel!.ready;
    _started = true;
  }

  void _onFrame(dynamic raw) {
    try {
      Map<String, dynamic> msg;
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List && decoded.length >= 4) {
          msg = Map<String, dynamic>.from(decoded[3] as Map);
          msg['_parent'] = decoded[1];
        } else {
          return;
        }
      } else if (raw is List<int>) {
        final parsed = _parseBinary(raw);
        if (parsed == null) return;
        msg = parsed;
      } else {
        return;
      }
      _msgs.add(msg);
    } catch (_) {
      // Frame no parseable: ignorar.
    }
  }

  /// Parsea frame binario (v1) devolviendo {content, _parent, ...}.
  Map<String, dynamic>? _parseBinary(List<int> b) {
    try {
      if (b.length >= 16) {
        final n = _le64(b, 0);
        if (n >= 2 && 8 * (n + 1) <= b.length) {
          final offs = [for (var i = 0; i < n; i++) _le64(b, 8 * (i + 1))];
          if (offs.last <= b.length) {
            final parts = <List<int>>[];
            for (var i = 1; i < n - 1; i++) {
              if (offs[i] < offs[i + 1] && offs[i + 1] <= b.length) {
                parts.add(b.sublist(offs[i], offs[i + 1]));
              }
            }
            if (parts.length >= 4) {
              final content =
                  jsonDecode(utf8.decode(parts[3])) as Map<String, dynamic>;
              final parent = parts.length > 1
                  ? jsonDecode(utf8.decode(parts[1]))
                  : <String, dynamic>{};
              content['_parent'] = parent;
              return content;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static int _le64(List<int> b, int off) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v |= b[off + i] << (8 * i);
    }
    return v;
  }

  Future<ColabExecResult> execute(
    String code, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (!_started || _channel == null) await start();
    return _executeWithRetry(code, timeout, 1);
  }

  Future<ColabExecResult> _executeWithRetry(
      String code, Duration timeout, int retries) async {
    final result = ColabExecResult();
    final msgId = _uuid();
    _send('shell', 'execute_request', {
      'code': code,
      'silent': false,
      'store_history': true,
      'user_expressions': {},
      'allow_stdin': false,
      'stop_on_error': true,
    }, msgId: msgId);

    final completer = Completer<void>();
    late final StreamSubscription sub;
    sub = _msgs.stream.listen((msg) {
      if (msg['__closed'] == true) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      if (msg['__error'] == true) {
        result.errorBuf.writeln('WS error: ${msg['text']}');
        result.status = 'error';
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final header = (msg['header'] ?? msg) as Map<String, dynamic>? ?? {};
      final content = msg['content'] as Map<String, dynamic>? ?? {};
      final type = header['msg_type'] ?? msg['msg_type'];
      final parent = msg['_parent'];
      final ours = parent is Map && parent['msg_id'] == msgId;

      switch (type) {
        case 'stream':
          result.stdoutBuf.write('${content['text']}');
          break;
        case 'execute_result':
        case 'display_data':
          final dataMap = content['data'] ?? {};
          final text = dataMap['text/plain'];
          if (text is String && ours) result.results.add(text);
          break;
        case 'error':
          final tb = content['traceback'];
          if (tb is List) result.errorBuf.writeln(tb.join('\n'));
          result.status = 'error';
          break;
        case 'status':
          if (content['execution_state'] == 'idle' && ours) {
            if (!completer.isCompleted) completer.complete();
            unawaited(sub.cancel());
          }
          break;
        case 'execute_reply':
          if (ours) {
            final st = content['status'];
            if (st == 'error' || st == 'abort') result.status = 'error';
            if (!completer.isCompleted) completer.complete();
            unawaited(sub.cancel());
          }
          break;
        case 'error_output':
          result.stderrBuf.write('${content['text']}');
          break;
      }
    });

    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      result.status = 'timeout';
      result.errorBuf.writeln('Timeout: la celda siguió ejecutando');
      await sub.cancel();
    }

    // Si el canal se cerró y no hubo salida, reconectamos 1 vez.
    if (retries > 0 && !completer.isCompleted && result.output.isEmpty) {
      await _reconnect();
      return _executeWithRetry(code, timeout, retries - 1);
    }
    return result;
  }

  Future<void> _reconnect() async {
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _started = false;
    await start();
  }

  void _send(String channel, String type, Map<String, dynamic> content,
      {String? msgId}) {
    final id = msgId ?? _uuid();
    final now = DateTime.now().toUtc().toIso8601String().replaceAll('000Z', 'Z');
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
        await http
            .delete(
              Uri.parse('$serverUrl/api/kernels/$_kernelId'),
              headers: _headers,
            )
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    _closedByUs = true;
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
