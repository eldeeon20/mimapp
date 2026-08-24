import 'dart:io';
import 'dart:typed_data';

import 'package:dart_ipfs/dart_ipfs.dart';
import 'package:path_provider/path_provider.dart';

/// Nodo IPFS offline: almacenamiento local con direccion por contenido.
///
/// Fase 1 (esta): solo local, sin P2P. El gateway HTTP opcional sirve los
/// CIDs en http://127.0.0.1:8080/ipfs/<cid>.
/// Fase 2 (futura): modo P2P real con bootstrap peers (NetworkConfig).
class IpfsService {
  IpfsService._();
  static final IpfsService instance = IpfsService._();

  IPFSNode? _node;
  bool gatewayEnabled = false;
  String lastError = '';

  /// cid-string -> objeto CID que devolvió addFile (necesario para get/pin).
  final Map<String, Object> _cidObjects = {};

  bool get running => _node != null;
  List<String> get localCids => _cidObjects.keys.toList();

  /// Inicia el nodo offline; [gateway] habilita el HTTP gateway en :8080.
  Future<String> start({bool gateway = false}) async {
    if (_node != null) return 'ya está corriendo';
    try {
      final dir = await getApplicationSupportDirectory();
      final dataPath = '${dir.path}/ipfs_data';
      await Directory(dataPath).create(recursive: true);
      gatewayEnabled = gateway;
      final config = IPFSConfig(
        offline: true,
        dataPath: dataPath,
        debug: false,
        verboseLogging: false,
        gateway: GatewayConfig(enabled: gateway, port: 8080),
      );
      final node = await IPFSNode.create(config);
      await node.start();
      _node = node;
      lastError = '';
      return gateway
          ? 'nodo OK · gateway http://127.0.0.1:8080'
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
    _cidObjects[s] = cid;
    return s;
  }

  /// Contenido bruto de un CID agregado en esta sesión.
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

  void forget(String cidStr) => _cidObjects.remove(cidStr.trim());

  String status() {
    if (_node == null) {
      return lastError.isEmpty
          ? 'detenido'
          : 'detenido · último error: $lastError';
    }
    return 'corriendo · ${_cidObjects.length} CID locales'
        '${gatewayEnabled ? " · gateway :8080" : " · sin gateway"}';
  }

  IPFSNode _requireNode() {
    final n = _node;
    if (n == null) throw Exception('nodo IPFS no iniciado');
    return n;
  }
}
