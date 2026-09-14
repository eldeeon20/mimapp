import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/caja_sql.dart';

/// Ejemplo de CajaSql (SQLite cifrado ChaCha20) para el menú radial:
/// crear db, cambiar db, borrar db, crear tablas con campos distintos,
/// agregar/quitar campos, agregar filas y listas, ordenar, contar,
/// quitar por id. Sin AppBar propia: la da el contenedor.
class DbTestScreen extends StatefulWidget {
  const DbTestScreen({super.key});

  @override
  State<DbTestScreen> createState() => _DbTestScreenState();
}

class _DbTestScreenState extends State<DbTestScreen> {
  final _caja = CajaSql();
  final _dbCtrl = TextEditingController(text: 'contactos');
  final _claveCtrl = TextEditingController();
  final _tablaCtrl = TextEditingController(text: 'gente');
  final _campoCtrl = TextEditingController();
  final _tipoCtrl = TextEditingController(text: 'TEXT');
  final _filaCtrl = TextEditingController(text: 'nombre=Ana;telefono=123');
  final _idCtrl = TextEditingController();
  final _log = <String>[];

  List<String> _bases = [];
  String _por = 'id';
  bool _asc = true;

  @override
  void dispose() {
    _caja.cerrar();
    _dbCtrl.dispose();
    _claveCtrl.dispose();
    _tablaCtrl.dispose();
    _campoCtrl.dispose();
    _tipoCtrl.dispose();
    _filaCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  void _add(String s) => setState(() {
        _log.add(s);
        if (_log.length > 80) _log.removeAt(0);
      });

  Future<void> _refrescarBases() async {
    try {
      final b = await CajaSql.listarBases();
      if (!mounted) return;
      setState(() => _bases = b);
    } catch (e) {
      _add('✗ listar bases: $e');
    }
  }

  /// Abre (crea si no existe) la db del campo con su clave.
  Future<void> _abrir() async {
    final nombre = _dbCtrl.text.trim();
    final clave = _claveCtrl.text;
    if (nombre.isEmpty || clave.isEmpty) {
      _add('✗ poné nombre de db + clave');
      return;
    }
    try {
      await _caja.abrir(nombre, clave: clave);
      _claveCtrl.clear();
      await _refrescarBases();
      _add('✓ db "$nombre" abierta · tablas: ${_caja.tablas()}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  /// Crea DB de contactos (una tabla, unos campos).
  Future<void> _ejemploContactos() async {
    final clave = _claveCtrl.text;
    if (clave.isEmpty) {
      _add('✗ poné clave primero');
      return;
    }
    try {
      await _caja.abrir('contactos', clave: clave);
      _claveCtrl.clear();
      _dbCtrl.text = 'contactos';
      _tablaCtrl.text = 'gente';
      _caja.crearTabla('gente', {'nombre': 'TEXT', 'telefono': 'TEXT'});
      await _refrescarBases();
      _add('✓ db "contactos" · tabla gente${_caja.campos('gente')}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  /// Crea OTRA db con campos DISTINTOS (notas).
  Future<void> _ejemploNotas() async {
    final clave = _claveCtrl.text;
    if (clave.isEmpty) {
      _add('✗ poné clave primero');
      return;
    }
    try {
      await _caja.abrir('notas', clave: clave);
      _claveCtrl.clear();
      _dbCtrl.text = 'notas';
      _tablaCtrl.text = 'notas';
      _caja.crearTabla(
          'notas', {'titulo': 'TEXT', 'cuerpo': 'TEXT', 'fecha': 'TEXT'});
      await _refrescarBases();
      _add('✓ db "notas" · tabla notas${_caja.campos('notas')}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  Future<void> _cambiar(String nombre) async {
    final clave = _claveCtrl.text;
    if (clave.isEmpty) {
      _add('✗ poné la clave para cambiar a "$nombre"');
      return;
    }
    try {
      await _caja.cambiar(nombre, clave: clave);
      _claveCtrl.clear();
      _dbCtrl.text = nombre;
      _add('✓ ahora en db "$nombre" · tablas: ${_caja.tablas()}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  Future<void> _borrarBase() async {
    final nombre = _dbCtrl.text.trim();
    if (nombre.isEmpty) return;
    try {
      await _caja.borrarBase(nombre);
      await _refrescarBases();
      _add('✓ db "$nombre" borrada');
    } catch (e) {
      _add('✗ $e');
    }
  }

  void _agregarCampo() {
    final t = _tablaCtrl.text.trim();
    final c = _campoCtrl.text.trim();
    final tipo = _tipoCtrl.text.trim().isEmpty ? 'TEXT' : _tipoCtrl.text.trim();
    if (t.isEmpty || c.isEmpty) {
      _add('✗ poné tabla + campo');
      return;
    }
    try {
      // Si la tabla no existe, crearla con ese campo (evita "no such table").
      if (!_caja.tablas().contains(t)) {
        _caja.crearTabla(t, {c: tipo});
        _add('✓ tabla "$t" creada con "$c $tipo" → ${_caja.campos(t)}');
        return;
      }
      _caja.agregarCampo(t, c, tipo);
      _add('✓ campo "$c $tipo" en $t → ${_caja.campos(t)}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  /// Crea la tabla del campo con 2 columnas de ejemplo si está vacía.
  void _crearTabla() {
    final t = _tablaCtrl.text.trim();
    if (t.isEmpty) {
      _add('✗ poné nombre de tabla');
      return;
    }
    try {
      if (t == 'notas') {
        _caja.crearTabla(
            t, {'titulo': 'TEXT', 'cuerpo': 'TEXT', 'fecha': 'TEXT'});
      } else {
        _caja.crearTabla(t, {'nombre': 'TEXT', 'telefono': 'TEXT'});
      }
      _add('✓ tabla "$t" lista → ${_caja.campos(t)}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  void _borrarTabla() {
    final t = _tablaCtrl.text.trim();
    if (t.isEmpty) {
      _add('✗ poné nombre de tabla');
      return;
    }
    try {
      _caja.borrarTabla(t);
      _add('✓ tabla "$t" borrada · tablas: ${_caja.tablas()}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  void _quitarCampo() {
    final t = _tablaCtrl.text.trim();
    final c = _campoCtrl.text.trim();
    if (t.isEmpty || c.isEmpty) {
      _add('✗ poné tabla + campo');
      return;
    }
    try {
      _caja.quitarCampo(t, c);
      _add('✓ campo "$c" fuera de $t → ${_caja.campos(t)}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  /// Fila formato "k=v;k=v" (ej: nombre=Ana;telefono=123).
  Map<String, Object?> _parseFila(String crudo) {
    final m = <String, Object?>{};
    for (final parte in crudo.split(';')) {
      final i = parte.indexOf('=');
      if (i <= 0) continue;
      m[parte.substring(0, i).trim()] = parte.substring(i + 1).trim();
    }
    return m;
  }

  void _agregarFila() {
    final t = _tablaCtrl.text.trim();
    final v = _parseFila(_filaCtrl.text);
    if (t.isEmpty || v.isEmpty) {
      _add('✗ poné tabla + fila "k=v;k=v"');
      return;
    }
    try {
      final id = _caja.agregar(t, v);
      _add('✓ fila id=$id en $t · total ${_caja.contar(t)}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  /// Agrega una LISTA de ejemplo de una (según la tabla).
  void _agregarLista() {
    final t = _tablaCtrl.text.trim();
    if (t.isEmpty) {
      _add('✗ poné tabla');
      return;
    }
    final lote = t == 'notas'
        ? [
            {'titulo': 'uno', 'cuerpo': 'primera', 'fecha': 'hoy'},
            {'titulo': 'dos', 'cuerpo': 'segunda', 'fecha': 'hoy'},
            {'titulo': 'tres', 'cuerpo': 'tercera', 'fecha': 'mañana'},
          ]
        : [
            {'nombre': 'Ana', 'telefono': '111'},
            {'nombre': 'Beto', 'telefono': '222'},
            {'nombre': 'Celia', 'telefono': '333'},
          ];
    try {
      final ids = _caja.agregarLote(t, lote);
      _add('✓ lote $ids en $t · total ${_caja.contar(t)}');
    } catch (e) {
      _add('✗ $e');
    }
  }

  void _listar() {
    final t = _tablaCtrl.text.trim();
    if (t.isEmpty) return;
    try {
      final filas = _caja.listar(t, por: _por, asc: _asc);
      _add('— $t (${filas.length}, por $_por ${_asc ? 'ASC' : 'DESC'}):');
      for (final f in filas.take(10)) {
        _add('  $f');
      }
    } catch (e) {
      _add('✗ $e');
    }
  }

  void _contar() {
    final t = _tablaCtrl.text.trim();
    if (t.isEmpty) return;
    try {
      _add('= $t tiene ${_caja.contar(t)} filas');
    } catch (e) {
      _add('✗ $e');
    }
  }

  void _quitar() {
    final t = _tablaCtrl.text.trim();
    final id = int.tryParse(_idCtrl.text.trim());
    if (t.isEmpty || id == null) {
      _add('✗ poné tabla + id numérico');
      return;
    }
    try {
      final n = _caja.quitar(t, id);
      _add(n > 0 ? '✓ id=$id fuera de $t' : '= id=$id no existe en $t');
    } catch (e) {
      _add('✗ $e');
    }
  }

  Widget _campo(TextEditingController c, String titulo, {bool clave = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TextField(
        controller: c,
        obscureText: clave,
        decoration: InputDecoration(
          labelText: titulo,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _boton(String texto, VoidCallback f) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: ElevatedButton(onPressed: f, child: Text(texto)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('DB abierta: ${_caja.nombreActual ?? 'ninguna'}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        _campo(_dbCtrl, 'Nombre db'),
        _campo(_claveCtrl, 'Clave ChaCha20', clave: true),
        Wrap(children: [
          _boton('Abrir/crear', _abrir),
          _boton('Ej: contactos', _ejemploContactos),
          _boton('Ej: notas', _ejemploNotas),
          _boton('Borrar db', _borrarBase),
          _boton('Refrescar', _refrescarBases),
        ]),
        if (_bases.isNotEmpty) ...[
          const Text('Cambiar db (pedí clave arriba):'),
          Wrap(
            children: [
              for (final b in _bases)
                _boton(b == _caja.nombreActual ? '[$b]' : b, () => _cambiar(b)),
            ],
          ),
        ],
        const Divider(),
        _campo(_tablaCtrl, 'Tabla'),
        _campo(_campoCtrl, 'Campo (para agregar/quitar)'),
        _campo(_tipoCtrl, 'Tipo (ej TEXT, INTEGER)'),
        Wrap(children: [
          _boton('Crear tabla', _crearTabla),
          _boton('Borrar tabla', _borrarTabla),
          _boton('Agregar campo', _agregarCampo),
          _boton('Quitar campo', _quitarCampo),
        ]),
        const Divider(),
        _campo(_filaCtrl, 'Fila "k=v;k=v"'),
        Wrap(children: [
          _boton('Agregar fila', _agregarFila),
          _boton('Agregar lista', _agregarLista),
        ]),
        Row(children: [
          const Text('Orden: '),
          DropdownButton<String>(
            value: _por,
            items: const [
              DropdownMenuItem(value: 'id', child: Text('id')),
              DropdownMenuItem(value: 'rowid', child: Text('rowid')),
            ],
            onChanged: (v) => setState(() => _por = v ?? 'id'),
          ),
          TextButton(
            onPressed: () => setState(() => _asc = !_asc),
            child: Text(_asc ? 'ASC ↓' : 'DESC ↑'),
          ),
        ]),
        _campo(_idCtrl, 'ID (para quitar)'),
        Wrap(children: [
          _boton('Listar', _listar),
          _boton('Contar', _contar),
          _boton('Quitar id', _quitar),
        ]),
        const Divider(),
        // ---- bitácora copiable (igual que Tor: SelectableText + Copiar)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.black.withValues(alpha: .5),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('bitácora db',
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace')),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      final txt = _log.join('\n');
                      if (txt.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: txt));
                      }
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copiar', style: TextStyle(fontSize: 11)),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _log.clear()),
                    icon: const Icon(Icons.delete, size: 14),
                    label:
                        const Text('Limpiar', style: TextStyle(fontSize: 11)),
                  ),
                ]),
                SizedBox(
                  height: 220,
                  child: SingleChildScrollView(
                    child: SelectableText(
                        _log.isEmpty ? '· sin eventos ·' : _log.join('\n'),
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.lightGreenAccent)),
                  ),
                ),
              ]),
        ),
        // Código viejo dejado comentado (regla: no borrar):
        // for (final l in _log) Text(l, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
