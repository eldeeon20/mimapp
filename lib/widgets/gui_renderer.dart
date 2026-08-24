import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../lua/lua_theme.dart';
import 'gui_button.dart';
import 'gui_divider.dart';
import 'gui_grid.dart';
import 'gui_node.dart';
import 'gui_rect.dart';
import 'gui_rect_image.dart';
import 'gui_scroll.dart';
import 'gui_spacer.dart';
import 'gui_style_button.dart';
import 'gui_text.dart';
import 'gui_text_edit.dart';
import 'gui_video.dart';
import 'gui_zoom_image.dart';

/// Convierte un [GuiNode] (descrito en Lua) en su widget Flutter.
/// Flutter siempre dibuja; Lua decide estructura, estilo y layout.
class GuiRenderer {
  static Widget build(
    BuildContext context,
    GuiNode node, {
    required Map<String, String> values,
    required void Function(String id, String value) onInput,
    required void Function(String name) onAction,
    VideoController? videoController,
  }) {
    return switch (node) {
      GuiText() => _text(context, node as GuiText, values),
      GuiTextEdit() => _textEdit(node as GuiTextEdit, values, onInput),
      GuiButton() => _button(context, node as GuiButton, onAction),
      GuiStyleButton() =>
        _styleButton(context, node as GuiStyleButton, onAction),
      GuiRect() => _rect(context, node as GuiRect,
          values: values,
          onInput: onInput,
          onAction: onAction,
          videoController: videoController),
      GuiRectImage() => _rectImage(node as GuiRectImage),
      GuiDivider() => _divider(context, node as GuiDivider),
      GuiSpacer() => _spacer(node as GuiSpacer),
      GuiVideo() => _video(node as GuiVideo, videoController),
      GuiScroll() => _scroll(context, node as GuiScroll, values, onInput,
          onAction, videoController),
      GuiGrid() => _grid(context, node as GuiGrid, values, onInput, onAction,
          videoController),
      GuiZoomImage() => _zoomImage(node as GuiZoomImage),
      _ => const SizedBox.shrink(),
    };
  }

  // ---------------------------------------------------------------- text

  static Widget _text(
      BuildContext context, GuiText n, Map<String, String> values) {
    final s = n.style;
    final display =
        (s.id != null && values.containsKey(s.id)) ? values[s.id]! : s.text;
    final theme = Theme.of(context).textTheme;
    final base = n.heading ? theme.headlineSmall : theme.bodyMedium;
    final style = base?.copyWith(
      fontSize: s.font?.size,
      fontWeight: s.font?.bold == true ? FontWeight.bold : null,
      fontStyle: s.font?.italic == true ? FontStyle.italic : null,
      fontFamily: s.font?.family,
      color: _color(
        s.font?.color ?? s.color,
        n.heading ? _hexToColor(LuaTheme.instance.accent) : base?.color,
      ),
    );
    return _applyLayout(
      n,
      Text(
        display,
        style: style,
        textAlign: _textAlign(s.align),
        maxLines: s.multiline ? null : 1,
        overflow: s.multiline ? null : TextOverflow.ellipsis,
      ),
    );
  }

  // ----------------------------------------------------------- text edit

  static Widget _textEdit(
      GuiTextEdit n, Map<String, String> values, void Function(String, String) onInput) {
    final s = n.style;
    final initial =
        (s.id != null && values.containsKey(s.id)) ? values[s.id]! : n.value;
    final child = TextFormField(
      key: ValueKey('input_${s.id}'),
      initialValue: initial ?? '',
      decoration: InputDecoration(labelText: n.label ?? ''),
      onChanged: (v) {
        if (s.id != null) onInput(s.id!, v);
      },
    );
    return _applyLayout(n, child);
  }

  // --------------------------------------------------------------- button

