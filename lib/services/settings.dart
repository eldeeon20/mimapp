import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../toolsec/toolsec.dart';

/// Estado persistente del usuario, guardado cifrado en `config.pr`.
///
/// El archivo en disco siempre está cifrado con ToolSec (XOR por semilla
/// `masterKey`). Al cargar se descifra en RAM y el plaintext nunca se escribe
/// a disco.
class Settings {
  static final Settings instance = Settings._();
  Settings._();

  /// Toggle funcional del menú: mostrar la ruta/URI completa en media.
  bool mediaShowUri = false;

  /// Clave maestra de cifrado (preferencia por defecto).
  final String masterKey = '1234';

  /// Espacio para cuentas/otros datos del usuario (cifrado junto con el resto).
  Map<String, dynamic> accounts = {};

  /// Tareas Colab guardadas (plantillas Python) + pockets enviados.
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> pockets = [];

  /// Claves guardadas de Pkarr y Nostr (secretos en hex, cifrados junto
  /// con el resto de config.pr).
  List<Map<String, dynamic>> pkarrKeys = [];
  List<Map<String, dynamic>> nostrKeys = [];

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/config.pr');
      if (await file.exists()) {
        final enc = await file.readAsBytes();
        final plain = ToolSec(masterKey).processBytes(enc);
        final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        mediaShowUri = map['mediaShowUri'] as bool? ?? false;
        if (map['accounts'] is Map) {
          accounts = Map<String, dynamic>.from(map['accounts']);
        }
        if (map['tasks'] is List) {
          tasks = map['tasks']
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (map['pockets'] is List) {
          pockets = map['pockets']
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (map['pkarrKeys'] is List) {
          pkarrKeys = map['pkarrKeys']
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (map['nostrKeys'] is List) {
          nostrKeys = map['nostrKeys']
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      // Archivo corrupto/ilegible: se quedan los defaults.
      print('Settings.load error: $e');
    } finally {
      _loaded = true;
    }
  }

  Future<void> save() async {
    try {
      final map = {
        'mediaShowUri': mediaShowUri,
        'accounts': accounts,
        'tasks': tasks,
        'pockets': pockets,
        'pkarrKeys': pkarrKeys,
        'nostrKeys': nostrKeys,
      };
      final plain = utf8.encode(jsonEncode(map));
      final enc = ToolSec(masterKey).processBytes(Uint8List.fromList(plain));
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/config.pr');
      await file.writeAsBytes(enc);
    } catch (e) {
      print('Settings.save error: $e');
    }
  }
}
