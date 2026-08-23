import 'gui_node.dart';

/// Área scrolleable anidada. En Lua:
/// ```lua
/// gui_scroll{ height = 300, children = { gui_text{...}, ... } }
/// ```
class GuiScroll extends GuiNode {
  final List<GuiNode> children;

  GuiScroll({required super.style, this.children = const []})
      : super(type: 'scroll');

  factory GuiScroll.fromMap(Map<String, Object?> m) => GuiScroll(
        style: GuiNode.parseStyle(m),
        children: GuiNode.parseChildren(m),
      );
}