  static Widget _button(BuildContext context, GuiButton n, void Function(String) onAction) {
    final s = n.style;
    final t = LuaTheme.instance;
    final customColor = s.color != null ? _color(s.color, Colors.transparent) : null;
    final child = DecoratedBox(
      decoration: BoxDecoration(
        gradient: customColor == null
            ? LinearGradient(colors: [
                _color(t.primary, Colors.deepPurple)!,
                _color(t.accent, Colors.cyanAccent)!,
              ])
            : null,
        color: customColor,
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: FilledButton(
        onPressed: s.onClick == null ? null : () => onAction(s.onClick!),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: s.font?.color != null
              ? _color(s.font!.color, Colors.white)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radius),
          ),
        ),
        child: Text(
          s.text,
          style: s.font?.size != null
              ? TextStyle(
                  fontSize: s.font!.size,
                  fontWeight: s.font!.bold ? FontWeight.bold : null,
                )
              : const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
    return _applyLayout(n, child);
  }

  // ---------------------------------------------------------- style button

  /// Iconos Material disponibles por nombre desde Lua.
  static const _icons = <String, IconData>{
    'star': Icons.star_rounded,
    'lock': Icons.lock_rounded,
    'key': Icons.key_rounded,
    'bolt': Icons.bolt_rounded,
    'play': Icons.play_arrow_rounded,
    'chat': Icons.chat_rounded,
    'search': Icons.search_rounded,
    'settings': Icons.settings_rounded,
    'fingerprint': Icons.fingerprint_rounded,
    'memory': Icons.memory_rounded,
    'hub': Icons.hub_rounded,
    'brain': Icons.psychology_rounded,
    'eye': Icons.visibility_rounded,
    'split': Icons.call_split_rounded,
    'download': Icons.download_rounded,
    'upload': Icons.upload_rounded,
    'refresh': Icons.refresh_rounded,
    'close': Icons.close_rounded,
    'add': Icons.add_rounded,
    'delete': Icons.delete_outline_rounded,
    'home': Icons.home_rounded,
    'tab': Icons.tab_rounded,
    'link': Icons.link_rounded,
    'share': Icons.share_rounded,
    'copy': Icons.copy_rounded,
    'send': Icons.send_rounded,
    'stop': Icons.stop_circle_rounded,
    'image': Icons.image_rounded,
    'folder': Icons.folder_open_rounded,
    'shield': Icons.shield_rounded,
  };

  static Widget _styleButton(
    BuildContext context,
    GuiStyleButton n,
    void Function(String) onAction,
  ) {
    final s = n.style;
    final t = LuaTheme.instance;
    final custom = s.color != null ? _color(s.color, Colors.transparent) : null;
    final icon = n.icon.isEmpty ? null : _icons[n.icon.toLowerCase()];
    final child = DecoratedBox(
      decoration: BoxDecoration(
        gradient: custom == null
            ? LinearGradient(colors: [
                _color(t.primary, Colors.deepPurple)!,
                _color(t.accent, Colors.cyanAccent)!,
              ])
            : null,
        color: custom,
        borderRadius: BorderRadius.circular(t.radius),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: FilledButton.icon(
        onPressed: s.onClick == null ? null : () => onAction(s.onClick!),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: s.font?.color != null
              ? _color(s.font!.color, Colors.white)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radius),
          ),
        ),
        icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
        label: Text(
          s.text,
          style: TextStyle(
            fontSize: s.font?.size,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
    return _applyLayout(n, child);
  }

  // ----------------------------------------------------------------- rect

  static Widget _rect(
    BuildContext context,
    GuiRect n, {
    required Map<String, String> values,
    required void Function(String, String) onInput,
    required void Function(String) onAction,
    VideoController? videoController,
  }) {
    final s = n.style;
    final textStyle = (s.font?.size != null ||
            s.font?.bold == true ||
            s.font?.italic == true ||
            s.font?.color != null ||
            s.color != null)
        ? TextStyle(
            fontSize: s.font?.size,
            fontWeight: s.font?.bold == true ? FontWeight.bold : null,
            fontStyle: s.font?.italic == true ? FontStyle.italic : null,
            fontFamily: s.font?.family,
            color: _color(s.font?.color ?? s.color, null),
          )
        : null;
    final child = Container(
      decoration: BoxDecoration(
        color:
            n.bgColor != null ? _color(n.bgColor, Colors.transparent) : null,
        borderRadius: BorderRadius.circular(n.radius > 0 ? n.radius : 0),
        border: n.borderWidth > 0
            ? Border.all(
                color: _color(n.borderColor, Colors.grey),
                width: n.borderWidth,
              )
            : null,
        boxShadow: (n.children.isNotEmpty || s.text.isNotEmpty)
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .25),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      padding: n.children.isNotEmpty
          ? const EdgeInsets.all(10)
          : null,
      child: n.children.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.text.isNotEmpty)
                  Text(s.text,
                      textAlign: _textAlign(s.align), style: textStyle),
                for (final c in n.children) build(context, c, values: values, onInput: onInput, onAction: onAction, videoController: videoController),
              ],
            )
          : (s.text.isEmpty
              ? null
              : Text(s.text,
                  textAlign: _textAlign(s.align), style: textStyle)),
    );
    return _applyLayout(n, child);
  }

  // --------------------------------------------------------- rect image

