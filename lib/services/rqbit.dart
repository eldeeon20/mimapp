import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' as frb;

import '../src/rust/api/torrent/actions.dart' as t_act;
import '../src/rust/api/torrent/add.dart' as t_add;
import '../src/rust/api/torrent/detail.dart' as t_det;
import '../src/rust/api/torrent/list.dart' as t_list;
import '../src/rust/api/torrent/session.dart' as t_sess;

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
      sessionStartInner(dataDir, dht, upnp, downBps, upBps);

  static Future<String> sessionStartInner(String dataDir, bool dht,
          bool upnp, int? downBps, int? upBps) async {
    final r = await t_sess.torrentSessionStart(
      dataDir: dataDir,
      enableDht: dht,
      enableUpnp: upnp,
      downBps: downBps,
      upBps: upBps,
    );
    _running = true;
    return r;
  }

  /// Flag síncrono en memoria: la sesión vive solo mientras el proceso
  /// vive, así que este valor siempre es exacto.
  static bool _running = false;
  static bool get running => _running;

  /// Consulta real al lado Rust.
  static Future<bool> runningRust() => t_sess.torrentSessionRunning();

  static Future<List<TorrentItem>> list() async =>
      _parse(await t_list.torrentList(), TorrentItem.fromJson);

  static Future<int?> addUrl(String url, {int? downBps, int? upBps}) =>
      t_add.torrentAddUrl(url: url, downBps: downBps, upBps: upBps);

  static Future<int?> addTorrentFile(Uint8List bytes,
          {int? downBps, int? upBps}) =>
      t_add.torrentAddBytes(bytes: bytes, downBps: downBps, upBps: upBps);

  static Future<List<TorrentFile>> files(int id) async =>
      _parse(await t_det.torrentFiles(id: id), TorrentFile.fromJson);

  static Future<List<TorrentPeer>> peers(int id) async =>
      _parse(await t_det.torrentPeers(id: id), TorrentPeer.fromJson);

  static Future<void> action(int id, String action) =>
      t_act.torrentAction(id: id, action: action);

  // Vec<usize> del lado Rust llega como Uint64List.
  static Future<void> setOnlyFiles(int id, List<int> files) =>
      t_act.torrentSetOnlyFiles(
          id: id, files: frb.Uint64List.fromList(files));
}
