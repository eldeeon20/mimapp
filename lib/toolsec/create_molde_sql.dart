import 'dart:io';
import 'dart:typed_data';

import '../db/caja_sql.dart';
import '../services/media_server/media_server.dart';

/// HERRAMIENTA create_molde_sql (no es servicio, es de una vez):
/// crea el molde `.mld` + deja su índice en la SQL.
///
/// - El SERVIDOR (`media_server/`) solo sirve el `.mld` (se abre una
///   vez, sin pass SQL): este tool le deja todo armado.
/// - La SQL es del que usa el server: este tool la crea y la llena;
///   después se lee con `filasDe`/`moldeInfo` para abrir el server.
///
/// Esquema (db cifrada ChaCha20, se abre con clave como la agenda):
/// - `moldes(nombre UNIQUE, ruta, semilla, fecha, total, sal, cifrado)`
/// - `archivos(molde, nombre, formato, tamano, inicio, fin, fecha,
///   tag1..tag8, trozo)` + índice `idx_archivos_molde`.
class CreateMoldeSql {
  CreateMoldeSql._();

  static const baseDatos = 'media_server';

  /// Abre (o crea) la db del índice y asegura esquema + migraciones.
  static Future<CajaSql> abrirIndice({required String claveSql}) async {
    if (claveSql.isEmpty) {
      throw ArgumentError('create_molde_sql: la claveSql no puede vacía');
    }
    final caja = CajaSql();
    await caja.abrir(baseDatos, clave: claveSql);
    caja.crearTabla(MediaBase.tablaMoldes, {
      'nombre': 'TEXT UNIQUE',
      'ruta': 'TEXT',
      'semilla': 'TEXT',
      'fecha': 'INTEGER',
      'total': 'INTEGER',
      'sal': 'TEXT',
      'cifrado': 'TEXT',
    });
    if (!caja.campos(MediaBase.tablaMoldes).contains('sal')) {
      caja.agregarCampo(MediaBase.tablaMoldes, 'sal', 'TEXT');
    }
    if (!caja.campos(MediaBase.tablaMoldes).contains('cifrado')) {
      caja.agregarCampo(MediaBase.tablaMoldes, 'cifrado', 'TEXT');
    }
    caja.crearTabla(MediaBase.tablaArchivos, {
      'molde': 'TEXT',
      'nombre': 'TEXT',
      'formato': 'TEXT',
      'tamano': 'INTEGER',
      'inicio': 'INTEGER',
      'fin': 'INTEGER',
      'fecha': 'INTEGER',
      'tag1': 'TEXT',
      'tag2': 'TEXT',
      'tag3': 'TEXT',
      'tag4': 'TEXT',
      'tag5': 'TEXT',
      'tag6': 'TEXT',
      'tag7': 'TEXT',
      'tag8': 'TEXT',
      'trozo': 'INTEGER',
    });
    if (!caja.campos(MediaBase.tablaArchivos).contains('trozo')) {
      caja.agregarCampo(MediaBase.tablaArchivos, 'trozo', 'INTEGER');
    }
    // Índice principal por molde: 'molde_test' trae SOLO sus filas.
    caja.crearIndice(MediaBase.tablaArchivos, 'molde');
    return caja;
  }

