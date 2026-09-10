import 'package:flutter/material.dart';

import '../agents/agent_manager.dart';
import '../ai/laurelia_chat.dart';
import '../browser/browser_host.dart';
import '../browser/browser_tabs.dart';
import '../chat/screens/chat_list_screen.dart';
import '../media/media_player.dart';
import '../screens/ai_screen.dart';
import '../screens/media_screen.dart';
import '../screens/settings_screen.dart';
import 'test_routes.dart';
import 'widgets/candado_central.dart';
import 'widgets/home_bottom_menu.dart';
import 'widgets/home_header.dart';
import 'widgets/radial_menu.dart';

/// Pantalla principal: tarjetas + candado + menú inferior.
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

  @override
  Widget build(BuildContext context) {
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
            const HomeHeader(),
            Expanded(
              child: Center(
                child: CandadoCentral(
                    onTap: () => _openRadialMenu(context)),
              ),
            ),
            HomeBottomMenu(
              onChat: () => _openChatReplica(context),
              onMedia: () => _openMedia(context),
              onLaurelia: () => _openLaurelia(context),
              onConfig: () => _openSettings(context),
              onWeb: () => _openWeb(context),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Navegación
  // ===========================================================================

  void _openChatReplica(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const Scaffold(
        appBar: null,
        body: SafeArea(child: ChatListScreen()),
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
    // El botón Web abre el browser inappwebview como overlay global
    // (el motor Lua fue eliminado del proyecto).
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
          final route = kTestRoutes[key];
          if (route != null) {
            _openTest(context, route.titulo, route.pagina(context));
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
}
