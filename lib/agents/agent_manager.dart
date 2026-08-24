import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../services/crypto_vault.dart';
import '../services/settings.dart';
import 'key_vault.dart';
import 'lua_sandbox.dart';
import 'provider_registry.dart';
import 'tools.dart';

enum AgentStatus { idle, running, waitingPermission, stopped, error }

/// Cómo se poda el historial al superar el presupuesto de contexto.
enum HistModo { ventana, resumen, hibrido }

class AgentMsg {
  final String role; // user | assistant | tool
  final String content;
  final String? toolName;
  AgentMsg({required this.role, required this.content, this.toolName});

  Map<String, dynamic> toJson() =>
      {'role': role, 'content': content, if (toolName != null) 'tool': toolName};
  factory AgentMsg.fromJson(Map<String, dynamic> j) => AgentMsg(
      role: j['role'] ?? 'assistant',
      content: j['content'] ?? '',
      toolName: j['tool'] as String?);
}

class Agent {
  final String id;
  String name;
  String mission;
  String providerId;
  String model;
  Set<AgentPermission> permissions;
  AgentStatus status = AgentStatus.idle;
  String lastError = '';
  String pendingToolName = '';
  Map<String, dynamic>? pendingToolArgs;
  int iterations = 0;
  bool stopFlag = false;

  /// Cómo se poda el historial cuando supera el presupuesto de contexto.
  /// ventana: últimos N mensajes + marcador (menos tokens).
  /// resumen: cola vieja → llamada corta al modelo que la resume.
  /// hibrido: como resumen pero refresca el caché solo cuando el
  /// desborde crece 1.5x desde el último resumen.
  HistModo histModo = HistModo.ventana;

  /// Resumen vigente de lo podado (modos resumen/hibrido).
  String histResumenCache = '';

  /// Caracteres evictados que cubre [histResumenCache] (umbral híbrido).
  int histCubiertoChars = 0;

  Completer<bool>? _permissionWaiter;

  /// Chat individual del agente (se envía como historial).
  final List<AgentMsg> log = [];

  /// ¿El agente generó una página GUI con lua_gui?
  bool get hasGui => LuaSandbox.instance.lastPage != null;

  Agent({
    required this.id,
    required this.name,
    required this.mission,
    required this.providerId,
    required this.model,
    required this.permissions,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mission': mission,
        'provider': providerId,
        'model': model,
        'permissions': permissions.map((p) => p.name).toList(),
        'histModo': histModo.name,
        'histResumen': histResumenCache,
        'histCubierto': histCubiertoChars,
        'log': log.map((m) => m.toJson()).toList(),
      };

  static Agent fromJson(Map<String, dynamic> j) => Agent(
        id: j['id'],
        name: j['name'] ?? '',
        mission: j['mission'] ?? '',
        providerId: j['provider'] ?? '',
        model: j['model'] ?? '',
        permissions: ((j['permissions'] as List?) ?? [])
            .map((s) =>
                AgentPermission.values.firstWhere((p) => p.name == s,
                    orElse: () => AgentPermission.readFiles))
            .toSet(),
      )
        ..histModo = HistModo.values.firstWhere(
            (m) => m.name == (j['histModo'] ?? 'ventana'),
            orElse: () => HistModo.ventana)
        ..histResumenCache = (j['histResumen'] ?? '') as String
        ..histCubiertoChars = ((j['histCubierto'] as num?) ?? 0).toInt()
        ..log.addAll(((j['log'] as List?) ?? [])
            .map((e) => AgentMsg.fromJson(e))
            .toList());
}

/// Núcleo estilo FilosoIA portado a Dart puro: agentes con misión que
/// corren un loop de tool-calling SIN detenerse (auto-continúa) y piden
/// permiso inline cuando una herramienta no está autorizada.
/// Singleton a nivel app → los agentes siguen vivos aunque cambies de
/// pantalla. Persistencia cifrada en appSupport/filosoia_agents.pr.
class AgentManager extends ChangeNotifier {
  AgentManager._();
  static final AgentManager instance = AgentManager._();

