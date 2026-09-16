import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Base compartida del media_server: carpeta de moldes, validaciones y
/// modelos. El MOTOR no toca SQL: la SQL es del que usa el server (él
/// guarda las filas que `crear` devuelve). Ver [indice_sql.dart] para
/// el helper SQL opcional de demo.
class MediaBase {
  MediaBase._();

  static const tablaMoldes = 'moldes';
  static const tablaArchivos = 'archivos';

  /// 8 tags de hasta 16 caracteres por archivo (para filtrar).
  static const maxTags = 8;
  static const maxTagLen = 16;

  static final validoNombre = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  static void exigirNombre(String que, String v) {
    if (!validoNombre.hasMatch(v)) {
      throw ArgumentError(
          'media_server: $que inválido "$v" (letras, dígitos, - y _, 1-40)');
    }
  }

  /// Tags saneados: hasta 8, recortados, sin vacíos duplicados.
  /// Más de 16 caracteres o más de 8 → error (no se trunca en silencio).
  static List<String> sanearTags(List<String> tags) {
    if (tags.length > maxTags) {
      throw ArgumentError(
          'media_server: máximo $maxTags tags (vinieron ${tags.length})');
    }
    final vistos = <String>{};
    final out = <String>[];
    for (final t in tags) {
      final s = t.trim();
      if (s.isEmpty) continue;
      if (s.length > maxTagLen) {
        throw ArgumentError(
            'media_server: tag "$s" pasa de $maxTagLen caracteres');
      }
      if (vistos.add(s)) out.add(s);
    }
    return out;
  }

  /// Carpeta donde viven los `<nombre>.mld` (UN solo archivo por
  /// molde, appSupport/media_server/).
  static Future<Directory> carpetaMoldes() async {
    final dir = await getApplicationSupportDirectory();
    final carpeta = Directory('${dir.path}/media_server');
    await carpeta.create(recursive: true);
    return carpeta;
  }

  static Future<File> archivoMolde(String nombre) async {
    exigirNombre('molde', nombre);
    final carpeta = await carpetaMoldes();
    return File('${carpeta.path}/$nombre.mld');
  }

  /// Fila de archivos → mapa listo para guardar en TU sql
  /// (ver helper opcional [indice_sql.dart]).
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

/// Un archivo dentro de un molde (leído de la SQL).
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

  /// Tamaño del trozo GCM en claro (0 = molde XOR viejo).
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

/// Un molde (bloque único).
/// La CLAVE es la misma que abre tu SQL (no se guarda): solo viaja la
/// sal. `semilla` existe solo en moldes xor viejos.
class MoldeInfo {
  final String nombre;
  final String ruta;
  final int fecha;
  final int total;

  /// Sal hex del molde (deriva claves) + cifrado ('gcm-c' o 'xor').
  final String sal;
  final String cifrado;

  /// Solo moldes xor viejos (compatibilidad).
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