  static Widget _rectImage(GuiRectImage n) {
    final s = n.style;
    final fit = switch (n.fit?.toLowerCase()) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      _ => BoxFit.cover,
    };
    Widget child;
    if (n.src == null || n.src!.isEmpty) {
      child = Container(
        color: Colors.black12,
        child: const Center(child: Text('sin imagen')),
      );
    } else {
      child = Image.network(
        n.src!,
        fit: fit,
        loadingBuilder: (context, widget, progress) =>
            progress == null ? widget : const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.black12,
          child: const Center(child: Text('error de imagen')),
        ),
      );
    }
    return _applyLayout(n, child);
  }

  // -------------------------------------------------------------- divider

  static Widget _divider(BuildContext context, GuiDivider n) {
    final s = n.style;
    return _applyLayout(
      n,
      Divider(
        height: s.height ?? 24,
        color: s.color != null ? _color(s.color, Colors.transparent) : null,
      ),
    );
  }

  // --------------------------------------------------------------- spacer

  static Widget _spacer(GuiSpacer n) =>
      _applyLayout(n, SizedBox(height: n.space));

  // --------------------------------------------------------------- video

  static Widget _video(GuiVideo n, VideoController? videoController) {
    final s = n.style;
    final child = videoController == null
        ? Container(
            color: Colors.black12,
            child: const Center(child: Text('reproductor no disponible')),
          )
        : Video(controller: videoController);
    return _applyLayout(n, child);
  }

  // -------------------------------------------------------------- scroll

  static Widget _scroll(
    BuildContext context,
    GuiScroll n,
    Map<String, String> values,
    void Function(String, String) onInput,
    void Function(String) onAction,
    VideoController? videoController,
  ) {
    final h = n.style.height ?? 320.0;
    return _applyLayout(
      n,
      SizedBox(
        height: h,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in n.children)
                build(context, c,
                    values: values,
                    onInput: onInput,
                    onAction: onAction,
                    videoController: videoController),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- grid

  static Widget _grid(
    BuildContext context,
    GuiGrid n,
    Map<String, String> values,
    void Function(String, String) onInput,
    void Function(String) onAction,
    VideoController? videoController,
  ) {
    return _applyLayout(
      n,
      GridView.count(
        crossAxisCount: n.columns.clamp(1, 6),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: (n.style.width ?? 2.4),
        children: [
          for (final c in n.children)
            build(context, c,
                values: values,
                onInput: onInput,
                onAction: onAction,
                videoController: videoController),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- zoom image

  static Widget _zoomImage(GuiZoomImage n) {
    final s = n.style;
    final fit = switch (n.fit?.toLowerCase()) {
      'cover' => BoxFit.cover,
      'fill' => BoxFit.fill,
      _ => BoxFit.contain,
    };
    final image = (n.src == null || n.src!.isEmpty)
        ? Container(color: Colors.black12, height: 160)
        : Image.network(
            n.src!,
            fit: fit,
            loadingBuilder: (context, widget, progress) => progress == null
                ? widget
                : const Center(child: CircularProgressIndicator()),
            errorBuilder: (_, __, ___) =>
                Container(color: Colors.black12, height: 160),
          );
    return _applyLayout(
      n,
      SizedBox(
        height: s.height ?? 260,
        child: InteractiveViewer(maxScale: 6, child: Center(child: image)),
      ),
    );
  }

  // ------------------------------------------------------------- helpers

  /// Aplica padding, tamaño y alineación definidos en Lua.
  static Widget _applyLayout(GuiNode n, Widget child) {
    final s = n.style;
    if (s.padding > 0) {
      child = Padding(padding: EdgeInsets.all(s.padding), child: child);
    }
    if (s.width != null || s.height != null) {
      child = SizedBox(width: s.width, height: s.height, child: child);
    }
    if (s.align != null) {
      final alignment = switch (s.align) {
        'center' => Alignment.center,
        'right' => Alignment.centerRight,
        _ => Alignment.centerLeft,
      };
      child = Align(alignment: alignment, child: child);
    }
    return child;
  }

  static TextAlign? _textAlign(String? a) => switch (a) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        _ => null,
      };

  static Color _color(String? name, Color? fallback) {
    final f = fallback ?? Colors.black;
    if (name == null) return f;
    final hex = _hexToColor(name);
    if (hex != null) return hex;
    switch (name.toLowerCase()) {
      case 'white':
        return Colors.white;
      case 'black':
        return Colors.black;
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'grey' || 'gray':
        return Colors.grey;
      case 'indigo':
        return Colors.indigo;
      case 'orange':
        return Colors.orange;
      case 'teal':
        return Colors.teal;
      case 'amber':
        return Colors.amber;
      case 'transparent':
        return Colors.transparent;
    }
    return f;
  }

  static Color? _hexToColor(String s) {
    final m = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(s.trim());
    if (m == null) return null;
    final v = int.parse(m.group(1)!, radix: 16);
    return m.group(1)!.length == 8 ? Color(v) : Color(0xFF000000 | v);
  }
}
