import 'dart:convert';

/// Tema de la GUI Lua, controlable en caliente desde una página:
/// ```lua
/// theme_apply{ preset = "neon" }
/// theme_apply{ primary = "#FF00AA", radius = 16 }
/// ```
/// El renderer lee [LuaTheme.instance] para los defaults visuales
/// (botones con gradiente primario→acento, headings coloreados, cards).
class LuaTheme {
  static final LuaTheme instance = LuaTheme._();

  LuaTheme._();

  String preset = 'dark';
  String primary = '#7C4DFF';
  String accent = '#22D3EE';
  String surface = '#0B1226';
  String textMuted = '#94A3B8';
  double radius = 14;

  /// Aplica un preset o campos sueltos (mapa crudo desde Lua).
  void apply(Map<String, Object?> p) {
    final presetName = p['preset'] as String?;
    if (presetName != null && _presets.containsKey(presetName)) {
      final ps = _presets[presetName]!;
      primary = ps['primary'] as String;
      accent = ps['accent'] as String;
      surface = ps['surface'] as String;
      textMuted = ps['text_muted'] as String;
      radius = (ps['radius'] as num).toDouble();
      preset = presetName;
    }
    // overrides puntuales
    for (final k in ['primary', 'accent', 'surface', 'text_muted']) {
      final v = p[k] as String?;
      if (v != null) {
        switch (k) {
          case 'primary':
            primary = v;
          case 'accent':
            accent = v;
          case 'surface':
            surface = v;
          case 'text_muted':
            textMuted = v;
        }
      }
    }
    if (p['radius'] is num) {
      radius = (p['radius'] as num).toDouble();
    }
  }

  static const _presets = <String, Map<String, Object>>{
    'dark': {
      'primary': '#7C4DFF',
      'accent': '#22D3EE',
      'surface': '#0B1226',
      'text_muted': '#94A3B8',
      'radius': 14,
    },
    'neon': {
      'primary': '#FF2BD6',
      'accent': '#00F0FF',
      'surface': '#12001F',
      'text_muted': '#E9D5FF',
      'radius': 20,
    },
    'terminal': {
      'primary': '#22C55E',
      'accent': '#A3E635',
      'surface': '#04140A',
      'text_muted': '#86EFAC',
      'radius': 4,
    },
    'ocean': {
      'primary': '#38BDF8',
      'accent': '#FDE047',
      'surface': '#061826',
      'text_muted': '#BAE6FD',
      'radius': 16,
    },
  };

  /// Serialización compacta para debug/logs.
  @override
  String toString() =>
      jsonEncode({'preset': preset, 'primary': primary, 'accent': accent});
}
