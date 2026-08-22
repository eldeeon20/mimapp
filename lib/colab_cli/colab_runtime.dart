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
  bool connLost = false; // el WS se cerró/dio error durante la ejecución
  bool gotFrames = false; // llegó al menos un frame del kernel

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

  /// Generación de conexión. Cada start() la incrementa; los listeners de un
  /// socket viejo se ignoran si su generación ya no es la actual.
  int _gen = 0;

  /// Pide datos al usuario cuando el kernel lanza input_request (input()).
  /// Retorna lo tipeado (o null para vacío).
  Future<String?> Function(String prompt, bool password)? onInputRequest;

  /// Ejecución activa (para poder frenarla con [interruptCurrent]).
  Completer<void>? _activeCompleter;
  ColabExecResult? _activeResult;

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

  /// Abre el WebSocket del kernel. Reutiliza el kernel existente si ya hay
  /// uno (NO crea kernels nuevos en cada reconexión: se pierden variables).
  Future<void> start() async {
    if (_started) return;
    _gen++;
    final gen = _gen;

    if (_kernelId == null) {
      // Solo la PRIMERA vez: crear el kernel.
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
        throw Exception(
            'Respuesta sin kernel id: ${resp.body.substring(0, 120)}');
      }
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
    // Listener ÚNICO por conexión: los de generaciones viejas no tocan nada.
    _channel!.stream.listen(
      _onFrame,
      onError: (e) {
        if (gen != _gen) return;
        _started = false;
        _channel = null;
        _msgs.add({'__error': true, 'text': e.toString()});
      },
      onDone: () {
        if (gen != _gen) return;
        // Colab cerró el WS: reset para que el próximo execute() reconecte
        // AL MISMO kernel (sin perder variables).
        _started = false;
        _channel = null;
        _msgs.add({'__closed': true});
      },
    );
    await _channel!.ready;
    if (gen != _gen) {
      try {
        await _channel?.sink.close();
      } catch (_) {}
      return;
    }
    _started = true;
  }

  void _onFrame(dynamic raw) {
    try {
      final msg = _decodeFrame(raw);
      if (msg != null) _msgs.add(msg);
    } catch (_) {
      // Frame no parseable: ignorar.
    }
  }

  /// Decodifica un frame (texto lista, texto mapa o binario v1) en
  /// {header, content, _parent}. Devuelve null si no se entiende.
  Map<String, dynamic>? _decodeFrame(dynamic raw) {
    if (raw is String) {
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.length >= 4) {
        return <String, dynamic>{
          'header': _asMap(decoded[0]),
          'content': _asMap(decoded[3]),
          '_parent': _asMap(decoded[1]),
        };
      } else if (decoded is Map) {
        // Variante Colab: objeto {header, parent_header, metadata, content}.
        return <String, dynamic>{
          'header': _asMap(decoded['header']),
          'content': _asMap(decoded['content']),
          '_parent': _asMap(decoded['parent_header'] ?? decoded['parent']),
        };
      }
      return <String, dynamic>{'__raw': raw.toString()};
    } else if (raw is List<int>) {
      return _parseBinary(raw);
    }
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  /// Frame binario del protocolo DEFAULT (jupyter_kernel_client/utils.py):
  /// [4B BE nbufs][nbufs x 4B BE offsets] donde el JSON va de offsets[0]
  /// a offsets[1] y el resto son buffers binarios.
  Map<String, dynamic>? _parseBinary(List<int> b) {
    try {
      if (b.length < 8) return null;
      final nbufs = _be32(b, 0);
      if (nbufs < 2 || 4 * (nbufs + 1) > b.length) return null;
      final offsets = [for (var i = 0; i < nbufs; i++) _be32(b, 4 * (i + 1))];
      final jsonStart = offsets[0];
      final jsonStop = offsets[1];
      if (jsonStart < 0 || jsonStart > jsonStop || jsonStop > b.length) {
        return null;
      }
      final msg =
          jsonDecode(utf8.decode(b.sublist(jsonStart, jsonStop))) as Map;
      return <String, dynamic>{
        'header': _asMap(msg['header']),
        'content': _asMap(msg['content']),
        '_parent': _asMap(msg['parent_header']),
      };
    } catch (_) {
      return null;
    }
  }

  static final RegExp _ansiRe = RegExp(r'\x1b\[[0-9;]*[A-Za-z]');

  /// Saca códigos de escape ANSI (colores) de la salida del kernel.
  static String _stripAnsi(String s) => s.replaceAll(_ansiRe, '');

  static int _be32(List<int> b, int off) {
    return (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];
  }

  /// Frena la celda en ejecución: manda interrupt_request al kernel (control)
  /// y libera la espera local marcando el resultado como interrumpido.
  void interruptCurrent() {
    try {
      _send('control', 'interrupt_request', <String, dynamic>{});
    } catch (_) {}
    final r = _activeResult;
    if (r != null && !r.isError) {
      r.status = 'error';
      r.errorBuf.writeln('(celda interrumpida por el usuario)');
    }
    final c = _activeCompleter;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<ColabExecResult> execute(
    String code, {
    Duration timeout = const Duration(minutes: 10),
    void Function(String partial)? onTick,
  }) async {
    ColabExecResult? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!_started || _channel == null) await start();
      try {
        last = await _executeWithRetry(code, timeout, onTick: onTick);
      } catch (e) {
        last = ColabExecResult()
          ..errorBuf.writeln('WS error: $e')
          ..status = 'error'
          ..connLost = true;
      }
      // Reintentar SOLO si la conexión está muerta. Una celda sin salida
      // (ej: `x = 1`) es un resultado VÁLIDO: no se toca el kernel.
      final dead = last.output.isEmpty &&
          !last.isError &&
          (last.connLost || !last.gotFrames);
      if (!dead) return last;
      await _killChannel();
    }
    return last ?? ColabExecResult();
  }

  /// Cierra el WS actual invalidando sus listeners (sin borrar el kernel:
  /// se conserva el estado de las variables para la reconexión).
  Future<void> _killChannel() async {
    _started = false;
    _gen++;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<ColabExecResult> _executeWithRetry(
      String code, Duration timeout,
      {void Function(String partial)? onTick}) async {
    final result = ColabExecResult();
    final msgId = _uuid();
    final completer = Completer<void>();
    _activeResult = result;
    _activeCompleter = completer;
    _send('shell', 'execute_request', {
      'code': code,
      'silent': false,
      'store_history': true,
      'user_expressions': {},
      'allow_stdin': true, // soporte input() con input_request/input_reply
      'stop_on_error': true,
    }, msgId: msgId);
    late final StreamSubscription sub;
    sub = _msgs.stream.listen((msg) {
      if (msg['__closed'] == true) {
        result.connLost = true;
        if (!completer.isCompleted) completer.complete();
        unawaited(sub.cancel());
        return;
      }
      if (msg['__error'] == true) {
        result.connLost = true;
        result.errorBuf.writeln('WS error: ${msg['text']}');
        result.status = 'error';
        if (!completer.isCompleted) completer.complete();
        unawaited(sub.cancel());
        return;
      }
      result.gotFrames = true;
      final header = (msg['header'] ?? msg) as Map<String, dynamic>? ?? {};
      final content = msg['content'] as Map<String, dynamic>? ?? {};
      final type = header['msg_type'] ?? msg['msg_type'];

      switch (type) {
        case 'stream':
          result.stdoutBuf.write(_stripAnsi('${content['text'] ?? ''}'));
          onTick?.call(result.output);
          break;
        case 'execute_result':
        case 'display_data':
          final dataMap = content['data'] ?? {};
          final text = dataMap['text/plain'];
          if (text is String) {
            result.results.add(_stripAnsi(text));
            onTick?.call(result.output);
          }
          break;
        case 'error':
          final tb = content['traceback'];
          if (tb is List) {
            result.errorBuf.writeln(_stripAnsi(tb.join('\n')));
          }
          result.status = 'error';
          onTick?.call(result.output);
          break;
        case 'status':
          if (content['execution_state'] == 'idle') {
            if (!completer.isCompleted) completer.complete();
            unawaited(sub.cancel());
          }
          break;
        case 'execute_reply':
          final st = content['status'];
          if (st == 'error' || st == 'abort') result.status = 'error';
          if (!completer.isCompleted) completer.complete();
          unawaited(sub.cancel());
          break;
        case 'error_output':
          result.stderrBuf.write('${content['text'] ?? ''}');
          onTick?.call(result.output);
          break;
        case 'input_request':
          // El kernel pide datos (input() de Python): delegar en la UI.
          unawaited(_answerInput(
            content['prompt']?.toString() ?? '',
            content['password'] == true,
          ));
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

    _activeCompleter = null;
    _activeResult = null;
    return result;
  }

  Future<void> _answerInput(String prompt, bool password) async {
    String value = '';
    final cb = onInputRequest;
    if (cb != null) {
      try {
        value = await cb(prompt, password) ?? '';
      } catch (_) {}
    }
    try {
      _send('stdin', 'input_reply', {'value': value});
    } catch (_) {}
  }

  void _send(String channel, String type, Map<String, dynamic> content,
      {String? msgId}) {
    final id = msgId ?? _uuid();
    final now = DateTime.now().toUtc().toIso8601String().replaceAll('000Z', 'Z');
    // Protocolo DEFAULT de jupyter_server: UN objeto JSON con campo `channel`.
    // (jupyter_kernel_client/wsclient.py:226 msg['channel'] = channel)
    final msg = <String, dynamic>{
      'header': {
        'msg_id': id,
        'username': 'pr_app',
        'session': _sessionId,
        'date': now,
        'msg_type': type,
        'version': '5.3',
      },
      'parent_header': <String, dynamic>{},
      'metadata': <String, dynamic>{},
      'content': content,
      'buffers': <dynamic>[],
      'channel': channel,
    };
    _channel!.sink.add(jsonEncode(msg));
  }

  Future<void> close() async {
    _gen++; // invalida los listeners del socket actual
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
