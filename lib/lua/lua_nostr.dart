part of 'lua_controller.dart';

/// Globals nostr_dm_* / nostr_obs_*: chats Nostr desde Lua vía jobs.
/// Relays como argumento opcional "r1|r2|..." (vacío = defaults).
///
///   id = dm_connect_start(nsec, npub_peer [, relays_csv])
///   id = dm_send_start(mensaje)
///   id = dm_poll_start()
///   id = obs_connect_start(shared_hex [, relays_csv])
///   id = obs_poll_start()
void registerNostrGlobals(LuaController c) {
  c._registerSync('dm_connect_start', (ls) => _luaDmConnect(ls, c));
  c._registerSync('dm_send_start', (ls) => _luaDmSend(ls, c));
  c._registerSync('dm_poll_start', (ls) => _luaDmPoll(ls, c));
  c._registerSync('obs_connect_start', (ls) => _luaObsConnect(ls, c));
  c._registerSync('obs_poll_start', (ls) => _luaObsPoll(ls, c));
}

// Combo probado de Gtool: nos.lol (DM) + primal.net (lectura).
// nostr.wine es de pago y no entrega gift wraps anónimos.
const _nostrDefaults = [
  'wss://nos.lol',
  'wss://relay.primal.net',
];

List<String> _relaysArg(LuaState ls, int idx) {
  if (!ls.isString(idx)) return List.of(_nostrDefaults);
  final csv = ls.toStr(idx) ?? '';
  if (csv.trim().isEmpty) return List.of(_nostrDefaults);
  return csv.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
}

NostrChat? _dmChat;
NostrPeerChat? _obsChat;

int _luaDmConnect(LuaState ls, LuaController c) {
  final nsec = ls.checkString(1) ?? '';
  final peer = ls.checkString(2) ?? '';
  final relays = _relaysArg(ls, 3);
  ls.pop(ls.getTop());
  ls.pushInteger(c.jobStart(() async {
    try {
      await _dmChat?.close();
      final chat = NostrChat();
      await chat.init(
        nsec: nsec.isEmpty ? null : nsec,
        peerNpub: peer,
        dmRelays: relays,
      );
      _dmChat = chat;
      final pk = await chat.publicKey();
      return jobJson({'ok': true, 'mi_npub': pk});
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaDmSend(LuaState ls, LuaController c) {
  final msg = ls.checkString(1) ?? '';
  ls.pop(1);
  ls.pushInteger(c.jobStart(() async {
    try {
      final chat = _dmChat;
      if (chat == null || !chat.connected) return 'ERROR: DM no conectado';
      await chat.send(msg);
      return 'OK enviado';
    } catch (e) {
      return 'ERROR: $e';
    }
  }));
  return 1;
}

int _luaDmPoll(LuaState ls, LuaController c) {
  ls.pushInteger(c.jobStart(() async {
    try {
      final chat = _dmChat;
      if (chat == null || !chat.connected) return jobJson({'msgs': []});
      final msgs = await chat.poll(timeoutSecs: 2);
      return jobJson({
        'ok': true,
        'n': msgs.length,
        'msgs': [for (final m in msgs) m.content],
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}

int _luaObsConnect(LuaState ls, LuaController c) {
  final shared = ls.checkString(1) ?? '';
  final relays = _relaysArg(ls, 2);
  ls.pop(ls.getTop());
  ls.pushInteger(c.jobStart(() async {
    try {
      await _obsChat?.close();
      final chat = await NostrPeerChat.create();
      await chat.initObserver(sharedKeyHex: shared, relays: relays);
      _obsChat = chat;
      return 'OK: observador conectado';
    } catch (e) {
      return 'ERROR: $e';
    }
  }));
  return 1;
}

int _luaObsPoll(LuaState ls, LuaController c) {
  ls.pushInteger(c.jobStart(() async {
    try {
      final chat = _obsChat;
      if (chat == null) return jobJson({'msgs': []});
      final msgs = await chat.poll();
      return jobJson({
        'ok': true,
        'n': msgs.length,
        'msgs': [for (final m in msgs) '${m.pubkey}: ${m.content}'],
      });
    } catch (e) {
      return jobJson({'ok': false, 'error': '$e'});
    }
  }));
  return 1;
}
