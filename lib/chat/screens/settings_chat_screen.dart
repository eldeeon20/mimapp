import 'package:flutter/material.dart';

import '../account.dart';
import '../chat_settings.dart';
import '../chat_storage.dart';
import '../mock_server.dart';
import 'gifts_screen.dart';
import 'chat_list_screen.dart';
import 'profile_screen.dart';

/// Ajustes estilo Telegram: cuenta, notificaciones, almacenamiento,
/// privacidad (amigos/bloqueados) y acceso a la tienda de gifts.
class SettingsChatScreen extends StatelessWidget {
  const SettingsChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [AjustesChat.instance, Account.instance, ChatStorage.instance]),
      builder: (context, _) => Scaffold(
        backgroundColor: Tg.bg,
        appBar: AppBar(backgroundColor: Tg.panel, title: const Text('Ajustes')),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          // Cabecera de cuenta -> abre perfil propio
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProfileScreen(esPropio: true))),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Tg.panel, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor:
                      Account.instance.color.claro.withValues(alpha: .3),
                  child: Text(Account.instance.nombre[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24, color: Colors.white)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(Account.instance.nombre,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('${Account.instance.telefono} · ${Account.instance.username}',
                        style: const TextStyle(fontSize: 12.5, color: Tg.subtitulo)),
                    Text('💎 ${Account.instance.coins} coins',
                        style: const TextStyle(fontSize: 12.5, color: Tg.accent)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Tg.subtitulo),
              ]),
            ),
          ),
          const SizedBox(height: 14),

          _titulo(context, 'Notificaciones'),
          _grupo([
            _switch(Icons.notifications_active_rounded, 'Notificaciones',
                AjustesChat.instance.notificaciones,
                (v) => AjustesChat.instance.set(notificaciones: v)),
            _switch(Icons.music_note_rounded, 'Sonidos', AjustesChat.instance.sonidos,
                (v) => AjustesChat.instance.set(sonidos: v)),
            _switch(Icons.vibration_rounded, 'Vibración', AjustesChat.instance.vibrar,
                (v) => AjustesChat.instance.set(vibrar: v)),
          ]),

          _titulo(context, 'Chat'),
          _grupo([
            _switch(Icons.circle_outlined, 'Mostrar estados',
                AjustesChat.instance.mostrarEstados,
                (v) => AjustesChat.instance.set(mostrarEstados: v)),
            _switch(Icons.download_rounded, 'Auto-descargar media',
                AjustesChat.instance.autodownloadMedia,
                (v) => AjustesChat.instance.set(autodownloadMedia: v)),
          ]),
          _grupo([
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(children: [
                const Icon(Icons.format_size_rounded, size: 20, color: Tg.accent),
                const SizedBox(width: 14),
                const Text('Tamaño del texto'),
                const Spacer(),
                Text(AjustesChat.instance.tamanoTexto.toStringAsFixed(0),
                    style: const TextStyle(color: Tg.subtitulo)),
              ]),
            ),
            Slider(
              value: AjustesChat.instance.tamanoTexto,
              min: 12,
              max: 22,
              divisions: 10,
              activeColor: Tg.accent,
              onChanged: (v) => AjustesChat.instance.set(tamanoTexto: v),
            ),
          ]),

          _titulo(context, 'Datos y almacenamiento'),
          _grupo([
            ListTile(
              leading: const Icon(Icons.storage_rounded, color: Tg.accent),
              title: const Text('Uso de almacenamiento'),
              subtitle: Text(
                  '${ChatStorage.instance.fotosTxt} fotos · ${ChatStorage.instance.videosTxt} videos · ${ChatStorage.instance.docsTxt} docs',
                  style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Tg.subtitulo),
              onTap: () => _dialogoAlmacenamiento(context),
            ),
          ]),

          _titulo(context, 'Privacidad'),
          _grupo([
            ListTile(
              leading: const Icon(Icons.group_rounded, color: Tg.accent),
              title: Text('Amigos (${Account.instance.amigosIds.length})'),
              trailing: const Icon(Icons.chevron_right_rounded, color: Tg.subtitulo),
              onTap: () => _listaUsuarios(
                  context, 'Amigos', Account.instance.amigosIds.toList()),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
              title: Text('Bloqueados (${Account.instance.bloqueadosIds.length})'),
              trailing: const Icon(Icons.chevron_right_rounded, color: Tg.subtitulo),
              onTap: () => _listaUsuarios(
                  context, 'Bloqueados', Account.instance.bloqueadosIds.toList()),
            ),
          ]),

          _titulo(context, 'Gifts'),
          _grupo([
            ListTile(
              leading: const Icon(Icons.card_giftcard_rounded, color: Colors.purpleAccent),
              title: const Text('Tienda de gifts'),
              subtitle: Text('Enviale un regalo a tus contactos · 💎 ${Account.instance.coins}',
                  style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Tg.subtitulo),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GiftsScreen())),
            ),
          ]),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------

  void _dialogoAlmacenamiento(BuildContext context) {
    final s = ChatStorage.instance;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Tg.panel,
        title: const Text('Almacenamiento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _barraCat('Fotos', s.fotosTxt, s.fotosMb, Colors.purpleAccent),
          _barraCat('Videos', s.videosTxt, s.videosMb, Colors.orangeAccent),
          _barraCat('Documentos', s.docsTxt, s.docsMb, Tg.accent),
          _barraCat('Otros', s.otrosTxt, s.otrosMb, Colors.greenAccent),
          const SizedBox(height: 10),
          Text('Libre: ${s.libreTxt}', style: const TextStyle(color: Tg.subtitulo)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              s.limpiarCache();
              Navigator.of(context).pop();
            },
            child: const Text('Limpiar caché'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _barraCat(String t, String txt, double mb, Color c) {
    final frac = (mb / ChatStorage.instance.usadoMb).clamp(0.02, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('$t ', style: const TextStyle(fontSize: 13)),
          Text(txt, style: const TextStyle(fontSize: 13, color: Tg.subtitulo)),
        ]),
        const SizedBox(height: 4),
        FractionallySizedBox(
          widthFactor: frac,
          child: Container(height: 6, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        ),
      ]),
    );
  }

  void _listaUsuarios(BuildContext context, String titulo, List<String> ids) {
    final server = MockServer.instance;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Tg.bg,
        appBar: AppBar(backgroundColor: Tg.panel, title: Text(titulo)),
        body: ids.isEmpty
            ? const Center(child: Text('Nadie acá todavía'))
            : ListView.builder(
                itemCount: ids.length,
                itemBuilder: (_, i) {
                  final u = server.usuarios[ids[i]];
                  if (u == null) return const SizedBox.shrink();
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: u.color.oscuro,
                      child: Text(u.inicial, style: const TextStyle(color: Colors.white)),
                    ),
                    title: Text(u.nombre),
                    subtitle: Text(u.username),
                    trailing: titulo == 'Bloqueados'
                        ? IconButton(
                            icon: const Icon(Icons.lock_open_rounded, color: Tg.accent),
                            tooltip: 'Desbloquear',
                            onPressed: () =>
                                Account.instance.toggleBloqueo(u.id))
                        : null,
                  );
                },
              ),
      ),
    ));
  }

  Widget _titulo(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 0, 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w600, color: Tg.subtitulo)),
      );

  Widget _grupo(List<Widget> hijos) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Tg.panel, borderRadius: BorderRadius.circular(14)),
        child: Column(children: hijos),
      );

  Widget _switch(IconData i, String t, bool v, ValueChanged<bool> on) => SwitchListTile(
        secondary: Icon(i, color: Tg.accent),
        title: Text(t),
        value: v,
        activeColor: Tg.accent,
        onChanged: on,
      );
}
