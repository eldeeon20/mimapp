import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Un grupo de caché: nombre + rutas (archivos o carpetas) + tamaño.
class GrupoCache {
  final String nombre;
  final List<String> rutas;
  final int bytes;

  /// Desglose opcional nombre → bytes (para mostrar por carpeta).
  final List<MapEntry<String, int>> detalle;

  const GrupoCache(this.nombre, this.rutas, this.bytes,
      [this.detalle = const []]);
}

/// Almacén: check de memoria (Kotlin) + tamaños por grupo + limpieza
/// en dos modos: Datos (db/pr) y Descargados (modelos, descargas,
/// torrents). Todo best-effort, sin romper si algo falta.
class Almacen {
  Almacen._();

  static const _canal = MethodChannel('pr_app/nativo');

  /// Memoria del celu en bytes: internaTotal, internaLibre, ramTotal,
  /// ramLibre. En 0 si el canal no responde (no Android).
  static Future<Map<String, int>> memoria() async {
    try {
      final r = await _canal.invokeMethod('memoria');
      if (r is Map) {
        int n(Object? v) => (v as num?)?.toInt() ?? 0;
        return {
          'internaTotal': n(r['internaTotal']),
          'internaLibre': n(r['internaLibre']),
          'ramTotal': n(r['ramTotal']),
          'ramLibre': n(r['ramLibre']),
        };
      }
    } catch (_) {}
    return {
      'internaTotal': 0,
      'internaLibre': 0,
      'ramTotal': 0,
      'ramLibre': 0,
    };
  }

  static Future<String> soporte() async =>
      (await getApplicationSupportDirectory()).path;

  static Future<String> docs() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// Tamaño recursivo de archivo o carpeta. Inexistente → 0.
  static Future<int> tamRuta(String ruta) async {
    try {
      final tipo = await FileSystemEntity.type(ruta);
      if (tipo == FileSystemEntityType.notFound) return 0;
      if (tipo == FileSystemEntityType.file) {
        return await File(ruta).length();
      }
      var total = 0;
      await for (final e in Directory(ruta)
          .list(recursive: true, followLinks: false)) {
        try {
          if (e is File) total += await e.length();
        } catch (_) {}
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static String base(String ruta) {
    final i = ruta.lastIndexOf('/');
    return i < 0 ? ruta : ruta.substring(i + 1);
  }

  /// Modo 1 · Datos: db/*.db + *.pr SALVO config.pr (ajustes, jamás).
  static Future<GrupoCache> grupoDatos() async {
    final baseDir = await soporte();
    final archivos = <String>[];
    try {
      final db = Directory('$baseDir/db');
      if (await db.exists()) {
        await for (final e in db.list()) {
          if (e is File && e.path.endsWith('.db')) {
            archivos.add(e.path);
          }
        }
      }
      await for (final e in Directory(baseDir).list()) {
        if (e is File &&
            e.path.endsWith('.pr') &&
            !e.path.endsWith('/config.pr')) {
          archivos.add(e.path);
        }
      }
    } catch (_) {}
    var total = 0;
    for (final f in archivos) {
      try {
        total += await File(f).length();
      } catch (_) {}
    }
    archivos.sort();
    return GrupoCache('Datos (db/pr)', archivos, total);
  }

  /// Modo 2 · Descargados: modelos (needle), descargas HTTP, descargas
  /// del navegador, repo ipfs y la raíz de torrents (rqbit).
  static Future<GrupoCache> grupoDescargas(String raizTorrent) async {
    final baseDir = await soporte();
    final dirs = <String>[
      '$baseDir/needle',
      '$baseDir/downloads',
      '$baseDir/browser_downloads',
      '$baseDir/ipfs',
      if (raizTorrent.isNotEmpty) raizTorrent,
    ];
    final detalle = <MapEntry<String, int>>[];
    final vivas = <String>[];
    var total = 0;
    for (final d in dirs) {
      final t = await tamRuta(d);
      if (t > 0) {
        detalle.add(MapEntry(base(d), t));
        vivas.add(d);
        total += t;
      }
    }
    return GrupoCache('Descargados', vivas, total, detalle);
  }

  /// Borra archivos o carpetas (recursivo). Devuelve cuántos borró.
  static Future<int> liberar(List<String> rutas) async {
    var n = 0;
    for (final r in rutas) {
      try {
        final t = await FileSystemEntity.type(r);
        if (t == FileSystemEntityType.directory) {
          await Directory(r).delete(recursive: true);
          n++;
        } else if (t != FileSystemEntityType.notFound) {
          await File(r).delete();
          n++;
        }
      } catch (_) {}
    }
    return n;
  }

  static String fmt(int b) {
    if (b <= 0) return '0 B';
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1073741824) {
      return '${(b / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }
}
