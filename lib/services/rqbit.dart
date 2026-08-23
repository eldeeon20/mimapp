import 'dart:convert';
import 'dart:typed_data';

import '../src/rust/api/torrent/actions.dart' as actions;
import '../src/rust/api/torrent/add.dart' as add;
import '../src/rust/api/torrent/detail.dart' as detail;
import '../src/rust/api/torrent/list.dart' as list;
import '../src/rust/api/torrent/session.dart' as session;

/// Modelos manuales (parseados de JSON del puente): inmunes a los quirks
/// de mapeo de tipos de FRB (usize→BigInt, nombres sin camelCase).
class TorrentItem {
  final int? id;
  final String infoHash;
  final String name;
  final String state;
  final int progressBytes;
  final int totalBytes;
  final int uploadedBytes;
  final bool finished;
  final String? error;
  final int downBps;
  final int upBps;

  TorrentItem({
    this.id,
    required this.infoHash,
    required this.name,
    required this.state,
    required this.progressBytes,
    required this.totalBytes,
    required this.uploadedBytes,
    required this.finished,
    this.error,
    required this.downBps,
    required this.upBps,
  });

  factory TorrentItem.fromJson(Map<String, dynamic> j) => TorrentItem(
        id: (j['id'] as num?)?.toInt(),
        infoHash: j['info_hash'] ?? '',
        name: j['name'] ?? '',
        state: j['state'] ?? '',
        progressBytes: (j['progress_bytes'] as num?)?.toInt() ?? 0,
        totalBytes: (j['total_bytes'] as num?)?.toInt() ?? 0,
        uploadedBytes: (j['uploaded_bytes'] as num?)?.toInt() ?? 0,
        finished: j['finished'] == true,
        error: j['error'] as String?,
        downBps: (j['down_bps'] as num?)?.toInt() ?? 0,
        upBps: (j['up_bps'] as num?)?.toInt() ?? 0,
      );
}

class TorrentFile {
  final int index;
  final String name;
  final int length;
  final bool included;
  TorrentFile.fromJson(Map<String, dynamic> j)
      : index = (j['index'] as num).toInt(),
        name = j['name'] ?? '',
        length = (j['length'] as num?)?.toInt() ?? 0,
        included = j['included'] == true;
}

class TorrentPeer {
  final String addr;
  final String? client;
  final String state;
  final int downloaded;
  final int uploaded;
  TorrentPeer.fromJson(Map<String, dynamic> j)
      : addr = j['addr'] ?? '',
        client = j['client'] as String?,
        state = j['state'] ?? '',
        downloaded = (j['downloaded'] as num?)?.toInt() ?? 0,
        uploaded = (j['uploaded'] as num?)?.toInt() ?? 0;
}

List<T> _parse<T>(String raw, T Function(Map<String, dynamic>) from) =>
    (jsonDecode(raw) as List).map((e) => from(e as Map<String, dynamic>)).toList();

/// Puente rqbit (BitTorrent embebido). Espeja los comandos Tauri del
/// desktop vía flutter_rust_bridge — sin HTTP local.
class RqbitBridge {
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

  static Future<List<TorrentItem>> list() async =>
      _parse(await list.torrentList(), TorrentItem.fromJson);

  static Future<int?> addUrl(String url, {int? downBps, int? upBps}) =>
      add.torrentAddUrl(url: url, downBps: downBps, upBps: upBps);

  static Future<int?> addTorrentFile(Uint8List bytes,
          {int? downBps, int? upBps}) =>
      add.torrentAddBytes(bytes: bytes, downBps: downBps, upBps: upBps);

  static Future<List<TorrentFile>> files(int id) async =>
      _parse(await detail.torrentFiles(id: id), TorrentFile.fromJson);

  static Future<List<TorrentPeer>> peers(int id) async =>
      _parse(await detail.torrentPeers(id: id), TorrentPeer.fromJson);

  static Future<void> action(int id, String action) =>
      actions.torrentAction(id: id, action: action);

  static Future<void> setOnlyFiles(int id, List<int> files) =>
      actions.torrentSetOnlyFiles(id: id, files: files);
}
