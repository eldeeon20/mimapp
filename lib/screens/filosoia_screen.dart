import 'package:flutter/material.dart';

import '../agents/agent_manager.dart';
import '../agents/key_vault.dart';
import '../agents/provider_registry.dart';
import '../agents/tools.dart';
import 'needle_test_screen.dart';

/// FilosoIA en pr_app: gestión de proveedores/keys, agentes con misión
/// y chats individuales con tool-calling automático.
class FilosoiaScreen extends StatefulWidget {
  const FilosoiaScreen({super.key});

  @override
  State<FilosoiaScreen> createState() => _FilosoiaScreenState();
}

class _FilosoiaScreenState extends State<FilosoiaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this);
  String? _chatAgentId;

  @override
  void initState() {
    super.initState();
    AgentManager.instance.ensureLoaded().then((_) {
      if (!mounted) return;
      final list = AgentManager.instance.sorted;
      if (_chatAgentId == null && list.isNotEmpty) {
        setState(() => _chatAgentId = list.first.id);
      }
    });
    AgentManager.instance.addListener(_bump);
    KeyVault.instance.addListener(_bump);
  }

  void _bump() => mounted ? setState(() {}) : null;

  @override
  void dispose() {
    AgentManager.instance.removeListener(_bump);
    KeyVault.instance.removeListener(_bump);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agentes IA'),
        actions: [
          IconButton(
            tooltip: 'Tool-calling local (Needle)',
            icon: const Icon(Icons.handyman_rounded),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NeedleTestScreen())),
          ),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Proveedores'),
          Tab(text: 'Agentes'),
          Tab(text: 'Chat'),
        ]),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([AgentManager.instance, KeyVault.instance]),
        builder: (_, __) => TabBarView(controller: _tabs, children: [
          _providersTab(),
          _agentsTab(),
          _chatTab(),
        ]),
      ),
    );
  }

  // ================================================== TAB PROVEEDORES

  Widget _providersTab() {
    final list = [...AI_PROVIDERS]..sort((a, b) => a.priority.compareTo(b.priority));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final p = list[i];
        final n = KeyVault.instance.keyCount(p.id);
        final starred = p.priority <= 3;
        return ListTile(
          leading: Text('#${p.priority}',
              style: TextStyle(
                  fontSize: 11,
                  color: starred ? Colors.amberAccent : Colors.white24)),
          title: Text(p.name,
              style: TextStyle(
                  fontWeight:
                      starred ? FontWeight.bold : FontWeight.normal)),
          subtitle: Text(KeyVault.instance.baseUrlFor(p),
              style: const TextStyle(fontSize: 10)),
          trailing: Chip(
            label: Text('$n keys',
                style: const TextStyle(fontSize: 10)),
            backgroundColor: n > 0
                ? Colors.green.withValues(alpha: .2)
                : Colors.red.withValues(alpha: .15),
          ),
          onTap: () => _manageProvider(p),
        );
      },
    );
  }

  Future<void> _manageProvider(AiProvider p) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ProviderSheet(provider: p),
    );
    setState(() {});
  }

  // ====================================================== TAB AGENTES

  Widget _agentsTab() {
    final list = AgentManager.instance.sorted;
    return Stack(children: [
      if (list.isEmpty)
        Center(
            child: Text('Sin agentes.\nTocá ＋ para crear uno con misión y permisos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38))),
      ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) => _agentCard(list[i]),
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          onPressed: _newAgentDialog,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Agente'),
        ),
      ),
    ]);
  }

  Color _statusColor(AgentStatus s) => switch (s) {
        AgentStatus.running => Colors.green,
        AgentStatus.waitingPermission => Colors.orange,
        AgentStatus.error => Colors.red,
        AgentStatus.stopped => Colors.blueGrey,
        AgentStatus.idle => Colors.cyanAccent,
      };

  Widget _agentCard(Agent a) {
    final p = providerById(a.providerId);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: a.status == AgentStatus.waitingPermission
          ? Colors.orange.withValues(alpha: .08)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(a.name,
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            Chip(
              label: Text(a.status.name,
                  style: TextStyle(
                      fontSize: 10, color: _statusColor(a.status))),
              backgroundColor: _statusColor(a.status).withValues(alpha: .15),
            ),
          ]),
          if (a.mission.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(a.mission,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white54)),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 2, children: [
            for (final perm in a.permissions)
              Chip(
                label: Text(perm.label,
                    style: const TextStyle(fontSize: 9)),
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.white.withValues(alpha: .05),
              ),
            if (a.permissions.isEmpty)
              const Text('sin permisos',
                  style: TextStyle(fontSize: 9, color: Colors.white24)),
          ]),
          const SizedBox(height: 6),
          Text('· ${p?.name ?? a.providerId} · ${a.model} · '
              'key ${KeyVault.instance.keyCount(a.providerId)}',
              style: const TextStyle(fontSize: 10, color: Colors.white38)),
          if (a.status == AgentStatus.waitingPermission)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pide permiso: ${a.pendingToolName}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.orangeAccent)),
                    if ((a.pendingToolArgs ?? {}).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(a.pendingToolArgs.toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 9, color: Colors.white38)),
                      ),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(
                          onPressed: () => AgentManager.instance
                              .resolvePermission(a.id, false),
                          child: const Text('Denegar')),
                      FilledButton.tonal(
                          onPressed: () => AgentManager.instance
                              .resolvePermission(a.id, true),
                          child: const Text('Aprobar')),
                    ]),
                  ]),
            ),
          if (a.status == AgentStatus.error && a.lastError.isNotEmpty)
            Text(a.lastError,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
          const SizedBox(height: 6),
          Row(children: [
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _chatAgentId = a.id);
                _tabs.animateTo(2);
              },
              icon: const Icon(Icons.chat_rounded, size: 16),
              label: const Text('Hablar', style: TextStyle(fontSize: 11)),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Detener',
              onPressed: () => AgentManager.instance.stop(a.id),
              icon: const Icon(Icons.stop_circle_rounded, size: 20),
            ),
            if (a.status == AgentStatus.stopped ||
                a.status == AgentStatus.error)
              IconButton(
                tooltip: 'Reactivar',
                onPressed: () => AgentManager.instance.revive(a.id),
                icon: const Icon(Icons.play_circle_rounded, size: 20),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Eliminar agente',
              onPressed: () =>
                  showDialog(context: context, builder: (_) =>
                      AlertDialog(
                        title: const Text('¿Eliminar agente?'),
                        content: Text(a.name),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('No')),
                          FilledButton(onPressed: () {
                            Navigator.pop(context);
                            AgentManager.instance.remove(a.id);
                          }, child: const Text('Eliminar')),
                        ],
                      )),
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: Colors.redAccent.withValues(alpha: .7)),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _newAgentDialog() async {
    final nameCtrl = TextEditingController();
    final missionCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    var providerId = AI_PROVIDERS.first.id;
    final perms = <AgentPermission>{
      AgentPermission.readFiles,
      AgentPermission.webAccess,
    };
    final providersWithKeys = AI_PROVIDERS
        .where((p) => KeyVault.instance.keyCount(p.id) > 0)
        .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        providerId = providersWithKeys.any((p) => p.id == providerId)
            ? providerId
            : (providersWithKeys.isNotEmpty ? providersWithKeys.first.id : providerId);
        return AlertDialog(
          title: const Text('Nuevo agente'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 8),
              TextField(controller: missionCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Misión (prompt del sistema)',
                      hintText: 'Sos el editor de GUI del motor…')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: providerId,
                items: [
                  for (final p in providersWithKeys)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setD(() => providerId = v ?? providerId),
                decoration: InputDecoration(
                    labelText: 'Proveedor',
                    helperText: providersWithKeys.isEmpty
                        ? 'Agregá una key primero en Proveedores'
                        : null),
              ),
              const SizedBox(height: 8),
              TextField(controller: modelCtrl,
                  decoration: InputDecoration(
                      labelText: 'Etiqueta de modelo',
                      hintText:
                          providerById(providerId)?.defaultModel ?? '')),
              const SizedBox(height: 8),
              ...AgentPermission.values.map((perm) => CheckboxListTile(
                    dense: true,
                    title: Text(perm.label,
                        style: const TextStyle(fontSize: 12)),
                    value: perms.contains(perm),
                    onChanged: (v) => setD(() => v == true
                        ? perms.add(perm)
                        : perms.remove(perm)),
                  )),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
          ],
        );
      }),
    );
    if (ok != true) return;
    AgentManager.instance.create(
      name: nameCtrl.text,
      mission: missionCtrl.text,
      providerId: providerId,
      model: modelCtrl.text,
      permissions: perms,
    );
    setState(() {});
  }

  // ======================================================== TAB CHAT

  Widget _chatTab() {
    final mgr = AgentManager.instance;
    final list = mgr.sorted;
    if (list.isEmpty) return const Center(child: Text('Creá un agente primero'));
    _chatAgentId ??= list.first.id;
    final a = mgr.byId(_chatAgentId!) ?? list.first;

    return Column(children: [
      Row(children: [
        Expanded(
          child: DropdownButton<String>(
            value: a.id,
            isExpanded: true,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            items: [
              for (final ag in list)
                DropdownMenuItem(
                    value: ag.id,
                    child: Text('${ag.name} · ${ag.status.name}',
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _chatAgentId = v),
          ),
        ),
        IconButton(
          tooltip: 'historial: ${a.histModo.name}',
          icon: Icon(
            switch (a.histModo) {
              HistModo.ventana => Icons.notes_rounded,
              HistModo.resumen => Icons.summarize_rounded,
              HistModo.hibrido => Icons.auto_awesome_rounded,
            },
            size: 18,
          ),
          onPressed: () => _elegirHistMode(mgr, a),
        ),
      ]),
      Expanded(child: ListView.builder(
        reverse: false,
        itemCount: a.log.length,
        itemBuilder: (_, i) {
          final m = a.log[i];
          final isTool = m.role == 'tool';
          final mine = m.role == 'user';
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * .78),
              decoration: BoxDecoration(
                color: mine
                    ? const Color(0xFF2B7CD3)
                    : isTool
                        ? Colors.amber.withValues(alpha: .1)
                        : const Color(0xFF23232A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                isTool ? '🔧 ${m.toolName}: ${m.content}' : m.content,
                style: TextStyle(fontSize: isTool ? 10 : 13),
              ),
            ),
          );
        },
      )),
      SafeArea(child: Row(children: [
        Expanded(child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
          child: TextField(
            controller: _chatCtrl,
            minLines: 1,
            maxLines: 4,
            enabled: a.status != AgentStatus.running,
            decoration: const InputDecoration(hintText: 'Tarea para el agente…',
                border: OutlineInputBorder()),
            onSubmitted: (_) => _sendTask(a),
          ),
        )),
        IconButton(icon: const Icon(Icons.send_rounded),
            onPressed: a.status == AgentStatus.running
                ? null
                : () => _sendTask(a)),
      ])),
    ]);
  }

  final TextEditingController _chatCtrl = TextEditingController();

  void _elegirHistMode(AgentManager mgr, Agent a) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Historial del agente',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          for (final m in HistModo.values)
            RadioListTile<HistModo>(
              value: m,
              groupValue: a.histModo,
              title: Text(switch (m) {
                HistModo.ventana => 'Ventana · menos tokens',
                HistModo.resumen => 'Resumen · máxima continuidad',
                HistModo.hibrido => 'Híbrido · resumen con refresco',
              }),
              subtitle: Text(switch (m) {
                HistModo.ventana =>
                  'envía los últimos mensajes que entran en el presupuesto',
                HistModo.resumen =>
                  'la parte vieja se resume con una llamada al modelo',
                HistModo.hibrido =>
                  'como resumen, pero refresca solo cuando el desborde crece',
              }),
              onChanged: (v) {
                if (v == null) return;
                mgr.setHistMode(a, v);
                Navigator.pop(sheetCtx);
              },
            ),
        ]),
      ),
    );
  }

  void _sendTask(Agent a) {
    final t = _chatCtrl.text.trim();
    if (t.isEmpty) return;
    _chatCtrl.clear();
    AgentManager.instance.talk(a.id, t);
    setState(() {});
  }
}

