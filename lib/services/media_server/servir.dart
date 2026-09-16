import 'dart:io';
import 'dart:typed_data';

/// SERVIDOR de moldes, idiota a propósito: NO recibe clave, NI filas,
/// NI abre SQL. Solo lee bytes crudos del `.mld` por offset absoluto.
///
/// El USER (que abrió SU sql) tiene todo: calcula los trozos con
/// [Duro], pide crudo acá y descifra allá ([Duro.descifrarRango]).
/// Sin tu SQL el server no sabe qué trae el molde.
class MediaServer {
  MediaServer._();

  /// Abre el `.mld` (solo verifica que exista). Una vez por molde.
  static Future<MoldeAbierto> abrir({required String rutaMld}) async {
    final f = File(rutaMld);
    if (!await f.exists()) {
      throw StateError('media_server: no existe el bloque "$rutaMld"');
    }
    final tam = await f.length();
    return MoldeAbierto._(ruta: rutaMld, total: tam);
  }
}

/// Un `.mld` abierto: bomba de bytes crudos.
class MoldeAbierto {
  final String ruta;

  /// Largo total del bloque en disco.
  final int total;

  MoldeAbierto._({required this.ruta, required this.total});

  /// Lee [largo] bytes crudos desde [absoluto]. Fuera del bloque →
  /// error legible (no se recorta solo).
  Future<Uint8List> leer({
    required int absoluto,
    required int largo,
  }) async {
    if (absoluto < 0 || largo < 0) {
      throw ArgumentError(
          'media_server: lectura negativa [$absoluto, $largo)');
    }
    if (largo == 0) return Uint8List(0);
    if (absoluto + largo > total) {
      throw ArgumentError('media_server: [$absoluto, $largo) pasa el '
          'bloque ($total bytes)');
    }
    final raf = File(ruta).openSync(mode: FileMode.read);
    try {
      raf.setPositionSync(absoluto);
      final datos = raf.readSync(largo);
      if (datos.length != largo) {
        throw StateError(
            'media_server: el bloque se cortó en [$absoluto, $largo)');
      }
      return datos;
    } finally {
      try {
        raf.closeSync();
      } catch (_) {}
    }
  }
}
