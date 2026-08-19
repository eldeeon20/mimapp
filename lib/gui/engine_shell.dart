import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../ai/laurelia_chat.dart';
import '../ai/toolsec_dialog.dart';
import '../lua/lua_controller.dart';
import '../lua/page_model.dart';
import '../lua/page_registry.dart';
import '../media/media_player.dart';
import '../widgets/gui_renderer.dart';

/// Shell de la app: barra de URL + lista de widgets definidos por Lua.
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
  late final MediaPlayer _mediaPlayer;
  final _urlController = TextEditingController();
  final _controller = LuaController();
  final _laurelia = LaureliaChat();

  PageModel? _page;
  String? _pageName;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _mediaPlayer = MediaPlayer();
    _controller.mediaPlayer = _mediaPlayer;
    _controller.laureliaChat = _laurelia;
    _controller.onUpdate = (_, __) => setState(() {});
    _controller.onNavigate = _loadPageByName;
    _mediaPlayer.onChanged = () {
      if (mounted) setState(() {});
    };
    _mediaPlayer.onPush = (id, value) {
      _controller.setInputValue(id, value);
      if (mounted) setState(() {});
    };
    _laurelia.onProgress = (_) {
      if (mounted) setState(() {});
    };
    _loadPageByName('demo');
  }

  Future<void> _loadPageByName(String name) async {
    final asset = PageRegistry.assetFor(name);
    if (asset == null) {
      setState(() => _error = 'Página desconocida: $name');
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
      setState(() => _page = page);
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
      setState(() {
        _page = page;
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
  void dispose() {
    _urlController.dispose();
    _controller.dispose();
    _mediaPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_page?.title ?? 'pr_app'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'ToolSec: cifrar/descifrar archivo',
            onPressed: () => showToolSecDialog(context),
          ),
          for (final name in PageRegistry.names)
            TextButton(
              onPressed: () => _loadPageByName(name),
              child: Text(name),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _page == null
                ? const Center(child: Text('Sin página cargada'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final node in _page!.body)
                        GuiRenderer.build(
                          context,
                          node,
                          values: _controller.values,
                          onInput: (id, value) {
                            _controller.setInputValue(id, value);
                            setState(() {});
                          },
                          onAction: (name) =>
                              _controller.invokeHandler(name),
                          videoController: _mediaPlayer.videoController,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
