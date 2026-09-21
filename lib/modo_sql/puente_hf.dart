import 'dart:io';
import 'dart:typed_data';

import 'package:pr_app/services/hf.dart';

import 'indice/indice.dart';
import 'db/caja_sql.dart';
import 'media_server/media_server.dart';
import 'tool/create_molde_sql.dart';

/// Puente HF de moldes: el índice guarda por molde su repo
/// (dir/user = `repo_id`), su pass y su token de acceso.
///
/// Convención de paths dentro del repo:
///
///   `<nombre>.mld`   el molde (blob grande, NUNCA se baja entero)
///   `<nombre>.sql`   su SQL con ruta `hf://repo/<nombre>.mld`
///                     (se baja entera; apunta al molde de HF)
///
/// El `.mld` remoto solo se lee por RANGOS (`rangoMld`), con el
/// token del molde para repos privados. La SQL sí se descarga
/// completa la primera vez que se toca el molde como carpeta.
class PuenteHf {
  final HuggingFace _hf = HuggingFace();

  bool get listo => _hf.ready;

  Future<void> init(String token) => _hf.init(token);

  void cerrar() => _hf.dispose();

  /// Config HF de un molde desde el índice.
  static Future<({String repo, String token, int version})> configDe({
    required String passIndice,
    required String nombre,
  }) async {
    final ent =
        await Indice.entrada(pass: passIndice, nombre: nombre);
    if (ent == null) {
      throw StateError('puente_hf: "$nombre" no está en el índice');
    }
    return (
      repo: '${ent['hf_repo'] ?? ''}',
      token: '${ent['hf_token'] ?? ''}',
      version: (ent['version'] as int?) ?? 0,
    );
  }

  /// Crea el repo privado si falta (exist_ok, no falla si ya está).
  Future<void> asegurarRepo({
    required String repoId,
    required String token,
    String repoType = 'dataset',
  }) async {
    await init(token);
    final existe =
        await _hf.repoExists(repoId: repoId, repoType: repoType);
    if (!existe) {
      await _hf.createRepository(
        repoId: repoId,
        repoType: repoType,
        private: true,
      );
    }
  }

