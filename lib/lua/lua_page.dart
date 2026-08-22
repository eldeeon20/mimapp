import 'package:flutter/material.dart';

import '../ai/laurelia_chat.dart';
import '../lua/lua_controller.dart';
import '../lua/gui_runtime.dart';
import '../lua/page_model.dart';
import '../lua/page_registry.dart';
import '../media/media_player.dart';

/// Herramienta Lua (variante de _LuaTool en engine_shell). Orquesta
/// [LuaController] + [GuiRuntime]; los valores actualizan solo el nodo
/// enlazado, no todo el árbol.
class LuaPage extends StatefulWidget {
  final MediaPlayer mediaPlayer;
  final LaureliaChat laurelia;

  const LuaPage({super.key, required this.mediaPlayer, required this.laurelia});

  @override
  State<LuaPage> createState() => _LuaPageState();
}

class _LuaPageState extends State<LuaPage> {
  final _controller = LuaController();
  late final GuiRuntime _runtime;
  final _urlController = TextEditingController();
  String? _pageName;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runtime = GuiRuntime(store: _controller.store);
    _controller.mediaPlayer = widget.mediaPlayer;
    _controller.laureliaChat = widget.laurelia;
    _controller.onNavigate = _loadPageByName;
    widget.mediaPlayer.onPush =
        (id, value) => _controller.setInputValue(id, value);
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
      setState(() => _pageName = null);
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
                  onInput: (id, value) =>
                      _controller.setInputValue(id, value),
                  onAction: (name) => _controller.invokeHandler(name),
                  videoController: widget.mediaPlayer.videoController,
                ),
        ),
      ],
    );
  }
}
