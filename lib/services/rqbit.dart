import 'dart:typed_data';

// FRB genera un .dart por cada archivo Rust del módulo torrent/.
import '../src/rust/api/torrent/actions.dart' as actions;
import '../src/rust/api/torrent/add.dart' as add;
import '../src/rust/api/torrent/detail.dart' as detail;
import '../src/rust/api/torrent/list.dart' as list;
import '../src/rust/api/torrent/session.dart' as session;

typedef TorrentItem = list.TorrentItem;
typedef TorrentFile = detail.TorrentFile;
typedef TorrentPeer = detail.TorrentPeer;

/// Puente rqbit (BitTorrent embebido). Espeja los comandos Tauri del
/// desktop 1:1 vía flutter_rust_bridge — sin HTTP local.
///
/// La sesión corre en el proceso Rust de la app: el servicio en primer
/// plano la mantiene viva al minimizar o salir de la pantalla.
class RqbitBridge {
  /// Arranca (o reusa) la sesión. [dataDir] dentro del sandbox.
  /// [dht] = Kademlia UDP · [upnp] = port forwarding del router.
  /// Límites globales en bytes/s (null = ilimitado).
  /// Se aplican SOLO al iniciar la sesión (primer arranque de la app).
  static Future<String> startSession(
    String dataDir, {
    bool dht = true,
    bool upnp = true,
    int? downBps,
    int? upBps,
  }) =>
      session.torrentSessionStart(
        dataDir: dataDir,
        enableDht: dht,
        enableUpnp: upnp,
        downBps: downBps,
        upBps: upBps,
      );

  static bool get running => session.torrentSessionRunning();

  static Future<List<rust.TorrentItem>> list() => list.torrentList();

  /// Magnet o URL de .torrent. Límites POR TORRENT en bytes/s.
  static Future<int?> addUrl(String url, {int? downBps, int? upBps}) =>
      add.torrentAddUrl(url: url, downBps: downBps, upBps: upBps);

  /// Archivo .torrent local. Límites POR TORRENT en bytes/s.
  static Future<int?> addTorrentFile(Uint8List bytes,
          {int? downBps, int? upBps}) =>
      add.torrentAddBytes(bytes: bytes, downBps: downBps, upBps: upBps);

  static Future<List<rust.TorrentFile>> files(int id) =>
      detail.torrentFiles(id: id);

  static Future<List<rust.TorrentPeer>> peers(int id) =>
      detail.torrentPeers(id: id);

  /// action: 'start' | 'pause' | 'forget' | 'delete'
  static Future<void> action(int id, String action) =>
      actions.torrentAction(id: id, action: action);

  /// Selección múltiple de archivos a descargar.
  static Future<void> setOnlyFiles(int id, List<int> files) =>
      actions.torrentSetOnlyFiles(id: id, files: files);
}
