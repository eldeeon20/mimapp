/// SERVIDOR de moldes (idiota: solo bytes crudos del `.mld`).
///
/// El server NO abre SQL y NO recibe clave: `abrir(rutaMld:)` + `leer`.
/// El USER (su SQL) calcula trozos, pide crudo y descifra con [Duro].
/// La HERRAMIENTA que crea molde+SQL vive en `toolsec/`:
///
/// ```dart
/// // Tool (una vez): carpeta → musica.mld + índice en TU sql.
/// await CreateMoldeSql.crear(
///   nombre: 'musica', origenDir: '/sdcard/audio', clave: 'una-sola',
///   tags: ['audio'],
/// );
/// // User: lee TU sql y pide al server.
/// final server = await MediaServer.abrir(rutaMld: '/.../musica.mld');
/// final crudo = await server.leer(absoluto: 0, largo: 222);
/// ```
library;

export 'base.dart';
export 'duro.dart';
export 'servir.dart';
