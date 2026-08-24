import 'dart:convert';
import 'dart:typed_data';

import '../src/rust/api/unarc.dart' as rust;

/// Unarc: extracción universal de archives (7z/ZIP/RAR5/tar/gz/arj/lha/zoo…)
/// vía unarc-rs. Port del Unarc de Gtool sin Godot.
///
/// Soporta multi-volumen (.7z.001/.002, .zip.001, .z01+.zip) y passwords.
/// Las funciones Rust devuelven JSON strings; acá se materializan a tipos.
class Unarc {
  /// true si la extensión del archivo es soportada.
  Future<bool> soportado(String path) =>
      rust.unarcSoportado(archivePath: path);

  /// Nombre legible del formato ('7-Zip', 'RAR', 'ZIP'…) o '' si no detecta.
  Future<String> formato(String path) =>
      rust.unarcFormato(archivePath: path);

  /// true si alguna entrada pide password (o el archive no abre sin ella).
  Future<bool> encriptado(String path) =>
      rust.unarcEncriptado(archivePath: path);

  /// Lista de entradas (nombre, tamaño, dir, cifrado).
  Future<List<UnarcEntry>> listar(String path, {String password = ''}) async {
    final raw = await rust.unarcListar(archivePath: path, password: password);
    final lista = jsonDecode(raw) as List<dynamic>;
    return [
      for (final e in lista)
        UnarcEntry(
          name: e['name'] as String,
          size: (e['size'] as num).toInt(),
          isDir: e['isDir'] as bool,
          encrypted: e['encrypted'] as bool,
        ),
    ];
  }

  /// Extrae todo el archive a [destDir]; devuelve archivos extraídos y bytes.
  Future<UnarcResumen> extraerTodo(
    String path,
    String destDir, {
    String password = '',
  }) async {
    final raw = await rust.unarcExtraerTodo(
      archivePath: path,
      outputDir: destDir,
      password: password,
    );
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return UnarcResumen(
      files: (m['files'] as num).toInt(),
      bytes: (m['bytes'] as num).toInt(),
    );
  }

  /// Extrae UNA entrada al archivo [destPath]. Devuelve bytes escritos.
  Future<int> extraerEntrada(
    String path,
    String entryName,
    String destPath, {
    String password = '',
  }) async {
    final raw = await rust.unarcExtraerEntrada(
      archivePath: path,
      entryName: entryName,
      destPath: destPath,
      password: password,
    );
    return ((jsonDecode(raw) as Map<String, dynamic>)['bytes'] as num).toInt();
  }

  /// Lee una entrada a memoria (preview), cortada a [maxBytes].
  Future<Uint8List> leerEntrada(
    String path,
    String entryName, {
    String password = '',
    int maxBytes = 8 * 1024 * 1024,
  }) {
    return rust.unarcLeerEntrada(
      archivePath: path,
      entryName: entryName,
      password: password,
      maxBytes: maxBytes,
    );
  }
}

class UnarcEntry {
  final String name;
  final int size;
  final bool isDir;
  final bool encrypted;
  const UnarcEntry({
    required this.name,
    required this.size,
    required this.isDir,
    required this.encrypted,
  });
}

class UnarcResumen {
  final int files;
  final int bytes;
  const UnarcResumen({required this.files, required this.bytes});
}
