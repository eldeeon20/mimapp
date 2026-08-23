import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../services/crypto_vault.dart';
import '../services/settings.dart';
import 'key_vault.dart';
import 'provider_registry.dart';
import 'tools.dart';

enum AgentStatus { idle, running, waitingPermission, stopped, error }

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
      )..log.addAll(((j['log'] as List?) ?? [])
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
        res = await _http.post(
          Uri.parse('${KeyVault.instance.baseUrlFor(providerById(a.providerId)!)}'
              '/chat/completions'),
          headers: {
            'authorization': 'Bearer $key',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': a.model,
            'messages': [
              {'role': 'system', 'content': a.mission},
              ...a.log.map((m) => m.role == 'tool'
                  ? {
                      'role': 'tool',
                      'tool_call_id': m.toolName ?? m.content.hashCode,
                      'content': m.content,
                    }
                  : {'role': m.role, 'content': m.content}),
            ],
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
