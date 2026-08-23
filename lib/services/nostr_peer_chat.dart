import '../src/rust/api/nostr_peer.dart';

/// Chat Nostr CON observador (clave compartida ECDH, patrón Mostro).
///
/// Variante B de Gtool (`nostrpeer.rs`): los dos participantes derivan la
/// misma shared key por ECDH; cualquier tercero con esa key puede LEER
/// (init_observer) pero no escribir.
class NostrPeerChat {
  NostrPeerChat._(this._inner);

  final rust.NostrPeerChat _inner;
  int _nSeconds = 600;

  static Future<NostrPeerChat> create() async => NostrPeerChat._(
        await rust.NostrPeerChat(),
      );

  /// Ventana de frescura: mensajes más viejos que [secs] se descartan.
  void setWindow(int secs) {
    _nSeconds = secs;
    _inner.setWindow(nSeconds: secs);
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
  Future<List<PeerMessage>> poll() => _inner.poll();

  Future<void> close() async {
    try {
      _inner.disconnect();
    } catch (_) {}
  }
}
