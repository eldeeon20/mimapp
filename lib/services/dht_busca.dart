import '../src/rust/api/dht_busca.dart' as rust;

/// DHT Busca: spider Mainline que atrapa info_hashes, resuelve
/// metadatos con rqbit y arma un índice local buscable.
/// El motor vive en Rust (nodo servidor de la red Kademlia).
class DhtBusca {
  final rust.MotorDht _m;

  DhtBusca._(this._m);

  /// Crea el motor con caché en [dirCache]. No conecta todavía.
  static Future<DhtBusca> crear(String dirCache, {int maxMeta = 300}) async {
    final m =
        await rust.motorDhtNew(dirCache: dirCache, maxMeta: maxMeta);
    return DhtBusca._(m);
  }

  Future<void> start({bool pasivo = true, bool activo = true}) =>
      _m.start(pasivo: pasivo, activo: activo);
  Future<void> stop() => _m.stop();
  Future<List<rust.HalladoItem>> pollNuevos() => _m.pollNuevos();
  Future<List<rust.HalladoItem>> buscar(String texto) => _m.buscar(texto: texto);
  Future<rust.DhtStats> stats() => _m.stats();
  Future<void> guardar() => _m.guardar();
  Future<List<String>> logs() => _m.takeLogs();

  /// Magnet enriquecido para pegar en la pantalla Torrents (rqbit).
  String magnet(rust.HalladoItem h) =>
      _m.magnet(hash: h.infoHash, nombre: h.nombre, tamano: h.tamano);
}
