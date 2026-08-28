import 'package:flutter/material.dart';

import '../ai/laurelia_chat.dart';
import '../chat/screens/chat_list_screen.dart';
import '../colab_cli/colab_dialog.dart';
import '../media/media_player.dart';
import '../screens/ai_screen.dart';
import '../screens/downloads_test_screen.dart';
import '../browser/browser_host.dart';
import '../browser/browser_tabs.dart';
import '../screens/torrent_screen.dart';
import '../screens/filosoia_screen.dart';
import '../agents/agent_manager.dart';
import '../screens/gpu_test_screen.dart';
import '../screens/hf_test_screen.dart';
import '../screens/ipfs_test_screen.dart';
import '../screens/kem_test_screen.dart';
import '../screens/media_screen.dart';
import '../screens/nostr_dm_test_screen.dart';
import '../screens/nostr_peer_test_screen.dart';
import '../screens/ring_signatures_test_screen.dart';
import '../screens/ring_vote_test_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shamir_test_screen.dart';
import '../screens/nostr_busca_screen.dart';
import '../screens/nostrn_screen.dart';
import '../screens/pkarr_test_screen.dart';
import '../screens/dht_busca_screen.dart';
import '../screens/iroh_chat_screen.dart';
import '../screens/iroh_test_screen.dart';
import '../screens/tor_test_screen.dart';
import '../screens/unarc_test_screen.dart';
import '../toolsec/toolsec_dialog.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/radial_menu.dart';