  /// Crea `<nombre>.mld` desde [origenDir] (recursivo) + su índice SQL.
  /// Todo cifrado DURO por trozos (clave + sal del molde).
  /// [tags] para todos; [tagsPorArchivo] pisa por nombre relativo.
  /// Devuelve cuántos archivos entraron (el primero siempre en 0).
  static Future<int> crear({
    required String nombre,
    required String origenDir,
    required String clave,
    List<String> tags = const [],
    Map<String, List<String>>? tagsPorArchivo,
    int trozoClaro = Duro.trozoClaro,
  }) async {
    MediaBase.exigirNombre('molde', nombre);
    if (clave.isEmpty) {
      throw ArgumentError('create_molde_sql: la clave no puede vacía');
    }
    if (trozoClaro <= 0) {
      throw ArgumentError('create_molde_sql: trozoClaro debe ser > 0');
    }
    final origen = Directory(origenDir);
    if (!await origen.exists()) {
      throw ArgumentError(
          'create_molde_sql: no existe la carpeta "$origenDir"');
    }
    final comunes = MediaBase.sanearTags(tags);
    final porArchivo = <String, List<String>>{};
    tagsPorArchivo?.forEach((k, v) {
      porArchivo[k] = MediaBase.sanearTags(v);
    });

    final base = origen.uri.toFilePath();
    final fuentes = <File>[];
    await for (final e in origen.list(recursive: true, followLinks: false)) {
      if (e is File) fuentes.add(e);
    }
    String rel(File f) {
      var r = f.uri.toFilePath();
      if (r.startsWith(base)) r = r.substring(base.length);
      return r.replaceAll('\\', '/');
    }

    fuentes.sort((a, b) => rel(a).compareTo(rel(b)));
    if (fuentes.isEmpty) {
      throw StateError('create_molde_sql: "$origenDir" no trae archivos');
    }

    final destino = await MediaBase.archivoMolde(nombre);
    if (await destino.exists()) await destino.delete();
    final sal = Duro.nuevaSal();
    var offset = 0;
    final filas = <Map<String, Object?>>[];
    final waf = destino.openSync(mode: FileMode.write);
    try {
      for (final f in fuentes) {
        final nombreRel = rel(f);
        if (nombreRel.isEmpty) continue;
        final tam = await f.length();
        final fecha = (await f.lastModified()).millisecondsSinceEpoch;
        final claveArchivo = await Duro.claveArchivo(
          clave: clave,
          molde: nombre,
          nombre: nombreRel,
          salHex: sal,
        );
        final raf = f.openSync(mode: FileMode.read);
        var escritos = 0;
        var indice = 0;
        try {
          while (true) {
            final trozo = raf.readSync(trozoClaro);
            if (trozo.isEmpty) break;
            final paquete = await Duro.cifrarTrozo(
              claveArchivo: claveArchivo,
              indice: indice,
              claro: trozo,
            );
            waf.writeFromSync(paquete);
            escritos += trozo.length;
            indice++;
          }
          if (escritos != tam) {
            throw StateError(
                'create_molde_sql: "$nombreRel" cambió mientras se leía');
          }
        } finally {
          try {
            raf.closeSync();
          } catch (_) {}
        }
        // Guardado = claro + overhead de sus trozos (sin padding).
        final guardado = _largoGuardado(tam, trozoClaro);
        filas.add(MediaBase.filaArchivo(
          molde: nombre,
          nombre: nombreRel,
          formato: _formato(nombreRel),
          tamano: tam,
          inicio: offset,
          fin: offset + guardado,
          fecha: fecha,
          tags: porArchivo[nombreRel] ?? comunes,
          trozo: trozoClaro,
        ));
        offset += guardado;
      }
    } finally {
      try {
        waf.closeSync();
      } catch (_) {}
    }
    final caja = await abrirIndice(claveSql: clave);
    try {
      final ya =
          caja.uno(MediaBase.tablaMoldes, 'nombre = ?', [nombre]);
      if (ya != null) {
        throw StateError(
            'create_molde_sql: el molde "$nombre" ya existe (borralo)');
      }
      caja.agregarLote(MediaBase.tablaArchivos, filas);
      caja.agregar(MediaBase.tablaMoldes, {
        'nombre': nombre,
        'ruta': destino.path,
        'semilla': '',
        'fecha': DateTime.now().millisecondsSinceEpoch,
        'total': offset,
        'sal': sal,
        'cifrado': 'gcm-c',
      });
      return filas.length;
    } finally {
      caja.cerrar();
    }
  }

  /// Largo GUARDADO (claro + overhead de trozos, sin padding).
  static int _largoGuardado(int tam, int trozo) {
    if (tam <= 0) return 0;
    final n = (tam + trozo - 1) ~/ trozo;
    return tam + n * Duro.overhead;
  }

