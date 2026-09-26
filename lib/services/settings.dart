import 'dart:convert';
import 'dart:typed_data';

import '../toolsec/toolsec.dart';
import 'app_db.dart';
import 'crypto_vault.dart';

/// Estado persistente del usuario, guardado cifrado en `app.db`
/// (tabla `kv`, clave `ajustes`, envelope AES-256-GCM con la
/// `masterKey`).
///
/// El viejo `config.pr` no importa: se borra sin migrar.
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
  /// con el resto en app.db).
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

  /// El load en curso (bootstrap lo dispara al arrancar). Los save()
  /// lo ESPERAN: guardar antes de cargar pisaba el archivo bueno con
  /// la memoria en defaults (vacía) → al reabrir, todo borrado.
  Future<void>? _cargando;

  /// Cola de guardados: los save() se EJECUTAN DE A UNO. Antes, dos
  /// _persist() juntos pisaban el mismo archivo a mitad de escritura
  /// → al reabrir, ilegible → todo vacío aunque decía "guardado".
  static Future<void> _cola = Future.value();

  Future<void> save() {
    final t = _cola.then((_) async {
      try {
        await _cargando;
      } catch (_) {}
      await _guardarAhora();
    });
    _cola = t.catchError((_) {});
    return t;
  }

  Future<void> load() async {
    if (_loaded) return;
    _cargando ??= _cargar();
    try {
      await _cargando;
    } finally {
      _loaded = true;
    }
  }

  Future<void> _cargar() async {
    try {
      // Solo app.db: los .pr no importan, no se migran.
      final kv = await AppDb.leer('ajustes');
      if (kv != null) await _cargarBytes(kv);
    } catch (e) {
      // Ilegible: se quedan los defaults.
      print('Settings.load error: $e');
    }
    // Tachar viejos (aunque falle todo lo demás).
    await AppDb.tachar('config.pr');
    await AppDb.tachar('config.pr.bak');
    await AppDb.tachar('config.pr.tmp');
  }

  /// Descifra y vuelca los bytes guardados en memoria. true = ok.
  /// Acepta envelope V2 (CryptoVault), legado XOR y ToolSec fuerte.
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

  Future<void> _guardarAhora() async {
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
      final enc = await CryptoVault.encrypt(
          Uint8List.fromList(plain), masterKey);
      await AppDb.guardar('ajustes', enc);
    } catch (e) {
      print('Settings.save error: $e');
    }
  }
}