  static const _fileName = 'filosoia_agents.pr';
  static const _maxIterations = 15;

  /// Presupuesto de historial en caracteres (~6k tokens). Si el log lo
  /// supera se poda según [HistModo] antes de cada POST.
  static const int kHistMaxChars = 24000;

  /// Gancho futuro: provider alternativo para resumir (ej. modelo
  /// local). null = usar el mismo provider del agente.
  static const String? kProveedorResumenOverride = null;

  final List<Agent> agents = [];
  bool _loaded = false;
  final http.Client _http = http.Client();

  // ------------------------------------------------------- persistencia

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      await KeyVault.instance.load();
      final f = await _file();
      if (!f.existsSync()) return;
      final plain = await CryptoVault.decrypt(
          await f.readAsBytes(), Settings.instance.masterKey);
      if (plain == null) return;
      final list = jsonDecode(utf8.decode(plain))['agents'] as List? ?? [];
      agents.clear();
      for (final e in list) {
        final a = Agent.fromJson(e as Map<String, dynamic>);
        a.status = AgentStatus.idle; // nunca restaurar corriendo
        agents.add(a);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      final json = utf8.encode(jsonEncode({
        'agents': agents.map((a) => a.toJson()).toList(),
      }));
      final enc = await CryptoVault.encrypt(
          Uint8List.fromList(json), Settings.instance.masterKey);
      await f.writeAsBytes(enc, flush: true);
    } catch (_) {}
  }

  // ------------------------------------------------------------ gestión

  Agent create({
    required String name,
    required String mission,
    required String providerId,
    required String model,
    required Set<AgentPermission> permissions,
  }) {
    final a = Agent(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Agente' : name.trim(),
      mission: mission.trim(),
      providerId: providerId,
      model: model.trim().isEmpty
          ? (providerById(providerId)?.defaultModel ?? '')
          : model.trim(),
      permissions: permissions,
    );
    agents.add(a);
    _persist();
    notifyListeners();
    return a;
  }

  void remove(String id) {
    agents.removeWhere((a) => a.id == id);
    _persist();
    notifyListeners();
  }

  void stop(String id) {
    final a = byId(id);
    if (a == null) return;
    a.stopFlag = true;
    a._permissionWaiter?.complete(false);
    a.status = AgentStatus.stopped;
    notifyListeners();
    _persist();
  }

  void revive(String id) {
    final a = byId(id);
    if (a == null) return;
    a.stopFlag = false;
    a.status = AgentStatus.idle;
    KeyVault.instance.reviveKeys(a.providerId);
    notifyListeners();
  }