  /// Borra el molde: `.mld` + filas del índice.
  static Future<void> borrar({
    required String nombre,
    required String claveSql,
  }) async {
    MediaBase.exigirNombre('molde', nombre);
    final caja = await abrirIndice(claveSql: claveSql);
    try {
      caja.quitarDonde(MediaBase.tablaArchivos, 'molde = ?', [nombre]);
      caja.quitarDonde(MediaBase.tablaMoldes, 'nombre = ?', [nombre]);
    } finally {
      caja.cerrar();
    }
    try {
      final f = await MediaBase.archivoMolde(nombre);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Ficha del molde (para abrir el server).
  static Future<MoldeInfo?> moldeInfo({
    required String claveSql,
    required String molde,
  }) async {
    final caja = await abrirIndice(claveSql: claveSql);
    try {
      final m =
          caja.uno(MediaBase.tablaMoldes, 'nombre = ?', [molde]);
      if (m == null) return null;
      return MoldeInfo.deMapa(m);
    } finally {
      caja.cerrar();
    }
  }

  /// Semilla del molde (la guarda el tool en su SQL).
  static Future<String> semillaDe({
    required String claveSql,
    required String molde,
  }) async {
    final caja = await abrirIndice(claveSql: claveSql);
    try {
      final m =
          caja.uno(MediaBase.tablaMoldes, 'nombre = ?', [molde]);
      final s = '${m?['semilla'] ?? ''}';
      if (s.isEmpty) {
        throw StateError(
            'create_molde_sql: el molde "$molde" no trae semilla');
      }
      return s;
    } finally {
      caja.cerrar();
    }
  }

  /// Filas del molde (SOLO ese, índice idx_archivos_molde).
  static Future<List<FichaArchivo>> filasDe({
    required String claveSql,
    required String molde,
  }) async {
    final caja = await abrirIndice(claveSql: claveSql);
    try {
      final filas = caja.listarDonde(
        MediaBase.tablaArchivos,
        'molde = ?',
        [molde],
        por: 'inicio',
      );
      return [for (final f in filas) FichaArchivo.deMapa(f)];
    } finally {
      caja.cerrar();
    }
  }

  /// Atajo en UNA llamada con TU sql: abre el índice, arma el server
  /// y pide `[desde, hasta)` del archivo. Lo que el server espera al
  /// final: molde + archivo + rango.
  static Future<Uint8List> pedirRango({
    required String claveSql,
    required String molde,
    required String archivo,
    required int desde,
    required int hasta,
  }) async {
    final info = await moldeInfo(claveSql: claveSql, molde: molde);
    if (info == null) {
      throw StateError('create_molde_sql: no existe el molde "$molde"');
    }
    final filas = await filasDe(claveSql: claveSql, molde: molde);
    FichaArchivo? ficha;
    for (final f in filas) {
      if (f.nombre == archivo) {
        ficha = f;
        break;
      }
    }
    if (ficha == null) {
      throw StateError('create_molde_sql: "$archivo" no está en "$molde"');
    }
    final f = ficha;
    if (f.tamano == 0) return Uint8List(0);
    if (desde < 0 || hasta < 0 || desde >= hasta || hasta > f.tamano) {
      throw ArgumentError('create_molde_sql: rango [$desde, $hasta) '
          'fuera de "$archivo" (0..${f.tamano})');
    }
    // El server es idiota: solo bytes crudos por offset. El user
    // (tiene SQL+clave) calcula trozos y descifra.
    final server = await MediaServer.abrir(rutaMld: info.ruta);
    if (f.trozo <= 0) {
      // Molde xor viejo: un solo slice + semilla de tu SQL.
      final crudo = await server.leer(
          absoluto: f.inicio + desde, largo: hasta - desde);
      return Duro.descifrarRango(
        claveArchivo: Uint8List(0),
        rango: RangoCrudo(
          modo: 'xor',
          archivo: archivo,
          desde: desde,
          hasta: hasta,
          trozo: 0,
          tamano: f.tamano,
          paquetes: [PaqueteCrudo(desde, crudo)],
        ),
        semillaXor: info.semilla,
      );
    }
    final claveArchivo = await Duro.claveArchivo(
      clave: claveSql,
      molde: molde,
      nombre: archivo,
      salHex: info.sal,
    );
    final primero = desde ~/ f.trozo;
    final ultimo = (hasta - 1) ~/ f.trozo;
    final packs = <PaqueteCrudo>[];
    for (var i = primero; i <= ultimo; i++) {
      final off = Duro.offsetDe(f.inicio, i, f.trozo);
      final len = Duro.largoDe(i, f.tamano, f.trozo);
      final bytes = await server.leer(absoluto: off, largo: len);
      packs.add(PaqueteCrudo(i, bytes));
    }
    return Duro.descifrarRango(
      claveArchivo: claveArchivo,
      rango: RangoCrudo(
        modo: 'gcm-c',
        archivo: archivo,
        desde: desde,
        hasta: hasta,
        trozo: f.trozo,
        tamano: f.tamano,
        paquetes: packs,
      ),
    );
  }

  /// Moldes del índice (sin abrir bloques).
  static Future<List<MoldeInfo>> listarMoldes({
    required String claveSql,
  }) async {
    final caja = await abrirIndice(claveSql: claveSql);
    try {
      final filas = caja.listar(MediaBase.tablaMoldes, por: 'nombre');
      return [for (final f in filas) MoldeInfo.deMapa(f)];
    } finally {
      caja.cerrar();
    }
  }

  /// Cambia tags de UNA entrada (update, no duplica).
  static Future<void> actualizarTags({
    required String claveSql,
    required String molde,
    required String archivo,
    required List<String> tags,
  }) async {
    final saneados = MediaBase.sanearTags(tags);
    final caja = await abrirIndice(claveSql: claveSql);
    try {
      final f = caja.uno(
        MediaBase.tablaArchivos,
        'molde = ? AND nombre = ?',
        [molde, archivo],
      );
      if (f == null) {
        throw StateError('create_molde_sql: "$archivo" no está en "$molde"');
      }
      final mapa = <String, Object?>{};
      for (var i = 0; i < MediaBase.maxTags; i++) {
        mapa['tag${i + 1}'] = i < saneados.length ? saneados[i] : '';
      }
      caja.actualizar(MediaBase.tablaArchivos, (f['id'] as int?) ?? 0, mapa);
    } finally {
      caja.cerrar();
    }
  }

  /// Borra UNA entrada del índice (la fila; los bytes quedan huérfanos
  /// en el .mld, no se mueven offsets de nadie).
  static Future<void> quitarEntrada({
    required String claveSql,
    required String molde,
    required String archivo,
  }) async {
    final caja = await abrirIndice(claveSql: claveSql);
    try {
      final f = caja.uno(
        MediaBase.tablaArchivos,
        'molde = ? AND nombre = ?',
        [molde, archivo],
      );
      if (f == null) {
        throw StateError('create_molde_sql: "$archivo" no está en "$molde"');
      }
      caja.quitar(MediaBase.tablaArchivos, (f['id'] as int?) ?? 0);
    } finally {
      caja.cerrar();
    }
  }

  /// Mismo nombre más de una vez → deja la primera, borra el resto.
  static Future<int> quitarDuplicados({
    required String claveSql,
    required String molde,
  }) async {
    final caja = await abrirIndice(claveSql: claveSql);
    try {
      final filas = caja.listarDonde(
        MediaBase.tablaArchivos,
        'molde = ?',
        [molde],
        por: 'id',
      );
      final vistos = <String>{};
      var borradas = 0;
      for (final f in filas) {
        final nombre = '${f['nombre'] ?? ''}';
        if (!vistos.add(nombre)) {
          caja.quitar(MediaBase.tablaArchivos, (f['id'] as int?) ?? 0);
          borradas++;
        }
      }
      return borradas;
    } finally {
      caja.cerrar();
    }
  }

  static String _formato(String nombreRel) {
    final base = nombreRel.split('/').last;
    final p = base.lastIndexOf('.');
    if (p <= 0 || p == base.length - 1) return 'sinformato';
    return base.substring(p + 1).toLowerCase();
  }
}
