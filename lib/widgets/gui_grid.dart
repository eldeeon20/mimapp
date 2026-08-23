import 'gui_node.dart';

/// Grilla de children. En Lua:
/// ```lua
/// gui_grid{ columns = 2, children = { gui_button{...}, ... } }
/// ```
class GuiGrid extends GuiNode {
  final int columns;
  final List<GuiNode> children;

  GuiGrid({
    required super.style,
    this.columns = 2,
    this.children = const [],
  }) : super(type: 'grid');

  factory GuiGrid.fromMap(Map<String, Object?> m) => GuiGrid(
        style: GuiNode.parseStyle(m),
        columns: (m['columns'] as num?)?.toInt() ?? 2,
        children: GuiNode.parseChildren(m),
      );
}
