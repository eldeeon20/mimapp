import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../toolsec/toolsec.dart';
import 'crypto_vault.dart';

/// Estado persistente del usuario, guardado cifrado en `config.pr`.
///
/// Formato V2: envelope AES-256-GCM (CryptoVault, clave derivada de
/// `masterKey` vía PBKDF2 con salt aleatorio). Los config.pr viejos (XOR)
/// se detectan al cargar y se re-guardan migrados automáticamente.
class Settings {
  static final Settings instance = Settings._();
  Settings._();

  /// Toggle funcional del menú: mostrar la ruta/URI completa en media.
  bool mediaShowUri = false;

  /// Abrir puertos en el router vía UPnP/NAT-PMP (servicio NatService).
  bool natEnabled = false;

  /// Modo de la web Lua: true = oscuro, false = claro (parámetro global).
  bool webDarkMode = true;

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

  /// Llaves OAuth de Colab puestas a mano por el usuario (vacío = usar
  /// las embebidas en ColabConfig). Cifradas junto con el resto.
  String colabClientId = '';
  String colabClientSecret = '';

  /// Carpeta RAÍZ de torrents (rqbit): la elige el usuario una vez y
  /// cada torrent crea SU subcarpeta adentro. Vacío = preguntar.
  String torrentRoot = '';

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/config.pr');
      Uint8List? enc;
      if (await file.exists()) {
        enc = await file.readAsBytes();
      } else {
        // Sin principal: probar el respaldo (corte a mitad de escritura).
        final bak = File('${dir.path}/config.pr.bak');
        if (await bak.exists()) {
          print('Settings.load: uso respaldo .bak');
          enc = await bak.readAsBytes();
        }
      }
      if (enc != null) {
        final ok = await _cargarBytes(enc);
        if (!ok) {
          // Principal corrupto: probar el respaldo antes de defaultear.
          try {
            final bak = File('${dir.path}/config.pr.bak');
            if (await bak.exists()) {
              print('Settings.load: principal corrupto, uso .bak');
              await _cargarBytes(await bak.readAsBytes());
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      // Archivo corrupto/ilegible: se quedan los defaults.
      print('Settings.load error: $e');
    } finally {
      _loaded = true;
    }
  }

  /// Descifra y vuelca un config.pr en memoria. true = ok.
  Future<bool> _cargarBytes(Uint8List enc) async {
    try {
      Uint8List? plain;
      bool needsMigration = false;
      if (CryptoVault.isEnvelope(enc)) {
        // Formato nuevo (AES-256-GCM). null = masterKey incorrecta.
        plain = await CryptoVault.decrypt(enc, masterKey);
      } else {
        // Legado XOR: descifrar y marcar para migrar a V2 al guardar.
        plain = ToolSec(masterKey).processBytes(enc);
        needsMigration = true;
      }
      if (plain == null) {
        print('Settings.load: envelope V2 no autenticado, defaults');
        return false;
      }
      final map = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      mediaShowUri = map['mediaShowUri'] as bool? ?? false;
      natEnabled = map['natEnabled'] as bool? ?? false;
      webDarkMode = map['webDarkMode'] as bool? ?? true;
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
      colabClientId = map['colabClientId'] as String? ?? '';
      colabClientSecret = map['colabClientSecret'] as String? ?? '';
      torrentRoot = map['torrentRoot'] as String? ?? '';
      if (needsMigration) {
        // Legado XOR -> re-guardar ya como envelope V2 (AES-GCM).
        save();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> save() async {
    try {
      final map = {
        'mediaShowUri': mediaShowUri,
        'natEnabled': natEnabled,
        'webDarkMode': webDarkMode,
        'accounts': accounts,
        'tasks': tasks,
        'pockets': pockets,
        'pkarrKeys': pkarrKeys,
        'nostrKeys': nostrKeys,
        'colabClientId': colabClientId,
        'colabClientSecret': colabClientSecret,
        'torrentRoot': torrentRoot,
      };
      final plain = utf8.encode(jsonEncode(map));
      final enc =
          await ToolSec(masterKey).processBytesStrong(Uint8List.fromList(plain));
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/config.pr');
      final tmp = File('${dir.path}/config.pr.tmp');
      final bak = File('${dir.path}/config.pr.bak');
      // Atómico: tmp + rename (matar la app a mitad no corrompe).
      await tmp.writeAsBytes(enc, flush: true);
      try {
        if (await file.exists()) {
          // Respaldo del último bueno (load lo usa si el principal falla).
          try {
            await file.copy(bak.path);
          } catch (_) {}
        }
      } catch (_) {}
      await tmp.rename(file.path);
    } catch (e) {
      print('Settings.save error: $e');
    }
  }
}
