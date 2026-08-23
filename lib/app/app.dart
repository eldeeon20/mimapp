import 'package:flutter/material.dart';

import '../ai/laurelia_chat.dart';
import '../colab_cli/colab_dialog.dart';
import '../lua/lua_page.dart';
import '../media/media_player.dart';
import '../screens/ai_screen.dart';
import '../screens/downloads_test_screen.dart';
import '../screens/gpu_test_screen.dart';
import '../screens/hf_test_screen.dart';
import '../screens/kem_test_screen.dart';
import '../screens/media_screen.dart';
import '../screens/nostr_dm_test_screen.dart';
import '../screens/nostr_peer_test_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shamir_test_screen.dart';
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
      home: const HomePage(),
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

  @override
  void initState() {
    super.initState();
    _mediaPlayer = MediaPlayer.instance;
    _laurelia = LaureliaChat();
  }

  @override
  void dispose() {
    _mediaPlayer.dispose();
    super.dispose();
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
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LuaPage(
        mediaPlayer: _mediaPlayer,
        laurelia: _laurelia,
      ),
    ));
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
            // CENTRO
            // ==========================================================

            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => _openRadialMenu(context),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                    Container(
                      width: size.width * .70,
                      height: size.width * .70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withValues(alpha: .12),
                            blurRadius: 100,
                            spreadRadius: 30,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: size.width * .72,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.blueAccent.withValues(alpha: .25),
                        ),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    Container(
                      width: size.width * .58,
                      height: 70,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              Colors.deepPurpleAccent.withValues(alpha: .25),
                        ),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    Container(
                      width: size.width * .62,
                      height: size.width * .46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF08132D),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.blueAccent.withValues(alpha: .55),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withValues(alpha: .18),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            top: 25,
                            child: Container(
                              width: size.width * .30,
                              height: size.width * .25,
                              decoration: BoxDecoration(
                                color: const Color(0xFF182747),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: .15),
                                ),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.description_rounded,
                                    size: 48,
                                    color: Colors.white54,
                                  ),
                                  SizedBox(height: 8),
                                  Icon(
                                    Icons.more_horiz,
                                    color: Colors.white30,
                                  ),
                                ],
                              ),
                            ),
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
                          onTap: () => _openLaurelia(context),
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
