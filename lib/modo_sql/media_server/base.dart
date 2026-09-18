import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Base: carpeta de moldes, validaciones y modelos.
class MediaBase {
  MediaBase._();

  static const tablaMoldes = 'moldes';
  static const tablaArchivos = 'archivos';

  static const maxTags = 8;
  static const maxTagLen = 16;

  static final validoNombre = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  static void exigirNombre(String que, String v) {
    if (!validoNombre.hasMatch(v)) {
      throw ArgumentError(
          'test_sql: $que inválido "$v" (letras, dígitos, - y _, 1-40)');
    }
  }

  static List<String> sanearTags(List<String> tags) {
    if (tags.length > maxTags) {
      throw ArgumentError(
          'test_sql: máximo $maxTags tags (vinieron ${tags.length})');
    }
    final vistos = <String>{};
    final out = <String>[];
    for (final t in tags) {
      final s = t.trim();
      if (s.isEmpty) continue;
      if (s.length > maxTagLen) {
        throw ArgumentError(
            'test_sql: tag "$s" pasa de $maxTagLen caracteres');
      }
      if (vistos.add(s)) out.add(s);
    }
    return out;
  }

  /// Carpeta visible: Download/test_sql en Android (los .mld a mano),
  /// soporte si Download no se puede escribir (o no es Android).
  static Future<Directory> carpetaMoldes() async {
    final down = await carpetaDescargas();
    if (down != null) return down;
    final dir = await getApplicationSupportDirectory();
    final carpeta = Directory('${dir.path}/media_server');
    await carpeta.create(recursive: true);
    return carpeta;
  }

  /// Download/test_sql o null si no se puede (ahí se usa soporte).
  static Future<Directory?> carpetaDescargas() async {
    if (!Platform.isAndroid) return null;
    try {
      final d = Directory('/storage/emulated/0/Download/test_sql');
      await d.create(recursive: true);
      return d;
    } catch (_) {
      return null;
    }
  }

  static Future<File> archivoMolde(String nombre) async {
    exigirNombre('molde', nombre);
    final carpeta = await carpetaMoldes();
    return File('${carpeta.path}/$nombre.mld');
  }

  static Map<String, Object?> filaArchivo({
    required String molde,
    required String nombre,
    required String formato,
    required int tamano,
    required int inicio,
    required int fin,
    required int fecha,
    required List<String> tags,
    int trozo = 0,
  }) {
    final saneados = sanearTags(tags);
    final m = <String, Object?>{
      'molde': molde,
      'nombre': nombre,
      'formato': formato,
      'tamano': tamano,
      'inicio': inicio,
      'fin': fin,
      'fecha': fecha,
      'trozo': trozo,
    };
    for (var i = 0; i < maxTags; i++) {
      m['tag${i + 1}'] = i < saneados.length ? saneados[i] : '';
    }
    return m;
  }
}

class FichaArchivo {
  final int id;
  final String molde;
  final String nombre;
  final String formato;
  final int tamano;
  final int inicio;
  final int fin;
  final int fecha;
  final List<String> tags;
  final int trozo;

  FichaArchivo({
    required this.id,
    required this.molde,
    required this.nombre,
    required this.formato,
    required this.tamano,
    required this.inicio,
    required this.fin,
    required this.fecha,
    required this.tags,
    this.trozo = 0,
  });

  factory FichaArchivo.deMapa(Map<String, Object?> m) {
    final tags = <String>[];
    for (var i = 1; i <= MediaBase.maxTags; i++) {
      final t = '${m['tag$i'] ?? ''}';
      if (t.isNotEmpty) tags.add(t);
    }
    return FichaArchivo(
      id: (m['id'] as int?) ?? 0,
      molde: '${m['molde'] ?? ''}',
      nombre: '${m['nombre'] ?? ''}',
      formato: '${m['formato'] ?? ''}',
      tamano: (m['tamano'] as int?) ?? 0,
      inicio: (m['inicio'] as int?) ?? 0,
      fin: (m['fin'] as int?) ?? 0,
      fecha: (m['fecha'] as int?) ?? 0,
      tags: tags,
      trozo: (m['trozo'] as int?) ?? 0,
    );
  }
}

class MoldeInfo {
  final String nombre;
  final String ruta;
  final int fecha;
  final int total;
  final String sal;
  final String cifrado;
  final String semilla;

  MoldeInfo({
    required this.nombre,
    required this.ruta,
    required this.fecha,
    required this.total,
    this.sal = '',
    this.cifrado = '',
    this.semilla = '',
  });

  factory MoldeInfo.deMapa(Map<String, Object?> m) => MoldeInfo(
        nombre: '${m['nombre'] ?? ''}',
        ruta: '${m['ruta'] ?? ''}',
        fecha: (m['fecha'] as int?) ?? 0,
        total: (m['total'] as int?) ?? 0,
        sal: '${m['sal'] ?? ''}',
        cifrado: '${m['cifrado'] ?? ''}',
        semilla: '${m['semilla'] ?? ''}',
      );
}
