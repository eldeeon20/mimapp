import 'gui_node.dart';

/// Rectángulo/contenedor con fondo, borde y children opcionales. En Lua:
/// ```lua
/// gui_rect{ bg_color="#112", radius=12, children={ gui_text{...} } }
/// ```
class GuiRect extends GuiNode {
  final List<GuiNode> children;
  final String? bgColor;
  final String? borderColor;
  final double radius;
  final double borderWidth;

  GuiRect({
    required super.style,
    this.children = const [],
    this.bgColor,
    this.borderColor,
    this.radius = 0,
    this.borderWidth = 0,
  }) : super(type: 'rect');

  factory GuiRect.fromMap(Map<String, Object?> m) => GuiRect(
        style: GuiNode.parseStyle(m),
        children: GuiNode.parseChildren(m),
        bgColor: m['bg_color'] as String?,
        borderColor: m['border_color'] as String?,
        radius: (m['radius'] as num?)?.toDouble() ?? 0,
        borderWidth: (m['border_width'] as num?)?.toDouble() ?? 0,
      );
}
