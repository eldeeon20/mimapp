import 'gui_node.dart';

/// Botón custom con gradiente + icono Material (por nombre). En Lua:
/// ```lua
/// gui_style_button{ text="Firmar", icon="fingerprint", color="#22D3EE",
///                   on_click="firmar" }
/// ```
/// Sin [color] usa el gradiente primario→acento del tema Lua.
class GuiStyleButton extends GuiNode {
  final String icon;

  GuiStyleButton({required super.style, this.icon = ''})
      : super(type: 'style_button');

  factory GuiStyleButton.fromMap(Map<String, Object?> m) => GuiStyleButton(
        style: GuiNode.parseStyle(m),
        icon: m['icon'] as String? ?? '',
      );
}
