import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../account.dart';
import '../chat_settings.dart';
import '../chat_storage.dart';
import '../mock_server.dart';
import '../models.dart';
import 'camera_capture_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';

/// Conversación estilo Telegram: burbujas, media real, voz simulada.
class ChatScreen extends StatefulWidget {
  final Chat chat;
  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MockServer _server = MockServer.instance;
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Message? _respondiendo;

  // Grabación de voz simulada.
  bool _grabando = false;
  int _segGrabados = 0;
  Timer? _timerGrabacion;

  bool get _esCanal => widget.chat.esCanal;
  User? _user;

  @override
  void initState() {
    super.initState();
    _server.ensureSeed();
    _user = _server.usuarioDe(widget.chat);
    _server.marcarLeido(widget.chat.id);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _timerGrabacion?.cancel();
    super.dispose();
  }

  void _bajarAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  // ------------------------------------------------------------------
  // Envío
  // ------------------------------------------------------------------

  void _enviarTexto() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    _server.enviar(widget.chat.id, texto: t, respuestaA: _respondiendo);
    _respondiendo = null;
    ChatStorage.instance.registrar('texto', t.length * 2);
    _bajarAlFinal();
  }

  Future<void> _enviarArchivo(String tipo) async {
    final f = await elegirArchivo(context, tipo);
    if (f == null) return;
    final path = f.path;
    if (path == null) return;

    final mtipo = switch (tipo) {
      'imagen' => MediaType.imagen,
      'video' => MediaType.video,
      _ => MediaType.archivo,
    };
    final media = MediaAttachment(
      tipo: mtipo,
      archivo: File(path),
      nombre: f.name,
      sizeBytes: f.size,
    );
    ChatStorage.instance.registrar(mtipo.name, f.size);
    _server.enviar(widget.chat.id, media: media, respuestaA: _respondiendo);
    _respondiendo = null;
    _bajarAlFinal();
  }

  void _iniciarGrabacion() {
    setState(() => _grabando = true);
    _segGrabados = 0;
    _timerGrabacion = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _segGrabados++);
    });
  }

  Future<void> _terminarGrabacion({bool cancelar = false}) async {
    _timerGrabacion?.cancel();
    setState(() => _grabando = false);
    if (cancelar || _segGrabados < 1) return;
    final media = MediaAttachment(
      tipo: MediaType.audio,
      nombre: 'voz_${DateTime.now().millisecondsSinceEpoch}.m4a',
      sizeBytes: 16000 * _segGrabados,
      duracion: Duration(seconds: _segGrabados),
    );
    ChatStorage.instance.registrar('audio', media.sizeBytes);
    _server.enviar(widget.chat.id, media: media);
    _bajarAlFinal();
  }

  String get _duracionTxt =>
      '${(_segGrabados ~/ 60).toString().padLeft(2, '0')}:${(_segGrabados % 60).toString().padLeft(2, '0')}';

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_server, AjustesChat.instance]),
      builder: (context, _) {
        final msgs = _server.mensajes(widget.chat.id);
        final typing = _server.escribiendo.contains(widget.chat.id);

        return Scaffold(
          backgroundColor: Tg.bg,
          appBar: AppBar(
            backgroundColor: Tg.panel,
            leadingWidth: 80,
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              const BackButton(color: Colors.white70),
              GestureDetector(
                onTap: _abrirPerfil,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Avatar.chat(widget.chat, size: 34),
                ),
              ),
            ]),
            titleSpacing: 4,
            title: GestureDetector(
              onTap: _abrirPerfil,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.chat.nombre,
                    style: const TextStyle(fontSize: 16, color: Colors.white)),
                Text(
                  typing ? 'escribiendo...' : _subtitulo(),
                  style: TextStyle(
                      fontSize: 12,
                      color: typing ? Tg.accent : Tg.subtitulo),
                ),
              ]),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.call_rounded, color: Colors.white70), onPressed: () {}),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                onSelected: _accionMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'perfil', child: Text('Ver perfil')),
                  if (!_esCanal)
                    PopupMenuItem(
                        value: 'silenciar',
                        child: Text(widget.chat.silenciado ? 'Activar sonido' : 'Silenciar')),
                  const PopupMenuItem(value: 'limpiar', child: Text('Limpiar historial')),
                  const PopupMenuItem(value: 'bloquear', child: Text('Bloquear')),
                ],
              ),
            ],
          ),
          body: Column(children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                itemCount: msgs.length + (typing ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= msgs.length) return _burbujaTyping();
                  return _mensaje(msgs[i]);
                },
              ),
            ),
            if (!_esCanal) _barraInput() else _barraCanal(),
          ]),
        );
      },
    );
  }

  String _subtitulo() {
    final c = widget.chat;
    if (c.tipo == ChatType.privado) return _user?.estadoConexion ?? '';
    if (c.esCanal) return '${c.miembros} suscriptores';
    return '${c.miembros} miembros';
  }

  void _abrirPerfil() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProfileScreen(chat: widget.chat)));
  }

  void _accionMenu(String v) {
    switch (v) {
      case 'perfil':
        _abrirPerfil();
      case 'silenciar':
        setState(() => widget.chat.silenciado = !widget.chat.silenciado);
      case 'limpiar':
        _server.mensajes(widget.chat.id).clear();
        _server.notifyListeners();
      case 'bloquear':
        if (_user != null) Account.instance.toggleBloqueo(_user!.id);
        Navigator.of(context).pop();
    }
  }

  Widget _burbujaTyping() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: _decoBurbuja(Tg.bubbleIn),
          child: const TypingDots(),
        ),
      );

  BoxDecoration _decoBurbuja(Color c) => BoxDecoration(
        color: c,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(_esCanal ? 18 : 4),
          bottomRight: const Radius.circular(18),
        ),
      );

  // ------------------------------------------------------------------
  // Burbuja de mensaje
  // ------------------------------------------------------------------

  Widget _mensaje(Message m) {
    final mia = m.mia;
    final textoSize = AjustesChat.instance.tamanoTexto;
    final horaTxt =
        '${m.hora.hour.toString().padLeft(2, '0')}:${m.hora.minute.toString().padLeft(2, '0')}';
    final autorGrupo = !mia && widget.chat.esGrupo
        ? _server.usuarios[m.senderId]?.nombre.split(' ').first ?? ''
        : '';

    return GestureDetector(
      onLongPress: () => _menuMensaje(m),
      child: Align(
        alignment: mia ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: EdgeInsets.fromLTRB(m.media == null ? 12 : 5, m.media == null ? 8 : 5,
              m.media == null ? 12 : 5, 7),
          decoration: BoxDecoration(
            color: mia ? Tg.bubbleOut : Tg.bubbleIn,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mia ? 18 : 4),
              bottomRight: Radius.circular(mia ? 4 : 18),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (autorGrupo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 2),
                child: Text(autorGrupo,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: Tg.accent)),
              ),
            if (m.respuestaA != null) _citaRespuesta(m.respuestaA!),
            if (m.media != null) ...[
              _media(m.media!),
              if (m.texto.isNotEmpty) SizedBox(height: m.media!.tipo == MediaType.imagen || m.media!.tipo == MediaType.video ? 6 : 4),
            ],
            if (m.texto.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(m.texto, style: TextStyle(fontSize: textoSize, height: 1.25)),
              ),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [
              const Spacer(),
              Text(horaTxt,
                  style: const TextStyle(fontSize: 10.5, color: Colors.white38)),
              const SizedBox(width: 3),
              if (mia) _tickStatus(m.status),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _tickStatus(MsgStatus s) => Icon(
        s == MsgStatus.leido
            ? Icons.done_all_rounded
            : s == MsgStatus.enviado
                ? Icons.done_all_outlined
                : Icons.schedule_rounded,
        size: 14,
        color: s == MsgStatus.leido ? Tg.accent : Colors.white38,
      );

  Widget _citaRespuesta(Message r) {
    final texto = r.texto.isNotEmpty ? r.texto : '[media]';
    return Container(
      margin: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black26,
        border: Border(left: BorderSide(width: 3, color: Tg.accent)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(texto,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, color: Tg.accent)),
    );
  }

  void _menuMensaje(Message m) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Tg.panel,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.reply_rounded, color: Colors.white70),
            title: const Text('Responder'),
            onTap: () {
              setState(() => _respondiendo = m);
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded, color: Colors.white70),
            title: const Text('Copiar'),
            onTap: () {
              Navigator.of(context).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              _server.mensajes(m.chatId).remove(m);
              _server.notifyListeners();
              Navigator.of(context).pop();
            },
          ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Media dentro de la burbuja
  // ------------------------------------------------------------------

  Widget _media(MediaAttachment md) => switch (md.tipo) {
        MediaType.imagen => _imagen(md),
        MediaType.video => _video(md),
        MediaType.audio => _audio(md),
        MediaType.archivo => _archivo(md),
      };

  Widget _imagen(MediaAttachment md) {
    final f = md.archivo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(children: [
        if (f != null)
          Image.file(f, width: 240, fit: BoxFit.cover, errorBuilder:
              (_, __, ___) => _placeholderMedia(md, Icons.broken_image_rounded))
        else
          _placeholderMedia(md, Icons.image_rounded),
      ]),
    );
  }

  Widget _video(MediaAttachment md) {
    final f = md.archivo;
    return GestureDetector(
      onTap: f == null ? null : () => _reproducirVideo(f),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 240,
          height: 150,
          child: Stack(alignment: Alignment.center, children: [
            if (f != null && f.existsSync())
              Image.file(f, width: 240, height: 150, fit: BoxFit.cover)
            else
              _placeholderMedia(md, Icons.videocam_rounded),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: .45),
              ),
              child: const Icon(Icons.play_arrow_rounded, size: 36, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }

  /// Reproduce un video local en pantalla completa con media_kit.
  void _reproducirVideo(File f) {
    final player = Player();
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(controller: VideoController(player)),
          ),
        ),
      ),
    )).then((_) => player.dispose());
    player.open(Media(f.path));
  }

  Widget _archivo(MediaAttachment md) => Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Tg.accent.withValues(alpha: .2),
          child: const Icon(Icons.insert_drive_file_rounded, color: Tg.accent),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(md.nombre,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(md.sizeLegible,
                style: const TextStyle(fontSize: 12, color: Tg.subtitulo)),
          ]),
        ),
      ]);

  Widget _audio(MediaAttachment md) => _VozBurbuja(duracion: md.duracion, wave: _waveActual(md));

  List<int> _waveActual(MediaAttachment md) {
    // Waveform estable derivada del tamaño (los audios locales no tienen id previo).
    var seed = md.sizeBytes + md.duracion.inSeconds;
    return List.generate(28, (_) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return 4 + (seed >> 16) % 24;
    });
  }

  Widget _placeholderMedia(MediaAttachment md, IconData icon) => Container(
        width: 240,
        height: md.tipo == MediaType.imagen ? 170 : 150,
        color: Tg.bubbleIn.withValues(alpha: .6),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 40, color: Colors.white24),
          const SizedBox(height: 6),
          Text(md.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.white24)),
        ]),
      );

  // ------------------------------------------------------------------
  // Barra de input / canal / grabación
  // ------------------------------------------------------------------

  Widget _barraCanal() => Container(
        color: Tg.panel,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 10, top: 12),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Tg.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: () {},
          icon: const Icon(Icons.notifications_none_rounded),
          label: Text(widget.chat.silenciado ? 'Recibir notificaciones' : 'Silenciar canal'),
        ),
      );

  Widget _barraInput() {
    if (_grabando) return _inputGrabando();
    return Container(
      color: Tg.panel,
      padding: EdgeInsets.only(
          left: 6, right: 6, top: 6, bottom: MediaQuery.of(context).padding.bottom + 6),
      child: Column(children: [
        if (_respondiendo != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: Tg.bubbleIn, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.reply_rounded, color: Tg.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _respondiendo!.texto.isEmpty ? '[media]' : _respondiendo!.texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Tg.subtitulo),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _respondiendo = null),
                child: const Icon(Icons.close_rounded, size: 18, color: Tg.subtitulo),
              ),
            ]),
          ),
        Row(children: [
          IconButton(
            icon: const Icon(Icons.attach_file_rounded, color: Colors.white54),
            onPressed: _hojaAdjuntos,
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              style: TextStyle(color: Colors.white, fontSize: AjustesChat.instance.tamanoTexto),
              decoration: InputDecoration(
                filled: true,
                fillColor: Tg.bubbleIn,
                hintText: _esCanal ? '' : 'Mensaje',
                hintStyle: const TextStyle(color: Tg.subtitulo),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _ctrl,
            builder: (_, v, __) {
              final tieneTexto = v.text.trim().isNotEmpty;
              return GestureDetector(
                onLongPressStart: tieneTexto ? null : (_) => _iniciarGrabacion(),
                onLongPressEnd: tieneTexto ? null : (_) => _terminarGrabacion(),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: Tg.accent,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(tieneTexto ? Icons.send_rounded : Icons.mic_rounded,
                        color: Colors.white, size: 21),
                    onPressed: tieneTexto
                        ? _enviarTexto
                        : () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Mantené presionado 🎤 para grabar'))),
                  ),
                ),
              );
            },
          ),
        ]),
      ]),
    );
  }

  void _hojaAdjuntos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Tg.panel,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _itemAdjunto(Icons.photo_camera_rounded, 'Cámara', Colors.cyanAccent,
              _abrirCamara),
          _itemAdjunto(Icons.photo_rounded, 'Imagen', Colors.purpleAccent,
              () => _enviarArchivo('imagen')),
          _itemAdjunto(Icons.movie_rounded, 'Video', Colors.orangeAccent,
              () => _enviarArchivo('video')),
          _itemAdjunto(Icons.description_rounded, 'Archivo', Tg.accent,
              () => _enviarArchivo('archivo')),
        ]),
      ),
    );
  }

  /// Abre la cámara y envía lo capturado como imagen o video.
  Future<void> _abrirCamara() async {
    final cap = await Navigator.of(context).push<CapturedMedia>(
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (cap == null) return;
    final f = File(cap.filePath);
    if (!f.existsSync()) return;
    final media = MediaAttachment(
      tipo: cap.tipo,
      archivo: f,
      nombre: cap.filePath.split('/').last,
      sizeBytes: f.lengthSync(),
      duracion: cap.duracion,
    );
    ChatStorage.instance.registrar(cap.tipo.name, media.sizeBytes);
    _server.enviar(widget.chat.id, media: media, respuestaA: _respondiendo);
    _respondiendo = null;
    _bajarAlFinal();
  }

  ListTile _itemAdjunto(IconData i, String t, Color c, VoidCallback onTap) =>
      ListTile(
        leading: CircleAvatar(backgroundColor: c.withValues(alpha: .2), child: Icon(i, color: c)),
        title: Text(t),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      );

  /// Barra roja durante la "grabación" con timer y cancelar.
  Widget _inputGrabando() => Container(
        color: Tg.panel,
        padding: EdgeInsets.only(
            left: 16, right: 16, top: 14, bottom: MediaQuery.of(context).padding.bottom + 14),
        child: Row(children: [
          const Icon(Icons.keyboard_voice_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent)),
          const SizedBox(width: 12),
          Text(_duracionTxt,
              style: const TextStyle(fontSize: 15, color: Colors.white70)),
          const SizedBox(width: 12),
          Expanded(child: _miniWave()),
          GestureDetector(
            onTap: () => _terminarGrabacion(cancelar: true),
            child: const Text('Cancelar',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Widget _miniWave() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(20, (i) {
          final h = 4.0 + (((i * 7 + _segGrabados * 13) % 11)).abs().toDouble();
          return Container(
            width: 2.4,
            height: h.clamp(4, 14),
            decoration: BoxDecoration(
                color: Colors.white38, borderRadius: BorderRadius.circular(2)),
          );
        }),
      );
}

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
          final fase = (_c.value - i * .18).clamp(0.0, 1.0);
          final salto = (fase < .5 ? fase : 1 - fase) * 5;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: Transform.translate(
              offset: Offset(0, -salto),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Tg.accent.withValues(alpha: .35 + salto / 10),
                ),
              ),
            ),
          );
        })),
      );
}

