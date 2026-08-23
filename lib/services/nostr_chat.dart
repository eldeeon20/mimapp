import '../src/rust/api/nostr_dm.dart' as rust;

/// Chat Nostr NIP-17 (DM privado 1-a-1, SIN observador).
///
/// Variante A de Gtool (`nostr_demo1.gd`): claves reales tuyas + npub del
/// peer, relays DM y de lectura, suscripción y polling.
class NostrChat {
  rust.NostrDm? _client;

  bool get connected => _client != null;

  /// nsec vacío = genera identidad nueva. Los relays se agregan ANTES de
  /// suscribirse (requisito del cliente).
  Future<void> init({
    String? nsec,
    required String peerNpub,
    List<String> dmRelays = const [],
    List<String> readRelays = const [],
    int nSeconds = 3600,
    int nLimit = 10,
  }) async {
    await close();
    final c = await rust.nostrDmNew(nsec: nsec, peerNpub: peerNpub);
    if (dmRelays.isNotEmpty) {
      await c.addRelays(dmRelays: dmRelays, readRelays: readRelays);
    }
    await c.subscribe(nSeconds: nSeconds, nLimit: nLimit);
    _client = c;
  }

  Future<void> addRelays(List<String> dmRelays,
      {List<String> readRelays = const []}) async {
    await _require()
        .addRelays(dmRelays: dmRelays, readRelays: readRelays);
  }

  Future<void> send(String content) async {
    await _require().send(content: content);
  }

  /// Poll bloqueante (~[timeoutSecs]); retorna mensajes nuevos del peer.
  Future<List<rust.DmMessage>> poll({int timeoutSecs = 2}) async {
    return _require().poll(pollTimeoutSecs: timeoutSecs);
  }

  Future<String> publicKey() async => _require().publicKey();

  /// Drena el registro de eventos de Rust (init/relays/send/poll).
  Future<List<String>> takeLogs() async {
    final c = _client;
    if (c == null) return const [];
    try {
      return await c.takeLogs();
    } catch (_) {
      return const [];
    }
  }

  Future<void> close() async {
    final c = _client;
    _client = null;
    if (c != null) {
      try {
        await c.disconnect();
      } catch (_) {}
    }
  }

  rust.NostrDm _require() {
    final c = _client;
    if (c == null) throw StateError('NostrChat sin inicializar (llamá init)');
    return c;
  }
}
