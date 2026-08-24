import '../../src/rust/api/nostr_busca.dart' as rust;

/// Nostr Busca: perfiles y búsqueda de usuarios.
/// Clase fina reutilizable desde cualquier pantalla o página Lua caliente.
class NostrBusca {
  /// B1: perfil de un npub concreto (bech32 o hex).
  Future<rust.PerfilItem> perfil({
    required String npub,
    required List<String> relays,
    int timeoutSecs = 8,
  }) =>
      rust.nostrPerfilFetch(
        npub: npub,
        relays: relays,
        timeoutSecs: timeoutSecs,
      );

  /// B2: búsqueda por texto (NIP-50 — solo relays que la soportan).
  Future<List<rust.PerfilItem>> buscar({
    required String query,
    required List<String> relays,
    int limite = 25,
    int timeoutSecs = 8,
  }) =>
      rust.nostrBuscarUsuarios(
        query: query,
        relays: relays,
        limite: limite,
        timeoutSecs: timeoutSecs,
      );
}
