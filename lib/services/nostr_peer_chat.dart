import '../src/rust/api/nostr_peer.dart' as rust;

/// Chat Nostr CON observador (clave compartida ECDH, patrón Mostro).
///
/// Variante B de Gtool (`nostrpeer.rs`): los dos participantes derivan la
/// misma shared key por ECDH; cualquier tercero con esa key puede LEER
/// (initObserver) pero no escribir.
class NostrPeerChat {
  NostrPeerChat._(this._inner);

  final rust.NostrPeerChat _inner;
  int _nSeconds = 600;

  static Future<NostrPeerChat> create() async =>
      NostrPeerChat._(await rust.nostrPeerNew());

  /// Ventana de frescura: mensajes más viejos que [secs] se descartan.
  Future<void> setWindow(int secs) async {
    _nSeconds = secs;
    await _inner.setWindow(nSeconds: secs);
  }

  /// Participante: retorna la shared key en hex → pasásela al observador
  /// por otro canal (p/ej. cifrada con Shamir o en persona).
  Future<String> initParticipant({
    required String senderSecret,
    required String receiverPubkey,
    required List<String> relays,
    int nLimit = 10,
    int since = 0,
    int until = 0,
  }) {
    return _inner.initParticipant(
      senderSecret: senderSecret,
      receiverPubkey: receiverPubkey,
      relays: relays,
      nLimit: nLimit,
      since: since,
      until: until,
    );
  }

  /// Observador: solo necesita la shared key + relays. Solo lectura.
  Future<void> initObserver({
    required String sharedKeyHex,
    required List<String> relays,
    int nLimit = 10,
    int since = 0,
    int until = 0,
  }) {
    return _inner.initObserver(
      sharedKeyHex: sharedKeyHex,
      relays: relays,
      nLimit: nLimit,
      since: since,
      until: until,
    );
  }

  /// Enviar mensaje. El observador recibe excepción (no puede escribir).
  Future<void> send(String message) => _inner.send(message: message);

  /// Poll no bloqueante; mensajes ya desencriptados y verificados.
  /// Falla con excepción si el chat no fue iniciado (antes: silencio).
  Future<List<rust.PeerMessage>> poll() => _inner.poll();

  /// Drena el registro de eventos de Rust (init/relays/subscribe/send).
  Future<List<String>> takeLogs() async {
    try {
      return await _inner.takeLogs();
    } catch (_) {
      return const [];
    }
  }

  Future<void> close() async {
    try {
      await _inner.disconnect();
    } catch (_) {}
  }
}
