import 'gui_node.dart';

/// Imagen con pinch-zoom (InteractiveViewer). En Lua:
/// ```lua
/// gui_zoom_image{ src = "https://...", height = 260, fit = "contain" }
/// ```
class GuiZoomImage extends GuiNode {
  final String? src;
  final String? fit;

  GuiZoomImage({required super.style, this.src, this.fit})
      : super(type: 'zoom_image');

  factory GuiZoomImage.fromMap(Map<String, Object?> m) => GuiZoomImage(
        style: GuiNode.parseStyle(m),
        src: m['src'] as String?,
        fit: m['fit'] as String?,
      );
}
