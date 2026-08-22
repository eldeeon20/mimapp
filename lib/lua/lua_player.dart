part of 'lua_controller.dart';

/// Globals del reproductor (media_kit / libmpv). Solo se registran si hay
/// un [MediaPlayer] conectado. Cada handler delega en el reproductor
/// compartido; el estado (status/posición) se consulta bajo demanda.
void _registerPlayerGlobals(LuaController c) {
  if (c.mediaPlayer == null) return;
  c._registerSync('player_pick', (ls) => _luaPlayerPick(ls, c));
  c._registerSync('player_open', (ls) => _luaPlayerOpen(ls, c));
  c._registerSync('player_play', (ls) => _luaPlayerPlay(ls, c));
  c._registerSync('player_pause', (ls) => _luaPlayerPause(ls, c));
  c._registerSync('player_toggle', (ls) => _luaPlayerToggle(ls, c));
  c._registerSync('player_stop', (ls) => _luaPlayerStop(ls, c));
  c._registerSync('player_status', (ls) => _luaPlayerStatus(ls, c));
}

/// Abre el selector de archivos de Android y reproduce lo elegido.
int _luaPlayerPick(LuaState ls, LuaController c) {
  ls.pop(0);
  c.mediaPlayer!.pickAndPlay();
  return 0;
}

/// Reproduce una ruta, p. ej. player_open("/storage/emulated/0/Music/x.mp3").
int _luaPlayerOpen(LuaState ls, LuaController c) {
  final path = ls.checkString(1) ?? '';
  ls.pop(1);
  if (path.isNotEmpty) c.mediaPlayer!.openPath(path);
  return 0;
}

int _luaPlayerPlay(LuaState ls, LuaController c) {
  ls.pop(0);
  c.mediaPlayer!.play();
  return 0;
}

int _luaPlayerPause(LuaState ls, LuaController c) {
  ls.pop(0);
  c.mediaPlayer!.pause();
  return 0;
}

int _luaPlayerToggle(LuaState ls, LuaController c) {
  ls.pop(0);
  c.mediaPlayer!.playOrPause();
  return 0;
}

int _luaPlayerStop(LuaState ls, LuaController c) {
  ls.pop(0);
  c.mediaPlayer!.stop();
  return 0;
}

/// Devuelve el estado actual del reproductor.
int _luaPlayerStatus(LuaState ls, LuaController c) {
  ls.pop(0);
  ls.pushString(c.mediaPlayer!.status);
  return 1;
}
