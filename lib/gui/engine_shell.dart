import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pr_app/src/rust/frb_generated.dart';

import '../colab_cli/colab_dialog.dart';
import '../lua/lua_controller.dart';
import '../lua/page_model.dart';
import '../lua/page_registry.dart';
import '../lua/gui_runtime.dart';
import '../media/media_player.dart';
import '../toolsec/toolsec_dialog.dart';
import '../ai/laurelia_chat.dart';
import '../screens/ai_screen.dart';
import '../screens/media_screen.dart';

/// Shell principal: home con 3 herramientas + ToolSec/Colab en AppBar.
class PrApp extends StatelessWidget {
  const PrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pr_app',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const EngineShell(),
    );
  }
}

class EngineShell extends StatefulWidget {
  const EngineShell({super.key});

  @override
  State<EngineShell> createState() => _EngineShellState();
}

class _EngineShellState extends State<EngineShell> {
  int _currentIndex = -1; // -1 = home

  // Servicios compartidos (viven mientras la app viva)
  late final MediaPlayer _mediaPlayer;
  late final LaureliaChat _laurelia;

  @override
  void initState() {
    super.initState();
    _mediaPlayer = MediaPlayer();
    _laurelia = LaureliaChat();
  }

  @override
  void dispose() {
    _mediaPlayer.dispose();
    super.dispose();
  }

  void _openTool(int index) => setState(() => _currentIndex = index);
  void _goHome() => setState(() => _currentIndex = -1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        leading: _currentIndex >= 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goHome,
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'ToolSec: cifrar/descifrar',
            onPressed: () => showToolSecDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.cloud_outlined),
            tooltip: 'Google Colab',
            onPressed: () => showColabDialog(context),
          ),
        ],
      ),
      body: _currentIndex < 0
          ? _buildHome()
          : _buildTool(_currentIndex),
    );
  }

  static const _titles = ['pr_app', 'Lua', 'Media', 'Laurelia AI'];

  Widget _buildHome() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Herramientas',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ToolCard(
                  icon: Icons.code,
                  label: 'Lua',
                  color: Colors.orange,
                  onTap: () => _openTool(1),
                ),
                const SizedBox(width: 24),
                _ToolCard(
                  icon: Icons.music_note,
                  label: 'Media',
                  color: Colors.teal,
                  onTap: () => _openTool(2),
                ),
                const SizedBox(width: 24),
                _ToolCard(
                  icon: Icons.smart_toy,
                  label: 'Laurelia',
                  color: Colors.purple,
                  onTap: () => _openTool(3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTool(int index) {
    switch (index) {
      case 1:
        return _LuaTool(
          mediaPlayer: _mediaPlayer,
          laurelia: _laurelia,
        );
      case 2:
        return MediaScreen(mediaPlayer: _mediaPlayer);
      case 3:
        return AiScreen(laurelia: _laurelia);
      default:
        return const Center(child: Text('??'));
    }
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        child: SizedBox(
          width: 120,
          height: 120,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Herramienta Lua. Ya NO es el "engine": solo orquesta [LuaController] y
/// [GuiRuntime]. Los valores (engine_set) actualizan solo el nodo enlazado;
/// aquí solo hacemos setState en cambios ESTRUCTURALES (navigate/load).
class _LuaTool extends StatefulWidget {
  final MediaPlayer mediaPlayer;
  final LaureliaChat laurelia;

  const _LuaTool({required this.mediaPlayer, required this.laurelia});

  @override
  State<_LuaTool> createState() => _LuaToolState();
}

class _LuaToolState extends State<_LuaTool> {
  final _controller = LuaController();
  late final GuiRuntime _runtime;
  final _urlController = TextEditingController();
  String? _pageName;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Mismo store: engine_set escribe y los nodos enlazados escuchan.
    _runtime = GuiRuntime(store: _controller.store);
    _controller.mediaPlayer = widget.mediaPlayer;
    _controller.laureliaChat = widget.laurelia;
    _controller.onNavigate = _loadPageByName;
    // El player empuja valores al store (sin setState global). El renderer
    // de ese nodo se repinta solo.
    widget.mediaPlayer.onPush = (id, value) =>
        _controller.setInputValue(id, value);
    // Laurelia ya escribe en el store desde el controller; nada que hacer aquí.
    widget.laurelia.onProgress = null;
    _loadPageByName('demo');
  }

  @override
  void dispose() {
    _urlController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPageByName(String name) async {
    final asset = PageRegistry.assetFor(name);
    if (asset == null) {
      setState(() => _error = 'Página: $name');
      return;
    }
    await _loadFromAsset(asset);
    if (mounted) setState(() => _pageName = name);
  }

  Future<void> _loadFromAsset(String asset) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _controller.loadFromAsset(asset);
      if (!mounted) return;
      // STRUCTURAL: cambia el árbol (raro, no por cada engine_set).
      _runtime.setTree(page.body);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _controller.loadFromUrl(url);
      if (!mounted) return;
      _runtime.setTree(page.body);
      setState(() {
        _pageName = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cargar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: 'URL de una página Lua…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _loadFromUrl(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _loading ? null : _loadFromUrl,
                child: const Text('Cargar'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _loading ? null : () => _loadPageByName('demo'),
                child: const Text('Demo'),
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: _runtime.nodes.isEmpty
              ? const Center(child: Text('Sin página'))
              : _runtime.build(
                  context,
                  onInput: (id, value) => _controller.setInputValue(id, value),
                  onAction: (name) => _controller.invokeHandler(name),
                  videoController: widget.mediaPlayer.videoController,
                ),
        ),
      ],
    );
  }
}