  Agent? byId(String id) {
    for (final a in agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Aprobar/denegar la herramienta pendiente del agente.
  void resolvePermission(String agentId, bool granted) {
    final a = byId(agentId);
    a?._permissionWaiter?.complete(granted);
  }

  /// Los agentes ordenados por prioridad de proveedor.
  List<Agent> get sorted {
    final copy = [...agents];
    copy.sort((x, y) {
      final px = providerById(x.providerId)?.priority ?? 99;
      final py = providerById(y.providerId)?.priority ?? 99;
      return px.compareTo(py);
    });
    return copy;
  }

  // ------------------------------------------------- conversación/loop

  /// Mandar tarea al agente y correr el loop (fire & forget).
  void talk(String agentId, String task) {
    final a = byId(agentId);
    if (a == null || a.status == AgentStatus.running) return;
    a.stopFlag = false;
    a.log.add(AgentMsg(role: 'user', content: task));
    unawaited(_loop(a));
  }

  // ------------------------------------------------ historial con poda

  Map<String, dynamic> _mapMsg(AgentMsg m) => m.role == 'tool'
      ? {
          'role': 'tool',
          'tool_call_id': m.toolName ?? m.content.hashCode,
          'content': m.content,
        }
      : {'role': m.role, 'content': m.content};

  /// Índice de arranque de la ventana: hacia atrás hasta entrar en el
  /// presupuesto, y si cae sobre un resultado 'tool' lo salta para no
  /// mandar un tool huérfano (regla fija en todos los modos).
  int _inicioVentana(List<AgentMsg> log) {
    var start = log.length;
    var acc = 0;
    while (start > 0 && acc + log[start - 1].content.length <= kHistMaxChars) {
      start--;
      acc += log[start].content.length;
    }
    while (start < log.length && log[start].role == 'tool') {
      start++;
    }
    return start;
  }

  /// Resumen corto de la cola vieja. null = falló → caller usa ventana.
  Future<String?> _resumir(Agent a, List<AgentMsg> viejos) async {
    try {
      final pid = kProveedorResumenOverride ?? a.providerId;
      final prov = providerById(pid);
      if (prov == null) return null;
      final key = KeyVault.instance.nextKey(pid);
      if (key == null) return null;
      final texto =
          viejos.map((m) => '${m.role}: ${_clip(m.content, 400)}').join('\n');
      final res = await _http
          .post(
            Uri.parse('${KeyVault.instance.baseUrlFor(prov)}/chat/completions'),
            headers: {
              'authorization': 'Bearer $key',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': a.model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Resumí en español esta conversación en máximo 300 '
                          'palabras, conservando datos, decisiones y pendientes.'
                },
                {'role': 'user', 'content': texto},
              ],
              'max_tokens': 400,
              'temperature': 0.2,
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) return null;
      final out =
          ((jsonDecode(res.body)['choices'][0]['message'])['content'] ?? '')
              .toString();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// Arma los messages del POST aplicando [HistModo] si el log desborda.
  /// mission SIEMPRE va completa al frente.
  Future<List<Map<String, dynamic>>> _mensajesParaEnviar(Agent a) async {
    final total = a.log.fold<int>(0, (n, m) => n + m.content.length);
    if (total <= kHistMaxChars) {
      return [for (final m in a.log) _mapMsg(m)];
    }

    final start = _inicioVentana(a.log);
    final evictados = a.log.take(start).toList();
    final evictChars = total -
        a.log.skip(start).fold<int>(0, (n, m) => n + m.content.length);
    final ventana = [
      for (final m in a.log.skip(start)) _mapMsg(m),
    ];
    if (evictados.isEmpty) return ventana;

    String? resumen;
    switch (a.histModo) {
      case HistModo.ventana:
        resumen = null;
      case HistModo.resumen:
        resumen = await _resumir(a, evictados);
      case HistModo.hibrido:
        if (a.histResumenCache.isEmpty ||
            evictChars > a.histCubiertoChars * 3 ~/ 2) {
          final r = await _resumir(a, evictados);
          if (r != null) {
            a.histResumenCache = r;
            a.histCubiertoChars = evictChars;
            _persist();
          }
        }
        resumen = a.histResumenCache.isEmpty ? null : a.histResumenCache;
    }

    if (resumen == null) {
      // fallback silencioso a ventana
      return [
        {
          'role': 'system',
          'content':
              '[se omitieron ${evictados.length} mensajes anteriores por límite de contexto]'
        },
        ...ventana,
      ];
    }
    return [
      {'role': 'system', 'content': 'Resumen de lo anterior: $resumen'},
      ...ventana,
    ];
  }

  /// Cambia el modo de historial desde la UI y persiste.
  Future<void> setHistMode(Agent a, HistModo modo) async {
    a.histModo = modo;
    notifyListeners();
    await _persist();
  }

  Future<void> _loop(Agent a) async {
    a.iterations = 0;
    while (!a.stopFlag && a.iterations < _maxIterations) {
      a.iterations++;
      a.status = AgentStatus.running;
      a.lastError = '';
      notifyListeners();

      final key = KeyVault.instance.nextKey(a.providerId);
      if (key == null) {
        a.status = AgentStatus.error;
        a.lastError = 'sin API key válida para ${a.providerId}';
        notifyListeners();
        return;
      }

      http.Response res;
      try {
        final mensajes = [
          {'role': 'system', 'content': a.mission},
          ...await _mensajesParaEnviar(a),
        ];
        res = await _http.post(
          Uri.parse('${KeyVault.instance.baseUrlFor(providerById(a.providerId)!)}'
              '/chat/completions'),
          headers: {
            'authorization': 'Bearer $key',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': a.model,
            'messages': mensajes,
            'tools': [for (final t in AGENT_TOOLS) t.toSchema()],
            'temperature': 0.4,
          }),
        ).timeout(const Duration(seconds: 120));
      } catch (e) {
        a.status = AgentStatus.error;
        a.lastError = '$e';
        notifyListeners();
        return;
      }

      // Rotación de keys ante auth error (semántica FilosoIA).
      if (res.statusCode == 401 || res.statusCode == 403) {
        KeyVault.instance.markDeadAndRotate(a.providerId);
        continue; // reintenta con otra key sin parar el flujo
      }
      if (res.statusCode != 200) {
        a.status = AgentStatus.error;
        a.lastError = 'HTTP ${res.statusCode}: ${_clip(res.body, 300)}';
        notifyListeners();
        return;
      }

      dynamic msg;
      try {
        msg =
            (jsonDecode(res.body)['choices'][0]['message']) as dynamic;
      } catch (_) {
        a.status = AgentStatus.error;
        a.lastError = 'respuesta no parseable';
        notifyListeners();
        return;
      }

      final toolCalls = msg['tool_calls'];
      if (toolCalls is List && toolCalls.isNotEmpty) {
        // registrar lo que dijo antes de las tools (si algo)
        final txt = msg['content']?.toString() ?? '';
        if (txt.isNotEmpty) a.log.add(AgentMsg(role: 'assistant', content: txt));

        for (final tc in toolCalls) {
          if (a.stopFlag) break;
          final fn = tc['function'] ?? {};
          final name = fn['name']?.toString() ?? '';
          final args = parseToolArgs(fn['arguments']?.toString() ?? '');
          final def = toolByName(name);

          if (def == null) {
            a.log.add(AgentMsg(
                role: 'tool', toolName: name, content: 'herramienta inexistente'));
            continue;
          }

          // PERMISO: si no está autorizado → pausa y espera decisión.
          if (!a.permissions.contains(def.permission)) {
            a.pendingToolName = name;
            a.pendingToolArgs = args;
            a.status = AgentStatus.waitingPermission;
            notifyListeners();
            final waiter = Completer<bool>();
            a._permissionWaiter = waiter;
            final granted = await waiter.future;
            a._permissionWaiter = null;
            a.pendingToolName = '';
            a.pendingToolArgs = null;
            if (a.stopFlag) break;
            if (!granted) {
              a.log.add(AgentMsg(
                  role: 'tool',
                  toolName: name,
                  content: 'DENEGADO por el usuario'));
              continue;
            }
            // otorgado SOLO esta vez: ejecutar sin agregar permiso fijo
            final out = await executeTool(name, args);
            a.log.add(AgentMsg(role: 'tool', toolName: name, content: out));
            notifyListeners();
            continue;
          }

          a.log.add(AgentMsg(
              role: 'assistant',
              content: '🔧 $name ${jsonEncode(args)}',
              toolName: name));
          final out = await executeTool(name, args);
          a.log.add(AgentMsg(role: 'tool', toolName: name, content: out));
          notifyListeners();
        }
        _persist();
        continue; // vuelta al LLM con los resultados
      }

      // respuesta final sin tools
      final content = msg['content']?.toString() ?? '';
      a.log.add(AgentMsg(role: 'assistant', content: content));
      a.status = AgentStatus.idle;
      notifyListeners();
      _persist();
      return;
    }
    if (a.iterations >= _maxIterations && a.status == AgentStatus.running) {
      a.status = AgentStatus.error;
      a.lastError = 'límite de $_maxIterations iteraciones de herramientas';
    }
    notifyListeners();
    _persist();
  }

  static String _clip(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}
