import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../account.dart';
import '../chat_settings.dart';
import '../mock_server.dart';
import '../models.dart';
import 'chat_screen.dart';
import 'gifts_screen.dart';
import 'profile_screen.dart';
import 'settings_chat_screen.dart';
import 'story_viewer_screen.dart';

/// Paleta estilo Telegram dark.
class Tg {
  static const bg = Color(0xFF0E1621);
  static const panel = Color(0xFF17212B);
  static const bubbleIn = Color(0xFF182533);
  static const bubbleOut = Color(0xFF2B5278);
  static const accent = Color(0xFF2EA6FF);
  static const divider = Color(0xFF101921);
  static const subtitulo = Color(0xFF708499);
}

/// Pantalla principal: buscador, fila de estados, tabs y lista de chats.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String query = '';

  @override
  void initState() {
    super.initState();
    MockServer.instance.ensureSeed();
    Account.instance.amigosIds.addAll(['u1', 'u3', 'u6']);
    Account.instance.bloqueadosIds.add('u5');
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = MockServer.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([server, Account.instance]),
      builder: (context, _) {
        var lista = server.chats.toList();
        final t = _tabs.index;
        if (t == 1) lista = lista.where((c) => c.esGrupo).toList();
        if (t == 2) lista = lista.where((c) => c.esCanal).toList();
        if (t == 3) {
          lista = lista
              .where((c) => c.tipo == ChatType.privado)
              .toList()
            ..sort((a, b) => b.noLeidos.compareTo(a.noLeidos));
        }
        if (query.isNotEmpty) {
          lista = lista
              .where((c) =>
                  c.nombre.toLowerCase().contains(query.toLowerCase()))
              .toList();
        }
        lista.sort((a, b) {
          if (a.fijado != b.fijado) return a.fijado ? -1 : 1;
          return 0;
        });

        return Scaffold(
          backgroundColor: Tg.bg,
          appBar: AppBar(
            backgroundColor: Tg.panel,
            title: TextField(
              onChanged: (v) => setState(() => query = v),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Buscar',
                hintStyle: TextStyle(color: Tg.subtitulo),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.card_giftcard_rounded,
                    color: Tg.accent),
                tooltip: 'Gifts',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const GiftsScreen())),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.menu, color: Colors.white70),
                onSelected: (v) {
                  if (v == 'ajustes') _push(const SettingsChatScreen());
                  if (v == 'perfil') {
                    _push(const ProfileScreen(esPropio: true));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'perfil', child: Text('Mi perfil')),
                  PopupMenuItem(value: 'ajustes', child: Text('Ajustes')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              _filaEstados(server),
              TabBar(
                controller: _tabs,
                labelColor: Tg.accent,
                unselectedLabelColor: Tg.subtitulo,
                indicatorColor: Tg.accent,
                dividerColor: Tg.divider,
                tabs: const [
                  Tab(text: 'Todos'),
                  Tab(text: 'Grupos'),
                  Tab(text: 'Canales'),
                  Tab(text: 'Amigos'),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _tile(server, lista[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _push(Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));
  }

  // ------------------------------------------------------------------
  // Estados (stories)
  // ------------------------------------------------------------------

  Widget _filaEstados(MockServer server) {
    if (!AjustesChat.instance.mostrarEstados) return const SizedBox.shrink();
    final entries = server.estados.entries.toList();
    return Container(
      color: Tg.panel,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: SizedBox(
        height: 92,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _storyItem(
              nombre: 'Mi estado',
              add: true,
              visto: false,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Demo: grabar estado no disponible'))),
            ),
            for (final e in entries)
              _storyItem(
                nombre: server.usuarios[e.value.userId]?.nombre.split(' ').first ??
                    e.key,
                visto: e.value.vista,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => StoryViewerScreen(story: e.value)));
                  server.marcarEstadoVisto(e.key);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _storyItem({
    required String nombre,
    required bool visto,
    bool add = false,
    VoidCallback? onTap,
  }) {
    final borde =
        visto ? Colors.white24 : Tg.accent;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, border: Border.all(color: borde, width: 2.4)),
                padding: const EdgeInsets.all(3),
                child: Stack(children: [
                  Container(
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Tg.bubbleIn),
                    alignment: Alignment.center,
                    child: Text(nombre[0].toUpperCase(),
                        style: const TextStyle(fontSize: 20, color: Colors.white)),
                  ),
                  if (add)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: Tg.accent),
                        child: const Icon(Icons.add, size: 15, color: Colors.white),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 4),
              Text(nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Tile de chat
  // ------------------------------------------------------------------

  Widget _tile(MockServer server, Chat c) {
    final last = server.ultimoMensaje(c.id);
    final typing = server.escribiendo.contains(c.id);

    String preview;
    if (typing) {
      preview = 'escribiendo...';
    } else if (last == null) {
      preview = c.descripcion.isEmpty ? 'Sin mensajes' : c.descripcion;
    } else {
      preview = switch (last.media?.tipo) {
        MediaType.imagen => '🖼 Foto',
        MediaType.video => '🎬 Video',
        MediaType.archivo => '📄 ${last.media!.nombre}',
        MediaType.audio => '🎤 Mensaje de voz',
        null => last.texto,
      };
      if (last.mia && preview.isNotEmpty) preview = 'Tú: $preview';
    }

    final hora = last?.hora;
    final horaTxt = hora == null
        ? ''
        : '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';

    return ListTile(
      onLongPress: () => setState(() => c.fijado = !c.fijado),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Avatar.chat(c, size: 52),
      title: Row(children: [
        Expanded(
          child: Text(c.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (c.silenciado)
          const Icon(Icons.notifications_off_rounded,
              size: 16, color: Tg.subtitulo),
        const SizedBox(width: 4),
        Text(horaTxt,
            style: TextStyle(
                fontSize: 11,
                color: c.noLeidos > 0 ? Tg.accent : Tg.subtitulo)),
      ]),
      subtitle: Row(children: [
        Expanded(
          child: Text(preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  color: typing ? Tg.accent : Tg.subtitulo,
                  fontStyle: FontStyle.normal)),
        ),
        if (last?.mia == true && !typing) _ticks(last!.status),
        if (c.noLeidos > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: c.silenciado ? Tg.subtitulo : Tg.accent,
                borderRadius: BorderRadius.circular(12)),
            child: Text('${c.noLeidos}',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ]),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChatScreen(chat: c)));
        server.marcarLeido(c.id);
      },
    );
  }

  Widget _ticks(MsgStatus s) => Icon(
        s == MsgStatus.leido ? Icons.done_all_rounded : Icons.done_rounded,
        size: 15,
        color: s == MsgStatus.leido ? Tg.accent : Tg.subtitulo,
      );
}

/// Evita import circular con settings; lee el toggle actual.

// ---------------------------------------------------------------------------
// Avatar reutilizable
// ---------------------------------------------------------------------------

class Avatar extends StatelessWidget {
  final String nombre;
  final ColorSeed seed;
  final double size;
  final ChatType? tipo;

  const Avatar({super.key, required this.nombre, required this.seed, this.size = 48, this.tipo});

  factory Avatar.chat(Chat chat, {double size = 48}) => Avatar(
      nombre: chat.nombre, seed: chat.color, size: size, tipo: chat.tipo);

  @override
  Widget build(BuildContext context) {
    IconData? badge = switch (tipo) {
      ChatType.canal => Icons.campaign_rounded,
      ChatType.grupo => Icons.groups_rounded,
      _ => null,
    };
    return Stack(children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [seed.claro, seed.oscuro]),
        ),
        alignment: Alignment.center,
        child: Text(
          nombre[0].toUpperCase(),
          style: TextStyle(
              fontSize: size * .42, color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      if (badge != null)
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Tg.panel),
            child: Icon(badge, size: size * .32, color: Colors.white70),
          ),
        ),
    ]);
  }
}

/// Selector de archivo real (imagen/video/documento) vía file_picker.
Future<PlatformFile?> elegirArchivo(BuildContext context, String tipo) async {
  FileType ft = switch (tipo) {
    'imagen' => FileType.image,
    'video' => FileType.video,
    _ => FileType.any,
  };
  final res = await FilePicker.platform.pickFiles(type: ft);
  return res?.files.singleOrNull;
}
