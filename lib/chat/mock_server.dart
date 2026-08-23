import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'models.dart';

/// "Server" simulado: guarda todo en memoria, responde con delays y
/// respuestas de eco para que la demo se sienta viva. Sin red.
class MockServer extends ChangeNotifier {
  MockServer._();
  static final MockServer instance = MockServer._();

  final List<Chat> chats = [];
  final Map<String, List<Message>> _mensajes = {};
  final Map<String, User> usuarios = {};
  final Map<String, Story> estados = {};
  final List<Gift> gifts = const [
    Gift('g1', '🎁', 'Caja sorpresa', 25),
    Gift('g2', '🌹', 'Rosa eterna', 50),
    Gift('g3', '🧸', 'Osito', 100),
    Gift('g4', '💎', 'Diamante', 250),
    Gift('g5', '🚀', 'Cohete', 500),
    Gift('g6', '👑', 'Corona', 1000),
  ];

  /// chatId -> el otro está escribiendo.
  final Set<String> escribiendo = {};
  final Random _rnd = Random();

  // ------------------------------------------------------------------
  // Carga inicial
  // ------------------------------------------------------------------

  bool _cargado = false;

  void ensureSeed() {
    if (_cargado) return;
    _cargado = true;

    void u(String id, String nombre, String username,
        {bool online = false, int haceMin = 30, String bio = ''}) {
      usuarios[id] = User(
        id: id,
        nombre: nombre,
        username: username,
        online: online,
        ultimaVez: DateTime.now().subtract(Duration(minutes: haceMin)),
        bio: bio,
      );
    }

    u('u1', 'Ana García', '@anag', online: true, bio: 'Diseñadora UX');
    u('u2', 'Carlos Ruiz', '@cruiz', haceMin: 45);
    u('u3', 'Lucía Fernández', '@lufern', online: true, bio: 'Dev Flutter');
    u('u4', 'Martín López', '@mlopez', haceMin: 180);
    u('u5', 'Sofía Torres', '@storres', haceMin: 1440);
    u('u6', 'Diego Martínez', '@dmartinez', haceMin: 15);

    // Los chats privados usan el MISMO id del usuario para que
    // usuarioDe() resuelva directo.
    chats.addAll([
      Chat(
        id: 'u1',
        nombre: 'Ana García',
        tipo: ChatType.privado,
        color: ColorSeed.rosa,
        fijado: true,
        noLeidos: 2,
      ),
      Chat(
        id: 'c2',
        nombre: 'Dev Team',
        tipo: ChatType.grupo,
        miembros: 12,
        descripcion: 'Proyecto mimapp · builds y bugs',
        noLeidos: 5,
      ),
      Chat(
        id: 'c3',
        nombre: 'Noticias Hoy',
        tipo: ChatType.canal,
        miembros: 154320,
        descripcion: 'Titulares del día, sin humo.',
        silenciado: true,
      ),
      Chat(
        id: 'u2',
        nombre: 'Carlos Ruiz',
        tipo: ChatType.privado,
      ),
      Chat(
        id: 'c5',
        nombre: 'Memes 😂',
        tipo: ChatType.canal,
        miembros: 891004,
        descripcion: 'El mejor contenido (dudoso) de internet',
      ),
      Chat(
        id: 'c6',
        nombre: 'Familia',
        tipo: ChatType.grupo,
        miembros: 6,
        fijado: true,
      ),
      Chat(
        id: 'u3',
        nombre: 'Lucía Fernández',
        tipo: ChatType.privado,
        color: ColorSeed.violeta,
      ),
      Chat(
        id: 'c8',
        nombre: 'Gym Brotes',
        tipo: ChatType.grupo,
        miembros: 4,
        silenciado: true,
      ),
    ]);

    Message m(String chatId, String senderId, String texto,
        {int haceMin = 0, MsgStatus st = MsgStatus.leido}) {
      final msg = Message(
        id: 'seed_${chatId}_${_mensajes[chatId]?.length ?? 0}',
        chatId: chatId,
        senderId: senderId,
        texto: texto,
        hora: DateTime.now().subtract(Duration(minutes: haceMin)),
        status: st,
      );
      (_mensajes[chatId] ??= []).add(msg);
      return msg;
    }

    m('u1', 'u1', '¡Hola! ¿Viste la nueva demo?', haceMin: 55);
    m('u1', 'yo', 'Todavía no, ¿cómo está?', haceMin: 53);
    m('u1', 'u1', 'Quedó increíble 🔥', haceMin: 50);
    m(
      'u1',
      'u1',
      'Te mando las capturas en un rato',
      haceMin: 8,
      st: MsgStatus.enviado,
    );

    m('c2', 'u3', 'Build verde en Actions ✅', haceMin: 120);
    m('c2', 'yo', 'Buenísimo, mergeo después', haceMin: 118);
    m('c2', 'u6', 'Ojo con el fix de Rust que pushearon', haceMin: 30);

    m('c3', 'c3', '📌 Titular: Flutter 3.x mejora el rendimiento en Android',
        haceMin: 200);
    m('c3', 'c3', 'Nueva actualización de Rust trae mejoras de borrow checker',
        haceMin: 90);

    m('u2', 'u2', '¿Jugamos algo más tarde?', haceMin: 300);
    m('u2', 'yo', 'Dale, a las 22 me parece', haceMin: 290);

    m('c5', 'c5', 'Cuando el código compila a la primera 🤖', haceMin: 500);

    m('c6', 'u5', '¿Quién trae la torta el domingo?', haceMin: 700);
    m('c6', 'yo', 'Yo me encargo 🎂', haceMin: 690);

    m('u3', 'u3', 'Pasame el diseño del onboarding cuando puedas', haceMin: 35);

    m('c8', 'u4', 'Mañana pierna 🦵', haceMin: 900);

    estados.addAll({
      'u1': Story(userId: 'u1', items: [
        StoryItem(id: 's1', titulo: 'Sunset en la ciudad', color: ColorSeed.naranja),
        StoryItem(id: 's2', titulo: 'Nuevo proyecto 👩‍💻', color: ColorSeed.rosa),
      ]),
      'u3': Story(
          userId: 'u3', vista: true, items: [
        StoryItem(id: 's3', titulo: 'Deploy day!', color: ColorSeed.verde),
      ]),
      'u6': Story(userId: 'u6', items: [
        StoryItem(id: 's4', titulo: 'Gym 💪', color: ColorSeed.cyan),
      ]),
    });
  }