  /// Sube el molde (.mld + su SQL + respaldo del índice) y marca
  /// la versión.
  /// El SQL que sube apunta al molde de HF (`hf://repo/nombre.mld`,
  /// editado en una COPIA: tu SQL local sigue al .mld local).
  /// El índice viaja como respaldo cifrado (lleva repos+tokens).
  /// Retorna la versión subida (ms actual).
  Future<int> subirMolde({
    required String passIndice,
    required String claveSql,
    required String nombre,
    String repoType = 'dataset',
    void Function(String s)? log,
  }) async {
    final ent =
        await Indice.entrada(pass: passIndice, nombre: nombre);
    if (ent == null) {
      throw StateError('puente_hf: "$nombre" no está en el índice');
    }
    final repo = '${ent['hf_repo'] ?? ''}';
    final token = '${ent['hf_token'] ?? ''}';
    if (repo.isEmpty || token.isEmpty) {
      throw StateError('puente_hf: "$nombre" sin repo/token '
          '(guardalos primero con Indice.guardarHf)');
    }
    await asegurarRepo(repoId: repo, token: token, repoType: repoType);
    final version = DateTime.now().millisecondsSinceEpoch;
    final commit = 'molde $nombre v$version';

    final mldRuta = '${ent['mld_ruta'] ?? ''}';
    if (mldRuta.isNotEmpty && await File(mldRuta).exists()) {
      log?.call('· subiendo $nombre.mld…');
      await _hf.uploadFile(
        repoId: repo,
        localFilePath: mldRuta,
        pathInRepo: '$nombre.mld',
        commitMessage: commit,
        repoType: repoType,
      );
    }
    final dbRuta = '${ent['db_ruta'] ?? ''}';
    if (dbRuta.isNotEmpty && await File(dbRuta).exists()) {
      log?.call('· subiendo $nombre.sql (apuntando a HF)…');
      // Copia con ruta HF: el que baja este SQL ve el molde de HF,
      // no tu disco. El local queda intacto.
      final tmp = await Directory.systemTemp.createTemp('hf_sql_up');
      try {
        final dbBase = dbRuta.split('/').last;
        final copia = File('${tmp.path}/$dbBase');
        await File(dbRuta).copy(copia.path);
        final sinDb = dbBase.endsWith('.db')
            ? dbBase.substring(0, dbBase.length - 3)
            : dbBase;
        final caja = CajaSql();
        try {
          await caja.abrir(sinDb,
              carpeta: tmp.path, clave: claveSql);
          caja.db.execute(
            'UPDATE "${MediaBase.tablaMoldes}" SET ruta = ? '
            'WHERE nombre = ?;',
            ['hf://$repo/$nombre.mld', nombre],
          );
        } finally {
          caja.cerrar();
        }
        await _hf.uploadFile(
          repoId: repo,
          localFilePath: copia.path,
          pathInRepo: '$nombre.sql',
          commitMessage: commit,
          repoType: repoType,
        );
      } finally {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    }
    await Indice.marcarVersion(
        pass: passIndice, nombre: nombre, version: version);
    // Respaldo del índice (cifrado con tu clave: repos+tokens).
    // En la copia que sube, este molde apunta al repo:
    // sql → `$nombre.sql`, mld → `hf://repo/nombre.mld`.
    // El índice local no se toca.
    try {
      final carpeta = await MediaBase.carpetaMoldes();
      final idx = File('${carpeta.path}/${Indice.archivo}');
      if (await idx.exists()) {
        log?.call('· subiendo ${Indice.archivo} (apuntando a HF)…');
        final tmpI =
            await Directory.systemTemp.createTemp('hf_idx_up');
        try {
          final copiaI = File('${tmpI.path}/${Indice.archivo}');
          await idx.copy(copiaI.path);
          final cajaI = CajaSql();
          try {
            await cajaI.abrir('indice',
                carpeta: tmpI.path, clave: passIndice);
            cajaI.db.execute(
              'UPDATE indice SET sql = ?, mld = ? WHERE nombre = ?;',
              [
                '$nombre.sql',
                'hf://$repo/$nombre.mld',
                nombre
              ],
            );
          } finally {
            cajaI.cerrar();
          }
          await _hf.uploadFile(
            repoId: repo,
            localFilePath: copiaI.path,
            pathInRepo: Indice.archivo,
            commitMessage: commit,
            repoType: repoType,
          );
        } finally {
          try {
            await tmpI.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (e) {
      log?.call('⚠ índice no subido: $e');
    }
    log?.call('✓ $nombre en $repo v$version');
    return version;
  }

  /// Baja la SQL entera del molde si no está local, directo a su
  /// ruta propia (`m_<nombre>.db`, la que `_cajaMolde` sabe abrir),
  /// y deja apuntado el índice (el índice sabe dónde está cada SQL).
  /// Retorna su path. El .mld NO se baja: se consulta por rangos.
  Future<String> bajarSql({
    required String passIndice,
    required String nombre,
    String repoType = 'dataset',
  }) async {
    final destino = await CreateMoldeSql.rutaDbPropia(nombre);
    if (await File(destino).exists()) {
      await Indice.actualizarRutas(
        pass: passIndice,
        nombre: nombre,
        dbRuta: destino,
        mldRuta: '',
      );
      return destino;
    }
    final ent =
        await Indice.entrada(pass: passIndice, nombre: nombre);
    if (ent == null) {
      throw StateError('puente_hf: "$nombre" no está en el índice');
    }
    final repo = '${ent['hf_repo'] ?? ''}';
    final token = '${ent['hf_token'] ?? ''}';
    if (repo.isEmpty || token.isEmpty) {
      throw StateError('puente_hf: "$nombre" sin repo/token');
    }
    await init(token);
    final tmp = await Directory.systemTemp.createTemp('hf_sql');
    try {
      final bajado = await _hf.downloadFile(
        repoId: repo,
        filename: '$nombre.sql',
        localDir: tmp.path,
        repoType: repoType,
      );
      await File(bajado).copy(destino);
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
    await Indice.actualizarRutas(
      pass: passIndice,
      nombre: nombre,
      dbRuta: destino,
      mldRuta: '',
    );
    return destino;
  }

  /// Un RANGO de bytes del .mld remoto (el molde se consulta,
  /// no se descarga). Token del molde para repos privados.
  static Future<Uint8List> rangoMld({
    required String repo,
    required String nombre,
    required int start,
    required int end,
    String token = '',
    String repoType = 'dataset',
  }) {
    return HuggingFace.downloadFileRange(
      repoId: repo,
      filename: '$nombre.mld',
      start: start,
      end: end,
      token: token,
      repoType: repoType,
    );
  }

  /// Archivos del repo (control de versiones: qué hay subido).
  Future<List<String>> archivos({
    required String repoId,
    required String token,
    String repoType = 'dataset',
  }) async {
    await init(token);
    return _hf.listRepoFiles(
        repoId: repoId, recursive: true, repoType: repoType);
  }
}
