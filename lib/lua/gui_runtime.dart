import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../widgets/gui_node.dart';
import '../widgets/gui_renderer.dart';
import '../widgets/gui_text.dart';
import 'state_store.dart';

/// Corazón de la nueva capa: separa STRUCTURAL de VALUE.
///
///   assets/pages/*.lua
///          │
///     LuaController  -> PageModel (estructura)
///          │
///          ▼
///   GuiRuntime
///     ├── GuiTree   (lista de GuiNode, cambia solo en navigate/load)
///     ├── StateStore (valores por id; cambia en cada engine_set)
///     └── build()   (inicial)  -> Flutter Widgets
///                      │
///                 value patch: StateStore.set(id)
///                      │
///                 solo el _BoundWidget(id) se reconstruye
///
/// `GuiRenderer` solo se usa para construir la FORMA de cada nodo; los
/// nodos con `id`/`bind` se envuelven en [_BoundWidget], que escucha el
/// notifier de esa clave y se repinta a sí mismo (sin setState del árbol).
class GuiRuntime {
  /// Mismo store que usa [LuaController] (engine_set escribe aquí y los
  /// nodos enlazados escuchan aquí). Se comparte para que ambos vean lo mismo.
  final StateStore store;
  List<GuiNode> _nodes = const [];

  GuiRuntime({StateStore? store}) : store = store ?? StateStore();

  /// Cambio ESTRUCTURAL (navigate / load). El widget padre debe reconstruir
  /// (setState), pero esto es raro, no por cada engine_set.
  void setTree(List<GuiNode> nodes) {
    store.clear();
    _nodes = nodes;
  }

  List<GuiNode> get nodes => _nodes;

  /// Construye el árbol una vez. Los nodos con id/bind se vuelven
  /// [_BoundWidget] que se actualizan solos ante StateStore.set.
  Widget build(
    BuildContext context, {
    required void Function(String id, String value) onInput,
    required void Function(String name) onAction,
    VideoController? videoController,
  }) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final node in _nodes)
          _buildNode(
            context,
            node,
            onInput: onInput,
            onAction: onAction,
            videoController: videoController,
          ),
      ],
    );
  }

  Widget _buildNode(
    BuildContext context,
    GuiNode node, {
    required void Function(String id, String value) onInput,
    required void Function(String name) onAction,
    VideoController? videoController,
  }) {
    // Binding dirigido: solo text/heading (los que muestran valores vivos).
    final key = node.style.id ?? node.style.bind;
    if (key != null && node is GuiText) {
      return _BoundWidget(
        store: store,
        id: key,
        node: node,
        onInput: onInput,
        onAction: onAction,
        videoController: videoController,
      );
    }
    // El resto (button, input, video, rect, image, divider, spacer) se
    // construye una vez; el input lee su valor inicial del snapshot.
    return GuiRenderer.build(
      context,
      node,
      values: store.values,
      onInput: onInput,
      onAction: onAction,
      videoController: videoController,
    );
  }
}

/// Widget que escucha UNA clave del [StateStore] y se reconstruye solo a sí
/// mismo cuando esa clave cambia. No provoca rebuild del árbol padre.
class _BoundWidget extends StatelessWidget {
  final StateStore store;
  final String id;
  final GuiText node;
  final void Function(String id, String value) onInput;
  final void Function(String name) onAction;
  final VideoController? videoController;

  const _BoundWidget({
    required this.store,
    required this.id,
    required this.node,
    required this.onInput,
    required this.onAction,
    this.videoController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store.listenableFor(id),
      builder: (_, __) => GuiRenderer.build(
        context,
        node,
        values: {id: store.get(id)},
        onInput: onInput,
        onAction: onAction,
        videoController: videoController,
      ),
    );
  }
}
