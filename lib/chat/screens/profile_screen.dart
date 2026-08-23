import 'package:flutter/material.dart';

import '../account.dart';
import '../chat_storage.dart';
import '../mock_server.dart';
import '../models.dart';
import "chat_list_screen.dart";

/// Perfil de usuario propio o de un chat (usuario/grupo/canal).
class ProfileScreen extends StatefulWidget {
  final Chat? chat;
  final bool esPropio;
  const ProfileScreen({super.key, this.chat, this.esPropio = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late bool _esAmigo;
  late bool _bloqueado;

  @override
  void initState() {
    super.initState();
    MockServer.instance.ensureSeed();
    final user = _user();
    _esAmigo = user != null && Account.instance.esAmigo(user.id);
    _bloqueado = user != null && Account.instance.estaBloqueado(user.id);
  }

  User? _user() => widget.esPropio ? null : MockServer.instance.usuarioDe(widget.chat!);

  @override
  Widget build(BuildContext context) {
    final server = MockServer.instance;
    final account = Account.instance;
    final user = _user();
    final nombre = widget.esPropio ? account.nombre : (widget.chat?.nombre ?? '');
    final seed = widget.esPropio ? account.color : (widget.chat?.color ?? ColorSeed.azul);
    final username = widget.esPropio ? account.username : (user?.username ?? '@canal');
    final bio = widget.esPropio
        ? account.bio
        : (widget.chat?.descripcion.isNotEmpty == true
            ? widget.chat!.descripcion
            : (user?.bio ?? ''));

    return AnimatedBuilder(
      animation: Listenable.merge([account, ChatStorage.instance]),
      builder: (context, _) => Scaffold(
        backgroundColor: Tg.bg,
        appBar: AppBar(backgroundColor: Tg.panel, title: Text(widget.esPropio ? 'Mi perfil' : 'Perfil')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [seed.claro, seed.oscuro]),
              ),
              alignment: Alignment.center,
              child: Text(nombre[0].toUpperCase(),
                  style: const TextStyle(fontSize: 40, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(nombre,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Center(child: Text(username, style: const TextStyle(color: Tg.accent))),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(bio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Tg.subtitulo)),
            ),
          ],
          if (!widget.esPropio && user != null) ...[
            const SizedBox(height: 6),
            Center(child: Text(user.estadoConexion,
                style: const TextStyle(fontSize: 12.5, color: Tg.subtitulo))),
          ],
          const SizedBox(height: 20),

          // Acciones sociales (solo usuarios)
          if (!widget.esPropio && user != null) ...[
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _accionBoton(
                icon: _esAmigo ? Icons.person_remove_rounded : Icons.person_add_rounded,
                label: _esAmigo ? 'Quitar amigo' : 'Agregar',
                onTap: () => setState(() {
                  Account.instance.toggleAmigo(user.id);
                  _esAmigo = !_esAmigo;
                }),
              ),
              const SizedBox(width: 12),
              _accionBoton(
                icon: Icons.block_rounded,
                color: Colors.redAccent,
                label: _bloqueado ? 'Desbloquear' : 'Bloquear',
                onTap: () => setState(() {
                  Account.instance.toggleBloqueo(user.id);
                  _bloqueado = !_bloqueado;
                  if (_bloqueado) _esAmigo = false;
                }),
              ),
            ]),
            const SizedBox(height: 16),
          ],

          // Info
          _seccion('Información', [
            if (widget.esPropio || user != null)
              _fila(Icons.phone_rounded,
                  widget.esPropio ? account.telefono : (user?.telefono ?? '')),
            if (widget.esPropio) _fila(Icons.diamond_outlined, '${account.coins} coins'),
            if (widget.chat != null && widget.chat!.miembros > 0)
              _fila(Icons.people_alt_rounded, '${widget.chat!.miembros} miembros'),
          ]),

          // Media compartida simulada
          _seccion('Media compartida', [
            Row(children: [
              _miniMedia(Icons.photo_rounded, '12 fotos', Colors.purpleAccent),
              _miniMedia(Icons.movie_rounded, '3 videos', Colors.orangeAccent),
              _miniMedia(Icons.insert_drive_file_rounded, '5 archivos', Tg.accent),
            ]),
          ]),

          // Almacenamiento (solo perfil propio)
          if (widget.esPropio)
            _seccion('Almacenamiento', [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: Row(children: [
                    Expanded(flex: ChatStorage.instance.fotosMb.round(), child: Container(color: Colors.purpleAccent)),
                    Expanded(flex: ChatStorage.instance.videosMb.round(), child: Container(color: Colors.orangeAccent)),
                    Expanded(flex: ChatStorage.instance.docsMb.round() + 1, child: Container(color: Tg.accent)),
                    Spacer(flex: (ChatStorage.instance.libreMb / 1024).round().clamp(1, 99999)),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              Text('Libre: ${ChatStorage.instance.libreTxt}',
                  style: const TextStyle(fontSize: 12.5, color: Tg.subtitulo)),
            ]),
        ]),
      ),
    );
  }

  Widget _accionBoton({required IconData icon, required String label, required VoidCallback onTap, Color? color}) =>
      GestureDetector(
        onTap: onTap,
        child: Column(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: (color ?? Tg.accent).withValues(alpha: .18),
            child: Icon(icon, color: color ?? Tg.accent),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
        ]),
      );

  Widget _seccion(String titulo, List<Widget> hijos) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(titulo.toUpperCase(),
                style: const TextStyle(
                    fontSize: 12, letterSpacing: 1, color: Tg.accent, fontWeight: FontWeight.w600)),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Tg.panel, borderRadius: BorderRadius.circular(14)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: hijos),
          ),
          const SizedBox(height: 14),
        ],
      );

  Widget _fila(IconData i, String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(i, size: 19, color: Tg.subtitulo),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 14))),
        ]),
      );

  Widget _miniMedia(IconData i, String t, Color c) => Expanded(
        child: Column(children: [
          CircleAvatar(radius: 22, backgroundColor: c.withValues(alpha: .18), child: Icon(i, size: 20, color: c)),
          const SizedBox(height: 5),
          Text(t, style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
        ]),
      );
}
