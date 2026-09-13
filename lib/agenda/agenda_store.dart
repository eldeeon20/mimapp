import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../services/crypto_vault.dart';

/// Una entrada de la agenda: cosa/nota con título y cuerpo.
class AgendaItem {
  final String id;
  String titulo;
  String cuerpo;
  int fecha; // epoch ms del evento/recordatorio (0 = sin fecha)
  int creada; // epoch ms de creación

  AgendaItem({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    this.fecha = 0,
    int? creada,
  }) : creada = creada ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'cuerpo': cuerpo,
        'fecha': fecha,
        'creada': creada,
      };

  factory AgendaItem.fromJson(Map<String, dynamic> j) => AgendaItem(
        id: (j['id'] ?? '') as String,
        titulo: (j['titulo'] ?? '') as String,
        cuerpo: (j['cuerpo'] ?? '') as String,
        fecha: ((j['fecha'] as num?) ?? 0).toInt(),
        creada: ((j['creada'] as num?) ?? 0).toInt(),
      );
}

/// Agenda persistente: el JSON se guarda CIFRADO con CryptoVault
/// (AES-256-GCM v2, envelope PRBX) en appSupport/<nombre>.pr.
/// La clave es la pass que pide la pantalla al abrir (NO la masterKey
/// global): cada agenda tiene su nombre y su pass.
class AgendaStore extends ChangeNotifier {
  AgendaStore._();
  static final AgendaStore instance = AgendaStore._();

  String _fileName = 'agenda.pr';
  String _pass = '';
  bool _abierta = false;

  /// Nombre actual (sin .pr). Vacío = aún no abierta.
  String nombreActual = '';

  /// true si ya se abrió con nombre+pass (pantalla muestra la lista).
  bool get abierta => _abierta;

  final List<AgendaItem> items = [];
  bool _loaded = false;
  bool _busy = false;

  bool get busy => _busy;

  /// Nombre a archivo: solo letras/números/guion/piso, máx 40.
  static String sanearNombre(String s) {
    final limpio = s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    if (limpio.isEmpty) return 'agenda';
    return limpio.length > 40 ? limpio.substring(0, 40) : limpio;
  }

  /// Abre (o crea) la agenda [nombre] con [pass]. false = pass mal
  /// (el archivo existe y no descifra) o pass vacío.
  Future<bool> abrir(String nombre, String pass) async {
    if (pass.isEmpty) return false;
    _fileName = '${sanearNombre(nombre)}.pr';
    nombreActual = sanearNombre(nombre);
    _pass = pass;
    _loaded = false;
    _abierta = false;
    items.clear();
    final f = await _file();
    if (await f.exists()) {
      try {
        final raw = await f.readAsBytes();
        final plain = await CryptoVault.decrypt(raw, _pass);
        if (plain == null) {
          // Existe pero no abre con esta pass: no tocar nada.
          items.clear();
          notifyListeners();
          return false;
        }
        final list = jsonDecode(utf8.decode(plain))['items'] as List? ?? [];
        for (final e in list) {
          final it = AgendaItem.fromJson(e as Map<String, dynamic>);
          if (it.id.isNotEmpty) items.add(it);
        }
        _ordenar();
      } catch (_) {
        return false;
      }
    }
    _loaded = true;
    _abierta = true;
    notifyListeners();
    return true;
  }

  /// Cierra: olvida pass e items en memoria (el .pr queda en disco).
  void cerrar() {
    _pass = '';
    _abierta = false;
    _loaded = false;
    nombreActual = '';
    items.clear();
    notifyListeners();
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Ruta del archivo (para mostrar en el test).
  Future<String> ruta() async => (await _file()).path;

  Future<void> ensureLoaded() async {
    if (_loaded || !_abierta) return;
    _loaded = true;
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final raw = await f.readAsBytes();
      final plain = await CryptoVault.decrypt(raw, _pass);
      if (plain == null) return; // clave mal o archivo alterado
      final list = jsonDecode(utf8.decode(plain))['items'] as List? ?? [];
      items.clear();
      for (final e in list) {
        final it = AgendaItem.fromJson(e as Map<String, dynamic>);
        if (it.id.isNotEmpty) items.add(it);
      }
      _ordenar();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> _persist() async {
    if (!_abierta || _pass.isEmpty) return false;
    try {
      final f = await _file();
      final json =
          utf8.encode(jsonEncode({'items': items.map((e) => e.toJson()).toList()}));
      final enc = await CryptoVault.encrypt(
          Uint8List.fromList(json), _pass);
      await f.writeAsBytes(enc, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _ordenar() {
    items.sort((a, b) => b.creada.compareTo(a.creada));
  }

  static String _nuevoId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Agrega una cosa/nota. Retorna el item creado o null si falló el guardado.
  Future<AgendaItem?> agregar(String titulo, String cuerpo,
      {int fecha = 0}) async {
    if (_busy) return null;
    _busy = true;
    try {
      final it = AgendaItem(
          id: _nuevoId(), titulo: titulo.trim(), cuerpo: cuerpo, fecha: fecha);
      items.add(it);
      _ordenar();
      if (!await _persist()) {
        items.removeWhere((e) => e.id == it.id);
        return null;
      }
      notifyListeners();
      return it;
    } finally {
      _busy = false;
    }
  }

  /// Edita título/cuerpo/fecha de un item. false = no existe o falló guardar.
  Future<bool> editar(String id,
      {String? titulo, String? cuerpo, int? fecha}) async {
    if (_busy) return false;
    final it = porId(id);
    if (it == null) return false;
    _busy = true;
    final viejoTitulo = it.titulo;
    final viejoCuerpo = it.cuerpo;
    final viejaFecha = it.fecha;
    try {
      if (titulo != null) it.titulo = titulo.trim();
      if (cuerpo != null) it.cuerpo = cuerpo;
      if (fecha != null) it.fecha = fecha;
      if (!await _persist()) {
        it.titulo = viejoTitulo;
        it.cuerpo = viejoCuerpo;
        it.fecha = viejaFecha;
        return false;
      }
      notifyListeners();
      return true;
    } finally {
      _busy = false;
    }
  }

  /// Borra un item. false = no existe o falló guardar.
  Future<bool> borrar(String id) async {
    if (_busy) return false;
    final idx = items.indexWhere((e) => e.id == id);
    if (idx < 0) return false;
    _busy = true;
    final sacado = items.removeAt(idx);
    try {
      if (!await _persist()) {
        items.insert(idx, sacado);
        return false;
      }
      notifyListeners();
      return true;
    } finally {
      _busy = false;
    }
  }

  AgendaItem? porId(String id) {
    for (final e in items) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Búsqueda simple por texto en título + cuerpo.
  List<AgendaItem> buscar(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return [...items];
    return items
        .where((e) =>
            e.titulo.toLowerCase().contains(query) ||
            e.cuerpo.toLowerCase().contains(query))
        .toList();
  }
}
