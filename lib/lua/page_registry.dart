import 'package:flutter/services.dart';

/// Registro de páginas Lua del bundle: nombre -> asset.
///
/// Desde Lua se navega con `navigate("player")`, `navigate("demo")`, etc.
/// El PageRouter resuelve `lua://nombre` acá.
class PageRegistry {
  static const Map<String, String> pages = {
    'demo': 'assets/pages/demo.lua',
    'player': 'assets/pages/player.lua',
    'laurelia': 'assets/pages/laurelia.lua',
    'shamir_lab': 'assets/pages/shamir_lab.lua',
    'kem_lab': 'assets/pages/kem_lab.lua',
    'gpu_lab': 'assets/pages/gpu_lab.lua',
    'hf_browser': 'assets/pages/hf_browser.lua',
    'nostr_dm_lab': 'assets/pages/nostr_dm_lab.lua',
    'nostr_obs_lab': 'assets/pages/nostr_obs_lab.lua',
  };

  /// Path del asset o null si no existe.
  static String? assetPath(String name) => pages[name];

  /// Nombres en orden, para poder mostrar en la UI.
  static List<String> get names => pages.keys.toList();
}

/// Metadata de recomendados para el inicio (icono/color/descr por página).
class PageRegistryMeta {
  static const List<Map<String, String>> all = [
    {
      'name': 'demo',
      'title': 'Demo GUI',
      'icon': 'widgets',
      'color': '#22D3EE',
      'desc': 'Tour de widgets y handlers',
    },
    {
      'name': 'player',
      'title': 'Player',
      'icon': 'play',
      'color': '#A78BFA',
      'desc': 'Reproductor media_kit controlado desde Lua',
    },
    {
      'name': 'laurelia',
      'title': 'Laurelia IA',
      'icon': 'psychology',
      'color': '#34D399',
      'desc': 'Chat LLM local desde una página',
    },
    {
      'name': 'gpu_lab',
      'title': 'GPU Lab',
      'icon': 'memory',
      'color': '#F472B6',
      'desc': 'WebGPU/WGSL + f16 en caliente, hasta shaders desde Lua',
    },
    {
      'name': 'shamir_lab',
      'title': 'Shamir Lab',
      'icon': 'call_split',
      'color': '#FB923C',
      'desc': 'Partir y reconstruir secretos',
    },
    {
      'name': 'kem_lab',
      'title': 'KEM Lab',
      'icon': 'lock',
      'color': '#4ADE80',
      'desc': 'Post-cuántico: ML-KEM / X-Wing',
    },
    {
      'name': 'hf_browser',
      'title': 'HuggingFace',
      'icon': 'hub',
      'color': '#60A5FA',
      'desc': 'Buscar modelos y bajar rangos',
    },
    {
      'name': 'nostr_dm_lab',
      'title': 'Nostr DM',
      'icon': 'chat',
      'color': '#38BDF8',
      'desc': 'DM NIP-17 sin observador',
    },
    {
      'name': 'nostr_obs_lab',
      'title': 'Nostr Obs',
      'icon': 'visibility',
      'color': '#C084FC',
      'desc': 'Shared-key con observador lectura-only',
    },
  ];

  static List<Map<String, String>> recommended() =>
      all.map((e) => {'uri': 'lua://${e['name']}', ...e}).toList();

  static Map<String, String>? forName(String name) {
    for (final e in all) {
      if (e['name'] == name) return e;
    }
    return null;
  }
}
