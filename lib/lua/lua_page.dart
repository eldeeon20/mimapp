import 'package:flutter/material.dart';

import '../ai/laurelia_chat.dart';
import '../media/media_player.dart';
import '../services/history_store.dart';
import '../services/settings.dart';
import 'gui_runtime.dart';
import 'lua_controller.dart';
import 'lua_theme.dart';
import 'page_model.dart';
import 'page_router.dart';
import 'web_home.dart';

/// Shell de la web Lua: sistema de PESTAÑAS (badge numerado + panel
/// lateral derecho deslizable), barra superior con botón de volver a la
/// app, y canvas donde cada página dibuja lo que su script decida.
///
/// El modo claro/oscuro sale del parámetro global en Ajustes
/// (Settings.webDarkMode) y se aplica con Theme.
class LuaPage extends StatefulWidget {
  final MediaPlayer mediaPlayer;
  final LaureliaChat laurelia;

  const LuaPage({super.key, required this.mediaPlayer, required this.laurelia});

  @override
  State<LuaPage> createState() => _LuaPageState();
}

/// Una pestaña web abierta: página cargada + snapshot de valores.
class _WebTab {
  final String uri;
  String title;
  PageModel? model;
  Map<String, String> values = {};

  _WebTab({required this.uri, this.title = '…', this.model});
}

class _LuaPageState extends State<LuaPage> {
  late final GuiRuntime _runtime;
  late final LuaController _controller;

  bool _loading = false;
  String? _error;

  final List<_WebTab> _tabs = [];
  int _activeIndex = -1; // -1 = inicio

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _controller = LuaController();
    _runtime = GuiRuntime(store: _controller.store);
    _controller.mediaPlayer = widget.mediaPlayer;
    _controller.laureliaChat = widget.laurelia;
    _controller.onNavigate = _openUri;
    HistoryStore.instance.load();
    widget.mediaPlayer.onPush =
        (id, value) => _controller.setInputValue(id, value);
    widget.laurelia.onProgress = null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ navegación

  Future<void> _openUri(String uri) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final src = await _controller.router.resolve(uri);
      final model = _controller.load(src.code);
      if (!mounted) return;
      setState(() {
        _tabs.add(_WebTab(uri: src.uri, title: model.title, model: model));
        _activateTab(_tabs.length - 1);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _activateTab(int i) {
    if (i >= 0 && i < _tabs.length) {
      _runtime.setTree(_tabs[i].model!.body);
      for (final e in _tabs[i].values.entries) {
        _controller.setInputValue(e.key, e.value);
      }
    }
    _activeIndex = i;
  }

  void _switchTab(int i) => setState(() => _activateTab(i));

  void _closeTab(int i) {
    setState(() {
      _tabs.removeAt(i);
      if (_tabs.isEmpty) {
        _activeIndex = -1;
        _runtime.setTree(const []);
      } else if (_activeIndex >= _tabs.length) {
        _activateTab(_tabs.length - 1);
      } else if (_activeIndex == i) {
        _activateTab(_activeIndex);
      }
    });
  }

  void _goHome() {
    if (_activeIndex >= 0 && _activeIndex < _tabs.length) {
      _tabs[_activeIndex].values = Map.of(_controller.store.values);
    }
    setState(() => _activeIndex = -1);
  }

  /// Intercepta acciones: los links generan "__nav__ <uri>" → router.
  void _onAction(String name) {
    if (name.startsWith('__nav__')) {
      final href = name.substring('__nav__'.length).trim();
      if (href.isNotEmpty) _openUri(href);
      return;
    }
    _controller.invokeHandler(name);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final dark = Settings.instance.webDarkMode;
    final bg = dark ? const Color(0xFF020617) : const Color(0xFFF4F6FB);
    final fg = dark ? Colors.white : Colors.black87;

    return Theme(
      data: dark ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: bg,
        endDrawer: _tabsDrawer(fg),
        drawerEdgeDragWidth: 60,
        body: SafeArea(
          child: GestureDetector(
            // gesto: arrastre desde el borde derecho abre el panel de pestañas
            onHorizontalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -250) {
                _scaffoldKey.currentState?.openEndDrawer();
              }
            },
            child: Column(children: [
              _topBar(dark, fg),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.withValues(alpha: .15),
                  child: Text(_error!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: Colors.red[200])),
                ),
              Expanded(child: _homeOrPage()),
            ]),
          ),
        ),
      ),
    );
  }

  /// Barra superior: volver al menú de la app con NRO DE PESTAÑAS,
  /// título activo (tap = inicio), y acceso al panel lateral derecho.
  Widget _topBar(bool dark, Color fg) {
    final active = _activeIndex >= 0 && _activeIndex < _tabs.length
        ? _tabs[_activeIndex]
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0B1226) : Colors.white,
        border: Border(
          bottom: BorderSide(color: dark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Row(children: [
        Badge(
          isLabelVisible: _tabs.isNotEmpty,
          label: Text('${_tabs.length}'),
          backgroundColor: Colors.deepPurpleAccent,
          child: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: fg),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Volver al menú ($_tabsCount pestañas)',
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: _goHome,
            behavior: HitTestBehavior.opaque,
            child: Text(
              active?.title ?? 'inicio · pr_web',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: fg.withValues(alpha: .85)),
            ),
          ),
        ),
        IconButton(
          icon: Badge(
            isLabelVisible: _tabs.isNotEmpty,
            label: Text('${_tabs.length}'),
            backgroundColor: Colors.cyanAccent,
            textColor: Colors.black,
            child: Icon(Icons.tab_rounded, color: fg),
          ),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          tooltip: 'Pestañas web',
        ),
      ]),
    );
  }

  int get _tabsCount => _tabs.length;

  Widget _homeOrPage() {
    if (_activeIndex >= 0 && _activeIndex < _tabs.length) {
      return _runtime.build(
        context,
        onInput: (id, value) => _controller.setInputValue(id, value),
        onAction: _onAction,
        videoController: widget.mediaPlayer.videoController,
      );
    }
    return WebHome(onOpenUri: _openUri, refresh: () => setState(() {}));
  }

  // ------------------------------------------------------- panel lateral

  Widget _tabsDrawer(Color fg) {
    final dark = Settings.instance.webDarkMode;
    return Drawer(
      backgroundColor: dark ? const Color(0xFF070D1D) : Colors.white,
      child: SafeArea(
        child: ListView(padding: EdgeInsets.zero, children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('PESTAÑAS WEB (${_tabs.length})',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: fg.withValues(alpha: .6))),
          ),
          if (_tabs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Sin pestañas abiertas.',
                  style:
                      TextStyle(fontSize: 12, color: fg.withValues(alpha: .4))),
            ),
          for (var i = 0; i < _tabs.length; i++)
            ListTile(
              selected: i == _activeIndex,
              leading: Icon(Icons.tab_rounded,
                  color: i == _activeIndex
                      ? Colors.cyanAccent
                      : fg.withValues(alpha: .5)),
              title: Text(_tabs[i].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_tabs[i].uri,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10)),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => _closeTab(i),
              ),
              onTap: () {
                _switchTab(i);
                Navigator.pop(context);
              },
            ),
          if (_tabs.isNotEmpty)
            ListTile(
              leading: Icon(Icons.delete_sweep_rounded,
                  color: Colors.redAccent.withValues(alpha: .8)),
              title: Text('Cerrar todas',
                  style: TextStyle(color: fg.withValues(alpha: .8))),
              onTap: () {
                setState(() {
                  _tabs.clear();
                  _activeIndex = -1;
                  _runtime.setTree(const []);
                });
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
  }
}
