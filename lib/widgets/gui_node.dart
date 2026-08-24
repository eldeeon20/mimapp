import 'gui_button.dart';
import 'gui_divider.dart';
import 'gui_font.dart';
import 'gui_grid.dart';
import 'gui_rect.dart';
import 'gui_rect_image.dart';
import 'gui_scroll.dart';
import 'gui_spacer.dart';
import 'gui_style_button.dart';
import 'gui_text.dart';
import 'gui_text_edit.dart';
import 'gui_video.dart';
import 'gui_zoom_image.dart';

/// Estilo/layout común a todo nodo de la GUI, leído desde Lua.
typedef NodeStyle = ({
  String? id,
  String? bind,
  String text,
  String? align,
  double? width,
  double? height,
  double padding,
  GuiFont? font,
  String? color,
  String? onClick,
  bool multiline,
});

/// Nodo de la GUI: modelo puro (sin dependencias de Flutter) que describe
/// un widget definido en Lua.
///
/// Cada tipo concreto (botón, input, texto, rect, imagen, ...) es una
/// subclase en un archivo propio.
abstract class GuiNode {
  final String type;
  final NodeStyle style;

  GuiNode({required this.type, required this.style});

  /// Crea la subclase correcta a partir de los campos leídos de Lua.
  factory GuiNode.fromMap(Map<String, Object?> m) {
    final t = (m['type'] as String?) ?? 'text';
    return switch (t) {
      'button' => GuiButton.fromMap(m),
      'style_button' => GuiStyleButton.fromMap(m),
      'input' || 'text_edit' || 'textfield' => GuiTextEdit.fromMap(m),
      'heading' => GuiText.fromMap(m, heading: true),
      'rect' || 'card' => GuiRect.fromMap(m),
      'image' || 'rect_image' => GuiRectImage.fromMap(m),
      'divider' => GuiDivider.fromMap(m),
      'spacer' => GuiSpacer.fromMap(m),
      'video' => GuiVideo.fromMap(m),
      'grid' => GuiGrid.fromMap(m),
      'scroll' => GuiScroll.fromMap(m),
      'zoom_image' => GuiZoomImage.fromMap(m),
      _ => GuiText.fromMap(m),
    };
  }

  /// Lee `children = { tabla, tabla, ... }` recursivamente.
  static List<GuiNode> parseChildren(Map<String, Object?> m) {
    final raw = m['children'];
    if (raw is! List) return const [];
    return [
      for (final c in raw)
        if (c is Map<String, Object?>) GuiNode.fromMap(c),
    ];
  }

  /// Extrae los campos de estilo/layout comunes desde el mapa Lua.
  static NodeStyle parseStyle(Map<String, Object?> m) => (
        id: m['id'] as String?,
        bind: m['bind'] as String?,
        text: m['text'] as String? ?? '',
        align: m['align'] as String?,
        width: (m['width'] as num?)?.toDouble(),
        height: (m['height'] as num?)?.toDouble(),
        padding: (m['padding'] as num?)?.toDouble() ?? 0,
        font: GuiFont.fromMap(
          m['font'] is Map<String, Object?>
              ? m['font']! as Map<String, Object?>
              : null,
        ),
        color: m['color'] as String?,
        onClick: m['on_click'] as String?,
        multiline: m['multiline'] == true,
      );
}