/// App principal: tema oscuro + HomePage.
class PrApp extends StatelessWidget {
  const PrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secure App',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: PopScope(
        // El botón atrás NUNCA cierra la app: si el browser está abierto lo
        // cierra (web intacta); si no, se queda en la app.
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (BrowserTabs.instance.isOpen) {
            BrowserTabs.instance.closeBrowser();
          }
        },
        child: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final MediaPlayer _mediaPlayer;
  late final LaureliaChat _laurelia;
  OverlayEntry? _browserEntry;

  @override
  void initState() {
    super.initState();
    _mediaPlayer = MediaPlayer.instance;
    _laurelia = LaureliaChat();
    // Agentes IA: cargar persistencia cifrada al arrancar la app; viven
    // a nivel app y sobreviven a los cambios de pantalla.
    AgentManager.instance.ensureLoaded();
    // Browser: overlay global persistente. Vive en el Overlay de la app,
    // así los WebViews no se destruyen al navegar (estado vivo completo).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _browserEntry = OverlayEntry(
          builder: (_) => Positioned.fill(child: const BrowserWebViewsHost()));
      Overlay.of(context).insert(_browserEntry!);
    });
  }

  @override
  void dispose() {
    _browserEntry?.remove();
    _mediaPlayer.dispose();
    super.dispose();
  }

  void _openChatReplica(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: null,
        body: SafeArea(child: const ChatListScreen()),
      ),
    ));
  }

  void _openMedia(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Media')),
        body: SafeArea(child: MediaScreen(mediaPlayer: _mediaPlayer)),
      ),
    ));
  }

  void _openLaurelia(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Laurelia IA')),
        body: SafeArea(child: AiScreen(laurelia: _laurelia)),
      ),
    ));
  }

  void _openWeb(BuildContext context) {
    // Lua quedó suelto (código intacto en lib/lua/, sin invocar): el botón
    // Web ahora abre el browser inappwebview como overlay global.
    BrowserTabs.instance.openBrowser();
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const SettingsScreen(),
    ));
  }

  void _openRadialMenu(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      useSafeArea: false,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: RadialMenu(onSelect: (key) {
          switch (key) {
            case 'dm':
              _openTest(context, 'Nostr DM (sin observador)',
                  const NostrDmTestScreen());
            case 'obs':
              _openTest(
                  context, 'Nostr con observador', const NostrPeerTestScreen());
            case 'shamir':
              _openTest(context, 'Shamir Secret Sharing',
                  const ShamirTestScreen());
            case 'kem':
              _openTest(context, 'KEM post-cuántico', const KemTestScreen());
            case 'hf':
              _openTest(context, 'HuggingFace', const HfTestScreen());
            case 'gpu':
              _openTest(context, 'GPU Compute (WGSL)', const GpuTestScreen());
            case 'dl':
              _openTest(context, 'Descargas', const DownloadsTestScreen());
            case 'bt':
              _openTest(context, 'Torrents (rqbit)', const TorrentScreen());
            case 'ag':
              _openTest(context, 'Agentes IA (FilosoIA)', const FilosoiaScreen());
            case 'ring':
              _openTest(
                  context, 'Nostringer · Firmas Ring', const RingSignaturesTestScreen());
            case 'rv':
              _openTest(context, 'Voto anónimo BLSAG', const RingVoteTestScreen());
            case 'ip':
              _openTest(context, 'IPFS', const IpfsTestScreen());
            case 'ua':
              _openTest(context, 'Unarc · RAR/7z/ZIP', const UnarcTestScreen());
            case 'ub':
              _openTest(context, 'Nostr Busca', const NostrBuscaScreen());
            case 'nn':
              _openTest(context, 'Nostrn+ · cuenta y bandeja',
                  const NostrnScreen());
            case 'up':
              _openTest(context, 'Pkarr v8', const PkarrTestScreen());
            case 'tr':
              _openTest(context, 'Tor embebido (arti)', const TorTestScreen());
            case 'dh':
              _openTest(
                  context, 'DHT Busca · spider Mainline', const DhtBuscaScreen());
            case 'ic':
              _openTest(context, 'Iroh Chat · DM', const IrohChatScreen());
            case 'ir':
              _openTest(
                  context, 'Iroh P2P · transferir archivos', const IrohTestScreen());

          }
        }),
      ),
    );
  }

  void _openTest(BuildContext context, String title, Widget child) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: child),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF030817),
              Color(0xFF020617),
              Color(0xFF01030D),
            ],
          ),
        ),
        child: Column(
          children: [
            // ==========================================================
            // TARJETAS SUPERIORES
            // ==========================================================

            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _TopCard(
                        icon: Icons.people_alt_rounded,
                        title: 'COLAB',
                        subtitle: 'Colabora y comparte\nde forma segura',
                        iconColor: Colors.deepPurpleAccent,
                        onTap: () => showColabDialog(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TopCard(
                        icon: Icons.lock_rounded,
                        title: 'CIFRAR ARCHIVOS',
                        subtitle: 'Protege tu información\ncon cifrado seguro',
                        iconColor: Colors.lightBlueAccent,
                        onTap: () => showToolSecDialog(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ==========================================================
            // CENTRO (FittedBox: escala en cualquier orientación sin deformar)
            // ==========================================================

            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => _openRadialMenu(context),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: 340,
                      height: 330,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 320,
                            height: 320,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent
                                      .withValues(alpha: .12),
                                  blurRadius: 100,
                                  spreadRadius: 30,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 330,
                            height: 100,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color:
                                    Colors.blueAccent.withValues(alpha: .25),
                              ),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                          Container(
                            width: 265,
                            height: 70,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.deepPurpleAccent
                                    .withValues(alpha: .25),
                              ),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                          Container(
                            width: 300,
                            height: 195,
                            decoration: BoxDecoration(
                              color: const Color(0xFF08132D),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    Colors.blueAccent.withValues(alpha: .55),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent
                                      .withValues(alpha: .18),
                                  blurRadius: 30,
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Nube detrás del candado
                                Icon(
                                  Icons.cloud_rounded,
                                  size: 175,
                                  color:
                                      Colors.blueAccent.withValues(alpha: .30),
                                  shadows: [
                                    Shadow(
                                      color: Colors.blueAccent
                                          .withValues(alpha: .35),
                                      blurRadius: 40,
                                    ),
                                  ],
                                ),
                                Container(
                                  width: 105,
                                  height: 105,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF111A46),
                                    border: Border.all(
                                      color: Colors.deepPurpleAccent,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.deepPurpleAccent
                                            .withValues(alpha: .45),
                                        blurRadius: 35,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.lock_rounded,
                                    size: 58,
                                    color: Color(0xFFB57CFF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ==========================================================
            // MENÚ INFERIOR
            // ==========================================================

            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                        BottomButton(
                          icon: Icons.chat_bubble_rounded,
                          title: 'Chat',
                          color: Colors.cyanAccent,
                          onTap: () => _openChatReplica(context),
                        ),
                  BottomButton(
                    icon: Icons.play_arrow_rounded,
                    title: 'Media',
                    color: Colors.purpleAccent,
                    onTap: () => _openMedia(context),
                  ),
                  BottomButton(
                    icon: Icons.psychology_rounded,
                    title: 'Laurelia IA',
                    color: Colors.cyanAccent,
                    onTap: () => _openLaurelia(context),
                  ),
                  BottomButton(
                    icon: Icons.settings_rounded,
                    title: 'Config',
                    color: Colors.orangeAccent,
                    onTap: () => _openSettings(context),
                  ),
                        BottomButton(
                          icon: Icons.language,
                          title: 'Web',
                          color: Colors.lightBlueAccent,
                          onTap: () => _openWeb(context),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TARJETA SUPERIOR
// ============================================================================

class _TopCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final VoidCallback onTap;

  const _TopCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 210,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF071027).withValues(alpha: .90),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: iconColor.withValues(alpha: .55),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: iconColor.withValues(alpha: .12),
              blurRadius: 25,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 65,
              height: 65,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: .20),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(icon, size: 38, color: iconColor),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