// ------------------------------------------------- sheet de proveedor

class _ProviderSheet extends StatefulWidget {
  final AiProvider provider;
  const _ProviderSheet({required this.provider});
  @override
  State<_ProviderSheet> createState() => _ProviderSheetState();
}

class _ProviderSheetState extends State<_ProviderSheet> {
  final _keyCtrl = TextEditingController();
  late final TextEditingController _urlCtrl =
      TextEditingController(text: KeyVault.instance.baseUrlFor(widget.provider));

  @override
  void dispose() {
    _keyCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  String _mask(String k) => k.length <= 8
      ? '••••'
      : '${k.substring(0, 4)}…${k.substring(k.length - 4)}';

  @override
  Widget build(BuildContext context) {
    final kv = KeyVault.instance;
    final keys = <String>[];
    for (var i = 0; i < 99; i++) {
      final k = kv.keyAt(widget.provider.id, i);
      if (k == null) break;
      keys.add(k);
    }
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16),
        children: [
          Text(widget.provider.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text('API keys cifradas (AES-GCM). Rotación automática ante 401/403.',
              style: TextStyle(fontSize: 11, color: Colors.white38)),
          const SizedBox(height: 10),
          for (var i = 0; i < keys.length; i++)
            ListTile(
              dense: true,
              leading: const Icon(Icons.key_rounded, size: 18),
              title: Text(_mask(keys[i]), style: const TextStyle(fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                onPressed: () {
                  kv.removeKey(widget.provider.id, i);
                  setState(() {});
                },
              ),
            ),
          Row(children: [
            Expanded(child: TextField(
              controller: _keyCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Nueva API key',
                  border: OutlineInputBorder()),
            )),
            IconButton(
              icon: const Icon(Icons.add_circle_rounded),
              onPressed: () {
                kv.addKey(widget.provider.id, _keyCtrl.text);
                _keyCtrl.clear();
                setState(() {});
              },
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: InputDecoration(
              labelText: 'Base URL',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save_rounded),
                onPressed: () {
                  kv.setBaseUrl(widget.provider.id, _urlCtrl.text);
                  FocusScope.of(context).unfocus();
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