class _VozBurbuja extends StatefulWidget {
  final Duration duracion;
  final List<int> wave;
  const _VozBurbuja({required this.duracion, required this.wave});

  @override
  State<_VozBurbuja> createState() => _VozBurbujaState();
}

class _VozBurbujaState extends State<_VozBurbuja> {
  bool reproduciendo = false;
  double progreso = 0;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _togglePlay() {
    if (reproduciendo) {
      _t?.cancel();
      setState(() => reproduciendo = false);
      return;
    }
    setState(() => reproduciendo = true);
    final total = widget.duracion.inMilliseconds <= 0
        ? 4000
        : widget.duracion.inMilliseconds;
    const pasoMs = 80;
    var acc = progreso * total;
    _t = Timer.periodic(const Duration(milliseconds: pasoMs), (t) {
      acc += pasoMs;
      if (acc >= total) {
        t.cancel();
        setState(() {
          reproduciendo = false;
          progreso = 0;
        });
      } else {
        setState(() => progreso = acc / total);
      }
    });
  }

  String get _txtDur {
    final s = widget.duracion.inSeconds <= 0 ? 4 : widget.duracion.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onTap: _togglePlay,
          child: CircleAvatar(
            radius: 19,
            backgroundColor: Tg.accent.withValues(alpha: .25),
            child: Icon(
                reproduciendo ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Tg.accent),
          ),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 150,
            height: 24,
            child: CustomPaint(painter: _WavePainter(wave: widget.wave, progreso: progreso)),
          ),
          Text(_txtDur, style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ]),
      ]);
}

class _WavePainter extends CustomPainter {
  final List<int> wave;
  final double progreso;
  _WavePainter({required this.wave, required this.progreso});

  @override
  void paint(Canvas canvas, Size size) {
    final n = wave.length;
    final bw = size.width / n;
    for (var i = 0; i < n; i++) {
      final activo = i / n <= progreso;
      final paint = Paint()
        ..color = activo ? Tg.accent : Colors.white24
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      final h = (wave[i] / 28.0) * size.height;
      canvas.drawLine(
        Offset(bw * i + bw / 2, (size.height - h) / 2),
        Offset(bw * i + bw / 2, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.progreso != progreso;
}
