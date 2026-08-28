import 'package:path_provider/path_provider.dart';

import '../src/rust/api/dht_busca.dart' as rust;

/// DHT Busca: spider Mainline que atrapa info_hashes, resuelve
/// metadatos con rqbit y arma un índice local buscable.
/// El motor vive en Rust (nodo servidor de la red Kademlia).
///
/// Es un SINGLETON: una sola instancia vive en segundo plano mientras la
/// app está abierta. Salir de la pantalla NO detiene el spider; al volver
/// se reutiliza la misma instancia (el nodo sigue corriendo y atrapando).
class DhtBusca {
  final rust.MotorDht _m;

  DhtBusca._(this._m);

  static DhtBusca? _inst;
  static bool _corriendo = false;

  /// Instancia única en segundo plano (se crea la primera vez).
  static Future<DhtBusca> get instancia async {
    if (_inst == null) {
      final dir = await getApplicationSupportDirectory();
      _inst = await crear('${dir.path}/dhtbusca');
    }
    return _inst!;
  }

  /// true si el spider ya está corriendo en segundo plano.
  static bool get corriendo => _corriendo;

  /// Crea el motor con caché en [dirCache]. No conecta todavía.
  static Future<DhtBusca> crear(String dirCache, {int maxMeta = 300}) async {
    final m =
        await rust.motorDhtNew(dirCache: dirCache, maxMeta: maxMeta);
    return DhtBusca._(m);
  }

  Future<void> start({bool pasivo = true, bool activo = true}) async {
    if (_corriendo) return; // ya corre en segundo plano: no reiniciar
    await _m.start(pasivo: pasivo, activo: activo);
    _corriendo = true;
  }

  Future<void> stop() async {
    await _m.stop();
    _corriendo = false;
  }
  Future<List<rust.HalladoItem>> pollNuevos() => _m.pollNuevos();
  Future<List<rust.HalladoItem>> buscar(String texto) => _m.buscar(texto: texto);
  Future<rust.DhtStats> stats() => _m.stats();
  Future<void> probar(String texto) => _m.probar(texto: texto);

  /// Índice completo de metadatos resueltos (incluidos los del JSON al abrir).
  Future<List<rust.HalladoItem>> resueltos({int limit = 300}) =>
      _m.resueltos(limit: limit);

  /// Activa/desactiva el sondeo de hashes aleatorios.
  /// Nota: FRB renombra el parámetro reservado `on` a `on_` en Dart.
  Future<void> setSondeoAleatorio(bool on) => _m.setSondeoAleatorio(on_: on);

  /// true si el sondeo de hashes aleatorios está activo.
  Future<bool> sondeoAleatorio() => _m.sondeoAleatorio();

  /// Base de capturas en vivo (cada hash interceptado, con estado).
  Future<List<rust.CapturaItem>> capturas({int limit = 400}) =>
      _m.capturas(limit: limit);
  Future<List<rust.CapturaItem>> capturasFiltradas(String texto,
          {int limit = 400}) =>
      _m.capturasFiltradas(texto: texto, limit: limit);
  Future<void> guardar() => _m.guardar();
  Future<List<String>> logs() => _m.takeLogs();

  /// Magnet enriquecido para pegar en la pantalla Torrents (rqbit).
  String magnet(rust.HalladoItem h) =>
      _m.magnet(hash: h.infoHash, nombre: h.nombre, tamano: h.tamano);
}
