import 'dart:io';
import 'dart:typed_data';

import 'package:dart_ipfs/dart_ipfs.dart';
import 'package:path_provider/path_provider.dart';

/// Nodos IPFS de pr_app.
///
/// - [IpfsService.instance]: nodo LOCAL offline (almacenamiento con
///   dirección por contenido, sin red).
/// - [IpfsService.p2p]: nodo ONLINE real — DHT server, bitswap y
///   bootstrap peers públicos de libp2p. Gateway en :8081 para poder
///   correr simultáneo con el local (:8080).
///
/// OJO: blockStorePath/keystorePath tienen defaults RELATIVOS ('blocks',
/// './ipfs_keystore') que dart_ipfs resuelve contra el CWD de Android
/// (read-only, errno=30). TODOS los paths van anclados absolutos acá.
class IpfsService {
  /// Nodo offline local (fase 1).
  static final IpfsService instance = IpfsService._('local');

  /// Nodo P2P online con bootstrap peers (fase 2).
  static final IpfsService p2p = IpfsService._('p2p');

  /// Bootstrap público oficial de libp2p.
  static const _bootstraps = [
    '/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxM2WkV78GQ6fQnZB2jYb8zXgBMjTezGAJN',
    '/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb',
    '/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt',
    '/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ',
  ];

  final String tag;
  IpfsService._(this.tag);

  IPFSNode? _node;
  bool gatewayEnabled = false;
  String lastError = '';

  /// cid-string -> cid-string (get/pin/findProviders aceptan String).
  final Map<String, String> _cidObjects = {};

  bool get running => _node != null;
  bool get online => identical(this, p2p);
  String get dataDirName => online ? 'ipfs_p2p' : 'ipfs_data';
  int get gatewayPort => online ? 8081 : 8080;
  List<String> get localCids => _cidObjects.keys.toList();

  /// Inicia el nodo ([online] ⇒ P2P con DHT+bitswap+bootstrap);
  /// [gateway] habilita el HTTP gateway del nodo.
  Future<String> start({bool gateway = false}) async {
    if (_node != null) return 'ya está corriendo';
    try {
      final dir = await getApplicationSupportDirectory();
      final base = '${dir.path}/$dataDirName';
      for (final sub in ['', '/datastore', '/keystore', '/blocks']) {
        await Directory('$base$sub').create(recursive: true);
      }
      gatewayEnabled = gateway;
      final gatewayCfg =
          GatewayConfig(enabled: gateway, port: gatewayPort);
      final config = online
          ? IPFSConfig(
              offline: false,
              network: NetworkConfig(
                bootstrapPeers: _bootstraps,
                listenAddresses: ['/ip4/0.0.0.0/tcp/4001'],
              ),
              // dht: DHTConfig no existe en dart_ipfs 1.11.6 → defaults.
              enableLibp2pBridge: true,
              libp2pListenAddress: '/ip4/0.0.0.0/tcp/4001',
              dataPath: base,
              datastorePath: '$base/datastore',
              keystorePath: '$base/keystore',
              blockStorePath: '$base/blocks',
              debug: false,
              verboseLogging: false,
              gateway: gatewayCfg,
            )
          : IPFSConfig(
              offline: true,
              dataPath: base,
              datastorePath: '$base/datastore',
              keystorePath: '$base/keystore',
              blockStorePath: '$base/blocks',
              debug: false,
              verboseLogging: false,
              gateway: gatewayCfg,
            );
      final node = await IPFSNode.create(config);
      await node.start();
      _node = node;
      lastError = '';
      if (online) {
        return 'P2P OK · DHT server + bitswap · ${_bootstraps.length} bootstrap'
            '${gateway ? " · gateway :$gatewayPort" : ""}';
      }
      return gateway
          ? 'nodo OK · gateway http://127.0.0.1:$gatewayPort'
          : 'nodo OK (offline)';
    } catch (e) {
      lastError = '$e';
      _node = null;
      return 'ERROR al iniciar: $e';
    }
  }

  Future<String> stop() async {
    final n = _node;
    if (n == null) return 'no estaba corriendo';
    _node = null;
    try {
      await n.stop();
      return 'nodo detenido';
    } catch (e) {
      lastError = '$e';
      return 'detenido (con aviso: $e)';
    }
  }

  /// Agrega un archivo y retorna su CID como string.
  Future<String> addFile(File f) async {
    final node = _requireNode();
    final bytes = await f.readAsBytes();
    final cid = await node.addFile(bytes);
    final s = '$cid'.trim();
    _cidObjects[s] = s;
    return s;
  }

  /// Contenido bruto de un CID agregado en esta sesión (o pegado externo).
  Future<Uint8List?> cat(String cidStr) async {
    final node = _requireNode();
    final key = cidStr.trim();
    return node.get(_cidObjects[key] ?? key);
  }

  /// Pin: el contenido sobrevive garbage collection.
  Future<void> pin(String cidStr) async {
    final node = _requireNode();
    final key = cidStr.trim();
    await node.pin(_cidObjects[key] ?? key);
  }

  /// Estadísticas locales del nodo (node.stats() no existe en dart_ipfs
  /// 1.11.6; armamos el resumen con el estado propio del service).
  Future<String> stats() async {
    return 'nodo ${running ? "activo" : "inactivo"} · '
        '${_cidObjects.length} CID · gateway ${gatewayEnabled ? "ON" : "OFF"}'
        '${online ? " · P2P" : ""}';
  }

  /// Busca proveedores de un CID en la red DHT (modo online).
  Future<String> providers(String cidStr) async {
    final node = _requireNode();
    final key = cidStr.trim();
    final list = await node.findProviders(_cidObjects[key] ?? key);
    if (list.isEmpty) return 'sin proveedores para $key';
    return '${list.length} proveedores · ${list.take(3).join(" , ")}';
  }

  void forget(String cidStr) => _cidObjects.remove(cidStr.trim());

  String status() {
    if (_node == null) {
      return lastError.isEmpty
          ? 'detenido'
          : 'detenido · último error: $lastError';
    }
    return online
        ? 'corriendo · P2P · ${_cidObjects.length} CID'
            '${gatewayEnabled ? " · gateway :$gatewayPort" : ""}'
        : 'corriendo · ${_cidObjects.length} CID locales'
            '${gatewayEnabled ? " · gateway :$gatewayPort" : " · sin gateway"}';
  }

  IPFSNode _requireNode() {
    final n = _node;
    if (n == null) throw Exception('nodo IPFS no iniciado');
    return n;
  }
}
