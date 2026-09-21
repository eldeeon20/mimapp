import 'package:flutter/material.dart';

import '../modo_sql/test_screen.dart';
import '../screens/agenda_test_screen.dart';
import '../screens/ai_screen.dart';
import '../screens/db_test_screen.dart';
import '../screens/dht_busca_screen.dart';
import '../screens/downloads_test_screen.dart';
import '../screens/filosoia_screen.dart';
import '../screens/gpu_test_screen.dart';
import '../screens/hf_test_screen.dart';
// IPFS DESACTIVADO (código en desactivado_ipfs/, sin borrar).
// import '../screens/ipfs_test_screen.dart';
import '../screens/iroh_chat_screen.dart';
import '../screens/iroh_test_screen.dart';
import '../screens/kem_test_screen.dart';
import '../screens/koni_test_screen.dart';
import '../screens/media_server_test_screen.dart';
import '../screens/nostr_busca_screen.dart';
import '../screens/nostr_dm_test_screen.dart';
import '../screens/nostr_peer_test_screen.dart';
import '../screens/nostrn_screen.dart';
import '../screens/pkarr_test_screen.dart';
import '../screens/ring_signatures_test_screen.dart';
import '../screens/ring_vote_test_screen.dart';
import '../screens/shamir_test_screen.dart';
import '../screens/tor_test_screen.dart';
import '../screens/torrent_screen.dart';
import '../screens/unarc_test_screen.dart';
import '../screens/webk_test_screen.dart';

/// Ruta de prueba del menú radial: título + constructor de la pantalla.
typedef TestRoute = ({String titulo, WidgetBuilder pagina});

/// Catálogo único claveRadial → pantalla (lo usa el menú del candado).
const Map<String, TestRoute> kTestRoutes = {
  'dm': (
    titulo: 'Nostr DM (sin observador)',
    pagina: _dm,
  ),
  'obs': (
    titulo: 'Nostr con observador',
    pagina: _obs,
  ),
  'shamir': (
    titulo: 'Shamir Secret Sharing',
    pagina: _shamir,
  ),
  'kem': (
    titulo: 'KEM post-cuántico',
    pagina: _kem,
  ),
  'hf': (
    titulo: 'HuggingFace',
    pagina: _hf,
  ),
  'gpu': (
    titulo: 'GPU Compute (WGSL)',
    pagina: _gpu,
  ),
  'dl': (
    titulo: 'Descargas',
    pagina: _dl,
  ),
  'bt': (
    titulo: 'Torrents (rqbit)',
    pagina: _bt,
  ),
  'ag': (
    titulo: 'Agentes IA (FilosoIA)',
    pagina: _ag,
  ),
  'ring': (
    titulo: 'Nostringer · Firmas Ring',
    pagina: _ring,
  ),
  'rv': (
    titulo: 'Voto anónimo BLSAG',
    pagina: _rv,
  ),
  // IPFS DESACTIVADO (código en desactivado_ipfs/, sin borrar).
  // 'ip': (
  //   titulo: 'IPFS',
  //   pagina: _ip,
  // ),
  'ua': (
    titulo: 'Unarc · RAR/7z/ZIP',
    pagina: _ua,
  ),
  'koni': (
    titulo: 'Koni · ZIP/7z/RAR (Dart)',
    pagina: _koni,
  ),
  'webk': (
    titulo: 'WebK · servidor local',
    pagina: _webk,
  ),
  'ub': (
    titulo: 'Nostr Busca',
    pagina: _ub,
  ),
  'nn': (
    titulo: 'Nostrn+ · cuenta y bandeja',
    pagina: _nn,
  ),
  'up': (
    titulo: 'Pkarr v8',
    pagina: _up,
  ),
  'tr': (
    titulo: 'Tor embebido (arti)',
    pagina: _tr,
  ),
  'dh': (
    titulo: 'DHT Busca · spider Mainline',
    pagina: _dh,
  ),
  'ic': (
    titulo: 'Iroh Chat · DM',
    pagina: _ic,
  ),
  'ir': (
    titulo: 'Iroh P2P · transferir archivos',
    pagina: _ir,
  ),
  'age': (
    titulo: 'Agenda · notas cifradas',
    pagina: _age,
  ),
  'db': (
    titulo: 'Base SQL · SQLite ChaCha20',
    pagina: _db,
  ),
  'ml': (
    titulo: 'MediaServer · moldes .mld + rangos',
    pagina: _ml,
  ),
  'ts': (
    titulo: 'Test SQL · moldes + índice + HF',
    pagina: _ts,
  ),
};

Widget _dm(BuildContext _) => const NostrDmTestScreen();
Widget _obs(BuildContext _) => const NostrPeerTestScreen();
Widget _shamir(BuildContext _) => const ShamirTestScreen();
Widget _kem(BuildContext _) => const KemTestScreen();
Widget _hf(BuildContext _) => const HfTestScreen();
Widget _gpu(BuildContext _) => const GpuTestScreen();
Widget _dl(BuildContext _) => const DownloadsTestScreen();
Widget _bt(BuildContext _) => const TorrentScreen();
Widget _ag(BuildContext _) => const FilosoiaScreen();
Widget _ring(BuildContext _) => const RingSignaturesTestScreen();
Widget _rv(BuildContext _) => const RingVoteTestScreen();
// IPFS DESACTIVADO (código en desactivado_ipfs/, sin borrar).
// Widget _ip(BuildContext _) => const IpfsTestScreen();
Widget _ua(BuildContext _) => const UnarcTestScreen();
Widget _koni(BuildContext _) => const KoniTestScreen();
Widget _webk(BuildContext _) => const WebkTestScreen();
Widget _ub(BuildContext _) => const NostrBuscaScreen();
Widget _nn(BuildContext _) => const NostrnScreen();
Widget _up(BuildContext _) => const PkarrTestScreen();
Widget _tr(BuildContext _) => const TorTestScreen();
Widget _dh(BuildContext _) => const DhtBuscaScreen();
Widget _ic(BuildContext _) => const IrohChatScreen();
Widget _ir(BuildContext _) => const IrohTestScreen();
Widget _age(BuildContext _) => const AgendaTestScreen();
Widget _db(BuildContext _) => const DbTestScreen();
Widget _ml(BuildContext _) => const MediaServerTestScreen();
Widget _ts(BuildContext _) => const TestSqlScreen();
