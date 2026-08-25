import '../src/rust/api/iroh_p2p.dart' as rust;

/// Iroh P2P: transferencia directa de archivos por hash BLAKE3.
/// El mismo nodo sirve (ofrecer→ticket) y descarga (ticket→archivo).
class IrohP2p {
  final rust.IrohViva _n;
  IrohP2p._(this._n);

  static Future<IrohP2p> crear() async => IrohP2p._(await rust.irohNuevo());

  /// Levanta endpoint + router de blobs. Devuelve el id copiable.
  Future<String> startServidor() => _n.startServidor();

  /// Hashea el archivo y queda sirviéndolo. Devuelve el ticket.
  Future<String> ofrecer(String ruta) => _n.ofrecer(ruta: ruta);

  /// Baja el blob del ticket a [dir]/[nombre]. Devuelve la ruta final.
  Future<String> bajar(String ticket, String dir, String nombre) =>
      _n.bajar(ticket: ticket, dirDestino: dir, nombre: nombre);

  String? get nodeId => _n.nodeId();
  bool get corriendo => _n.corriendo();

  Future<void> stop() => _n.stop();
  Future<List<String>> logs() => _n.takeLogs();
}
