import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:koni_archive/io.dart';

import 'koni_7z.dart';
import 'koni_rar.dart';
import 'koni_zip.dart';

/// Contrato de cada formato soportado por Koni (ZIP / 7Z / RAR).
///
/// Cada adapter valida SU extensión y abre con auto-detección de
/// koni_archive. La mecánica común (opciones, password, límites) vive en
/// [Koni.abrirArchivo] para no duplicarla.
abstract class KoniFormato {
  /// Etiqueta corta para la UI ('ZIP', '7Z', 'RAR').
  String get etiqueta;

  /// Extensiones que atiende, sin punto (['zip', 'cbz']).
  List<String> get extensiones;

  /// Tope anti-bomba por entrada al leer a memoria.
  int get maxEntradaBytes;

  /// ¿Esta ruta cae en este formato?
  bool soporta(String ruta);

  /// Abre el archivo (solo índice de entradas, nada se vuelca a disco).
  Future<Archive> abrir(String ruta, {String? password});
}

/// Entrada del archive en forma apta para la UI.
class KoniItem {
  final String ruta;
  final bool esDir;
  final int tamano;
  final int? comprimido;
  final bool cifrado;
  final DateTime? modificado;

  const KoniItem({
    required this.ruta,
    required this.esDir,
    required this.tamano,
    this.comprimido,
    required this.cifrado,
    this.modificado,
  });

  String get nombre =>
      ruta.isEmpty ? '' : ruta.split('/').last;
}

/// Resultado de una extracción a disco.
class KoniExtraccion {
  final int archivos;
  final int bytes;
  final int omitidos;
  const KoniExtraccion({
    required this.archivos,
    required this.bytes,
    required this.omitidos,
  });
}

/// Sesión abierta sobre un archive: navegar (RAM) + extraer a destino.
///
/// Abrir SOLO lee el índice de entradas (metadata); el contenido se
/// decodifica bajo demanda por streams con memoria acotada. Nada toca
/// el disco hasta que se pide extraer explícitamente.
class KoniSesion {
  final Archive _arc;
  final String formatoId;
  bool _cerrada = false;

  KoniSesion(this._arc, this.formatoId);

  bool get cerrada => _cerrada;

  /// Formato detectado por koni_archive.
  String get formatoDetectado => _arc.format.toString();

  /// Vista VFS (dirs sintetizados incluidos), en orden de recorrido.
  List<KoniItem> get items => [
        for (final e in _arc.walk())
          if (e.path.isNotEmpty)
            KoniItem(
              ruta: e.path,
              esDir: e.isDirectory,
              tamano: e.uncompressedSize,
              comprimido: e.compressedSize,
              cifrado: e.isEncrypted,
              modificado: e.modified,
            ),
      ];

  /// Solo archivos (para extraer todo).
  List<KoniItem> get archivos =>
      items.where((e) => !e.esDir).toList();

  /// Filtro por texto (nombre o ruta).
  List<KoniItem> buscar(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items
        .where((e) =>
            e.nombre.toLowerCase().contains(query) ||
            e.ruta.toLowerCase().contains(query))
        .toList();
  }

  void _exigirAbierta() {
    if (_cerrada) throw StateError('Koni: sesión cerrada');
  }

  /// Lee UNA entrada completa a memoria (preview). Nada toca el disco.
  /// [max] acota el buffer (anti-bomba).
  Future<Uint8List> leerBytes(String ruta, {int? max}) async {
    _exigirAbierta();
    final e = _arc.entry(ruta);
    if (e == null) throw StateError('Koni: no existe $ruta');
    if (e.isDirectory) throw StateError('Koni: es carpeta ($ruta)');
    return _arc.readBytes(e, maxSize: max);
  }

  /// Stream decodificado de una entrada (memoria acotada, por chunks).
  Stream<Uint8List> abrirStream(String ruta) {
    _exigirAbierta();
    return _arc.openReadPath(ruta);
  }

  /// Extrae UNA entrada al [destino] (stream → disco, sin buffer gigante).
  /// Retorna los bytes escritos.
  Future<int> extraerEntrada(String ruta, String destino) async {
    _exigirAbierta();
    final out = File(destino);
    await out.parent.create(recursive: true);
    final sink = out.openWrite();
    var bytes = 0;
    try {
      await for (final chunk in abrirStream(ruta)) {
        sink.add(chunk);
        bytes += chunk.length;
      }
    } finally {
      await sink.close();
    }
    return bytes;
  }

  /// Extrae TODOS los archivos bajo [dir], recreando subcarpetas.
  Future<KoniExtraccion> extraerTodo(String dir) async {
    _exigirAbierta();
    var archivos = 0;
    var bytes = 0;
    var omitidos = 0;
    for (final e in _arc.walk()) {
      if (!e.isFile || e.path.isEmpty) continue;
      if (e.pathEscapedRoot) {
        omitidos++;
        continue;
      }
      final destino = '$dir/${e.path}';
      bytes += await extraerEntrada(e.path, destino);
      archivos++;
    }
    return KoniExtraccion(
      archivos: archivos,
      bytes: bytes,
      omitidos: omitidos,
    );
  }

  Future<void> cerrar() async {
    if (_cerrada) return;
    _cerrada = true;
    await _arc.close();
  }
}

/// Fachada principal Koni: deriva al formato y abre la sesión.
class Koni {
  Koni._();

  static List<KoniFormato> get formatos => [KoniZip(), Koni7z(), KoniRar()];

  /// Extensiones soportadas en total (para mensajes y filtros).
  static List<String> get extensiones =>
      [for (final f in formatos) ...f.extensiones];

  /// ¿Qué formato atiende esta ruta? null = ninguno.
  static KoniFormato? formatoDe(String ruta) {
    for (final f in formatos) {
      if (f.soporta(ruta)) return f;
    }
    return null;
  }

  /// Apertura cruda compartida por los adapters (no usar directo desde
  /// la UI: preferir [abrir], que deriva formato y arma la sesión).
  static Future<Archive> abrirArchivo(
    String ruta, {
    required String etiqueta,
    String? password,
    required int maxEntradaBytes,
  }) async {
    final pwd = (password == null || password.isEmpty) ? null : password;
    try {
      return await openArchiveFile(
        ruta,
        options: ArchiveReadOptions(
          password: pwd,
          maxEntrySize: maxEntradaBytes,
        ),
      );
    } on InvalidPasswordException {
      throw StateError('Koni[$etiqueta]: contraseña incorrecta');
    } on EncryptedArchiveException {
      throw StateError(
          'Koni[$etiqueta]: pide contraseña (ponela y reabrí)');
    } on UnsupportedFormatException {
      throw StateError('Koni[$etiqueta]: no se reconoció el contenido');
    }
  }

  /// Abre un archive y devuelve la sesión para navegar/extraer.
  /// Solo lee el índice (metadata): NO vuelca nada a disco.
  static Future<KoniSesion> abrir(String ruta, {String? password}) async {
    final f = formatoDe(ruta);
    if (f == null) {
      throw UnsupportedError(
          'Koni: extensión no soportada ($ruta). '
          'Soportadas: ${extensiones.map((e) => '.$e').join(' ')}');
    }
    final arc = await f.abrir(ruta, password: password);
    return KoniSesion(arc, f.etiqueta);
  }
}