  // ------------------------------------------------------------------
  // Consultas
  // ------------------------------------------------------------------

  List<Message> mensajes(String chatId) => _mensajes[chatId] ??= [];

  Message? ultimoMensaje(String chatId) {
    final l = _mensajes[chatId];
    return (l == null || l.isEmpty) ? null : l.last;
  }

  Chat? chatPorId(String id) =>
      chats.where((c) => c.id == id).firstOrNull;

  User? usuarioDe(Chat c) =>
      c.tipo == ChatType.privado ? usuarios[c.id] : null;

  // ------------------------------------------------------------------
  // Envío (simulado)
  // ------------------------------------------------------------------

  Message nuevoLocal(String chatId,
      {String texto = '', MediaAttachment? media, Message? respuestaA}) {
    final m = Message(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      chatId: chatId,
      senderId: 'yo',
      texto: texto,
      status: MsgStatus.enviando,
      respuestaA: respuestaA,
      media: media,
    );
    mensajes(chatId).add(m);
    notifyListeners();
    return m;
  }

  /// Flujo completo de envío: enviando → enviado → leído → typing → respuesta.
  Future<void> enviar(String chatId,
      {String texto = '', MediaAttachment? media, Message? respuestaA}) async {
    final m = nuevoLocal(chatId, texto: texto, media: media, respuestaA: respuestaA);

    unawaited(Future.delayed(const Duration(milliseconds: 400), () {
      m.status = MsgStatus.enviado;
      notifyListeners();
    }));

    // Respuesta automática solo en chats privados/grupos (no canales).
    final chat = chatPorId(chatId);
    if (chat == null || chat.esCanal) return;

    await Future.delayed(const Duration(milliseconds: 1200), () {
      m.status = MsgStatus.leido;
      notifyListeners();
    });

    await Future.delayed(const Duration(milliseconds: 600), () {
      escribiendo.add(chatId);
      notifyListeners();
    });

    await Future.delayed(Duration(milliseconds: 1200 + _rnd.nextInt(1500)), () {
      escribiendo.remove(chatId);
      final remitente =
          chat.esGrupo ? _autorGrupo(chatId) : (usuarios[chatId]?.id ?? chatId);
      final msg = Message(
        id: 'resp_${DateTime.now().microsecondsSinceEpoch}',
        chatId: chatId,
        senderId: remitente,
        texto: _respuesta(texto),
      );
      mensajes(chatId).add(msg);
      notifyListeners();
    });
  }

  String _autorGrupo(String chatId) {
    final ids = usuarios.keys.where((k) => k != 'yo').toList();
    return ids[_rnd.nextInt(ids.length)];
  }

  String _respuesta(String recibido) {
    final lower = recibido.toLowerCase();
    if (lower.contains('?')) {
      const opts = [
        'Buena pregunta, déjame pensarlo...',
        'Mmm, creo que sí 🤔',
        'No estoy seguro, pregúntale a Ana',
        'Te confirmo en un rato',
      ];
      return opts[_rnd.nextInt(opts.length)];
    }
    if (lower.contains('hola') || lower.contains('buenas')) {
      const opts = ['¡Hola! ¿Cómo andás?', '¡Hey! Todo bien por acá 👋'];
      return opts[_rnd.nextInt(opts.length)];
    }
    const genericas = [
      'Jajaja buenísimo 😂',
      'Dale, de acuerdo ✅',
      'Interesante... seguí contando',
      'Perfecto, lo anoto',
      'Ok! Después te digo',
      '🔥🔥🔥',
    ];
    return genericas[_rnd.nextInt(genericas.length)];
  }

  // ------------------------------------------------------------------
  // Estados / social
  // ------------------------------------------------------------------

  void marcarEstadoVisto(String userId) {
    estados[userId]?.vista = true;
    notifyListeners();
  }

  void marcarLeido(String chatId) {
    final c = chatPorId(chatId);
    if (c != null && c.noLeidos > 0) {
      c.noLeidos = 0;
      for (final m in mensajes(chatId)) {
        if (!m.mia && m.status == MsgStatus.enviado) m.status = MsgStatus.leido;
      }
      notifyListeners();
    }
  }
}
