import 'dart:io';

import 'package:flutter/material.dart';

/// Tipos de chat soportados por la réplica.
enum ChatType { privado, grupo, canal, bot, guardados }

/// Estado de entrega de un mensaje (ticks de Telegram).
enum MsgStatus { enviando, enviado, leido }

/// Tipo de adjunto.
enum MediaType { imagen, video, archivo, audio }

class User {
  final String id;
  String nombre;
  String username;
  String telefono;
  String bio;
  ColorSeed color;
  bool online;
  DateTime? ultimaVez;

  User({
    required this.id,
    required this.nombre,
    required this.username,
    this.telefono = '',
    this.bio = '',
    ColorSeed? color,
    this.online = false,
    this.ultimaVez,
  }) : color = color ?? ColorSeed.values[id.hashCode.abs() % ColorSeed.values.length];

  String get inicial => nombre.isEmpty ? '?' : nombre[0].toUpperCase();

  String get estadoConexion {
    if (online) return 'en línea';
    final u = ultimaVez;
    if (u == null) return 'desconocido';
    final d = DateTime.now().difference(u);
    if (d.inMinutes < 1) return 'visto hace un momento';
    if (d.inHours < 1) return 'visto hace ${d.inHours} h';
    if (d.inDays < 1) return 'visto hace ${d.inHours} h';
    return 'visto hace ${d.inDays} d';
  }
}

/// Colores de avatar predefinidos (gradientes estilo Telegram).
enum ColorSeed {
  azul(Color(0xFF2EA6FF), Color(0xFF1B74D0)),
  violeta(Color(0xFFB57CFF), Color(0xFF834BF5)),
  verde(Color(0xFF4DDC84), Color(0xFF22B573)),
  naranja(Color(0xFFFFB74D), Color(0xFFF57C00)),
  rosa(Color(0xFFFF80AB), Color(0xFFF50057)),
  cyan(Color(0xFF4DD0E1), Color(0xFF0097A7));

  final Color claro;
  final Color oscuro;
  const ColorSeed(this.claro, this.oscuro);
}

class MediaAttachment {
  final MediaType tipo;
  final File? archivo;
  final String nombre;
  final int sizeBytes;
  final Duration duracion;

  MediaAttachment({
    required this.tipo,
    this.archivo,
    required this.nombre,
    this.sizeBytes = 0,
    this.duracion = Duration.zero,
  });

  String get sizeLegible {
    if (sizeBytes <= 0) return '';
    const u = ['B', 'KB', 'MB', 'GB'];
    var s = sizeBytes.toDouble();
    var i = 0;
    while (s >= 1024 && i < u.length - 1) {
      s /= 1024;
      i++;
    }
    return '${s.toStringAsFixed(s < 10 && i > 0 ? 1 : 0)} ${u[i]}';
  }
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  String texto;
  final DateTime hora;
  MsgStatus status;
  Message? respuestaA;
  final MediaAttachment? media;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.texto = '',
    DateTime? hora,
    this.status = MsgStatus.enviado,
    this.respuestaA,
    this.media,
  }) : hora = hora ?? DateTime.now();

  bool get mia => senderId == 'yo';

  /// Waveform pseudoaleatoria pero estable por mensaje (barras de voz).
  List<int> get waveform {
    var seed = id.hashCode;
    return List.generate(28, (_) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return 4 + (seed >> 16) % 24;
    });
  }
}

class Chat {
  final String id;
  final String nombre;
  final ChatType tipo;
  ColorSeed color;
  String descripcion;
  int miembros;
  bool fijado;
  bool silenciado;
  int noLeidos;

  Chat({
    required this.id,
    required this.nombre,
    required this.tipo,
    ColorSeed? color,
    this.descripcion = '',
    this.miembros = 0,
    this.fijado = false,
    this.silenciado = false,
    this.noLeidos = 0,
  }) : color = color ?? ColorSeed.values[nombre.hashCode.abs() % ColorSeed.values.length];

  String get inicial => nombre.isEmpty ? '?' : nombre[0].toUpperCase();
  bool get esCanal => tipo == ChatType.canal;
  bool get esGrupo => tipo == ChatType.grupo;
}

/// Item de un estado (historia). Contenido simulado con gradiente.
class StoryItem {
  final String id;
  final String titulo;
  final ColorSeed color;
  final IconData? icono;
  final DateTime hora;

  StoryItem({
    required this.id,
    required this.titulo,
    ColorSeed? color,
    this.icono,
    DateTime? hora,
  })  : color = color ?? ColorSeed.azul,
        hora = hora ?? DateTime.now();
}

class Story {
  final String userId;
  final List<StoryItem> items;
  bool vista;

  Story({required this.userId, required this.items, this.vista = false});
}

/// Gift de la tienda (se compra con coins simuladas).
class Gift {
  final String id;
  final String emoji;
  final String nombre;
  final int precio;

  const Gift(this.id, this.emoji, this.nombre, this.precio);
}
