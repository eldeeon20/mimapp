import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/media_server/media_server.dart';
import '../toolsec/create_molde_sql.dart';

/// Test de media_server: crear molde desde una carpeta (recursiva, todo
/// cifrado en UN solo .mld), abrirlo, listar archivos y pedir rangos.
class MediaServerTestScreen extends StatefulWidget {
  const MediaServerTestScreen({super.key});

  @override
  State<MediaServerTestScreen> createState() => _MediaServerTestScreenState();
}

class _MediaServerTestScreenState extends State<MediaServerTestScreen> {
  // Crear molde (clave ÚNICA: abre tu SQL y deriva el molde).
  final _nombreCtrl = TextEditingController();
  final _carpetaCtrl = TextEditingController();
  final _claveCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  bool _creando = false;

  // Moldes + abierto (server tonto + filas de TU sql).
  List<MoldeInfo> _moldes = [];
  MoldeInfo? _infoAbierta;
  List<FichaArchivo> _filas = [];
  final _tagFiltroCtrl = TextEditingController();

  // Rango.
  String? _selArchivo;
  final _desdeCtrl = TextEditingController(text: '0');
  final _hastaCtrl = TextEditingController();
  String _rangoInfo = '';

  final List<String> _log = [];
  bool _cargando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _carpetaCtrl.dispose();
    _claveCtrl.dispose();
    _tagsCtrl.dispose();
    _tagFiltroCtrl.dispose();
    _desdeCtrl.dispose();
    _hastaCtrl.dispose();
    super.dispose();
  }

  void _add(String s) {
    if (!mounted) return;
    setState(() => _log.add(s));
  }

  String get _clave => _claveCtrl.text;

  Future<void> _elegirCarpeta() async {
    try {
      final p = await FilePicker.platform.getDirectoryPath();
      if (p != null && p.isNotEmpty && mounted) {
        setState(() => _carpetaCtrl.text = p);
      }
    } catch (e) {
      _add('✗ elegir carpeta: $e');
    }
  }

  Future<void> _crear() async {
    if (_creando) return;
    if (!mounted) return;
    setState(() => _creando = true);
    try {
      final tags = _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      final n = await CreateMoldeSql.crear(
        nombre: _nombreCtrl.text.trim(),
        origenDir: _carpetaCtrl.text.trim(),
        clave: _clave,
        tags: tags,
      );
      _add('✓ molde "${_nombreCtrl.text.trim()}.mld" con $n archivos '
          '(uno solo, primero en 0)');
      await _refrescarMoldes();
    } catch (e) {
      _add('✗ crear: $e');
    }
    if (mounted) setState(() => _creando = false);
  }

  Future<void> _refrescarMoldes() async {
    if (_clave.isEmpty) {
      _add('· poné la clave SQL para listar');
      return;
    }
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      _moldes =
          await CreateMoldeSql.listarMoldes(claveSql: _clave);
      if (mounted) setState(() {});
      _add('· ${_moldes.length} molde(s) en la SQL');
    } catch (e) {
      _add('✗ listar moldes: $e');
    }
    if (mounted) setState(() => _cargando = false);
  }

  /// Server mira el MOLDE, user mira la SQL: la SQL (tool) da info +
  /// filas y con eso se abre el server (sin pass SQL en el server).
  Future<void> _abrir(String nombre) async {
    try {
      final info = await CreateMoldeSql.moldeInfo(
          claveSql: _clave, molde: nombre);
      if (info == null) {
        _add('✗ abrir: "$nombre" no está en tu SQL');
        return;
      }
      final filas = await CreateMoldeSql.filasDe(
          claveSql: _clave, molde: nombre);
      // USER abre su SQL (info+filas); el server solo abre el .mld.
      // Sin tu SQL el server no sabe qué trae el molde.
      // El server solo abre el .mld (sin SQL, sin clave).
      final m = await MediaServer.abrir(rutaMld: info.ruta);
      if (!mounted) return;
      setState(() {
        _infoAbierta = info;
        _filas = filas;
        _selArchivo = null;
        _rangoInfo = '';
      });
      _add('✓ abierto "$nombre": ${filas.length} filas de tu SQL, '
          'server solo ve ${_fmt(m.total)} crudos');
    } catch (e) {
      _add('✗ abrir: $e');
    }
  }

  Future<void> _pedirRango() async {
    final molde = _infoAbierta?.nombre;
    final a = _selArchivo;
    if (molde == null || a == null) return;
    final desde = int.tryParse(_desdeCtrl.text.trim()) ?? -1;
    final hasta = int.tryParse(_hastaCtrl.text.trim()) ?? -1;
    try {
      // Tu SQL → trozos → server crudo → vos descifrás (tool).
      final datos = await CreateMoldeSql.pedirRango(
        claveSql: _clave,
        molde: molde,
        archivo: a,
        desde: desde,
        hasta: hasta,
      );
      final hex = datos
          .take(64)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      if (!mounted) return;
      setState(() {
        _rangoInfo = '✓ [$desde, $hasta) de "$a": ${datos.length} bytes '
            'descifrados\n$hex${datos.length > 64 ? '…' : ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _rangoInfo = '✗ pedir: $e');
    }
  }

  Future<void> _pedirArchivo() async {
    final molde = _infoAbierta?.nombre;
    final a = _selArchivo;
    if (molde == null || a == null) return;
    FichaArchivo? ficha;
    for (final f in _filas) {
      if (f.nombre == a) {
        ficha = f;
        break;
      }
    }
    if (ficha == null) return;
    if (ficha.tamano == 0) {
      if (!mounted) return;
      setState(() {
        _rangoInfo = '✓ "$a" vacío (0 bytes)';
      });
      return;
    }
    try {
      final datos = await CreateMoldeSql.pedirRango(
        claveSql: _clave,
        molde: molde,
        archivo: a,
        desde: 0,
        hasta: ficha.tamano,
      );
      if (!mounted) return;
      setState(() {
        _rangoInfo =
            '✓ "$a" entero: ${datos.length} bytes descifrados';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _rangoInfo = '✗ pedir: $e');
    }
  }

  static const _imgs = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp'
  };
  static const _textos = {
    'txt',
    'md',
    'json',
    'log',
    'csv',
    'xml',
    'html',
    'css',
    'js',
    'srt',
    'vtt',
    'ini',
    'cfg',
    'yaml',
    'yml'
  };

  /// Recupera un archivo en RAM (descifrado desde su rango SQL) y lo
  /// abre en diálogo: imagen → vista, texto → texto, resto → aviso.
  Future<void> _recuperar(FichaArchivo f) async {
    final molde = _infoAbierta?.nombre;
    if (molde == null) return;
    if (f.tamano == 0) {
      _add('· "${f.nombre}" vacío (0 bytes, nada que recuperar)');
      return;
    }
    if (f.tamano > 15 * 1024 * 1024) {
      _add('✗ recuperar "${f.nombre}": ${_fmt(f.tamano)}, muy grande '
          'para RAM (pedí por rangos)');
      return;
    }
    late final List<int> datos;
    try {
      // Tu SQL dice el rango, el server da crudo, vos descifrás (tool).
      datos = await CreateMoldeSql.pedirRango(
        claveSql: _clave,
        molde: molde,
        archivo: f.nombre,
        desde: 0,
        hasta: f.tamano,
      );
    } catch (e) {
      _add('✗ recuperar: $e');
      return;
    }
    if (!mounted) return;
    final fmt = f.formato.toLowerCase();
    Widget cuerpo;
    if (_imgs.contains(fmt)) {
      cuerpo = Image.memory(
        Uint8List.fromList(datos),
        errorBuilder: (_, __, ___) =>
            const Text('bytes descifrados pero no es imagen válida'),
      );
    } else if (_textos.contains(fmt)) {
      cuerpo = SingleChildScrollView(
        child: SelectableText(
          utf8.decode(datos, allowMalformed: true),
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      );
    } else {
      final hex = datos
          .take(128)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      cuerpo = SelectableText(
        'formato ".$fmt" sin vista previa (${datos.length} bytes):\n$hex'
        '${datos.length > 128 ? '…' : ''}',
        style: const TextStyle(fontSize: 11),
      );
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(f.nombre, style: const TextStyle(fontSize: 13)),
        content: SizedBox(
          width: double.maxFinite,
          child: cuerpo,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  /// Edita los tags de UNA entrada (update en tu SQL, no duplica).
  Future<void> _editarTags(FichaArchivo f) async {
    final molde = _infoAbierta?.nombre;
    if (molde == null) return;
    final ctrl = TextEditingController(text: f.tags.join(', '));
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tags de ${f.nombre}',
            style: const TextStyle(fontSize: 13)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'coma, separados (8 máx, 16 letras)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    final tags = ctrl.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    try {
      ctrl.dispose();
    } catch (_) {}
    if (guardar != true) return;
    try {
      await CreateMoldeSql.actualizarTags(
        claveSql: _clave,
        molde: molde,
        archivo: f.nombre,
        tags: tags,
      );
      _add('✓ tags de "${f.nombre}": ${tags.join(', ')}');
      await _abrir(molde);
    } catch (e) {
      _add('✗ tags: $e');
    }
  }

  /// Borra UNA entrada del índice con aviso (popup): solo la fila SQL,
  /// los bytes quedan huérfanos en el .mld.
  Future<void> _borrarEntrada(FichaArchivo f) async {
    final molde = _infoAbierta?.nombre;
    if (molde == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar entrada', style: TextStyle(fontSize: 13)),
        content: Text(
          '"${f.nombre}" sale del índice SQL.\n'
          'AVISO: sus bytes quedan en el .mld (huérfanos); '
          'los demás archivos no se mueven.\n¿Seguir?',
          style: const TextStyle(fontSize: 12),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await CreateMoldeSql.quitarEntrada(
        claveSql: _clave,
        molde: molde,
        archivo: f.nombre,
      );
      if (!mounted) return;
      setState(() {
        if (_selArchivo == f.nombre) {
          _selArchivo = null;
          _rangoInfo = '';
        }
      });
      _add('✓ entrada "${f.nombre}" borrada del índice');
      await _abrir(molde);
    } catch (e) {
      _add('✗ borrar entrada: $e');
    }
  }

  /// Quita duplicados del molde abierto (mismo nombre → deja el primero).
  Future<void> _quitarDuplicados() async {
    final molde = _infoAbierta?.nombre;
    if (molde == null) return;
    try {
      final n = await CreateMoldeSql.quitarDuplicados(
        claveSql: _clave,
        molde: molde,
      );
      _add(n == 0
          ? '· sin duplicados en "$molde"'
          : '✓ $n duplicado(s) quitados de "$molde"');
      await _abrir(molde);
    } catch (e) {
      _add('✗ duplicados: $e');
    }
  }

  Future<void> _borrarMolde(String nombre) async {
    try {
      await CreateMoldeSql.borrar(nombre: nombre, claveSql: _clave);
      if (!mounted) return;
      setState(() {
        if (_infoAbierta?.nombre == nombre) {
          _infoAbierta = null;
          _filas = [];
          _selArchivo = null;
          _rangoInfo = '';
        }
      });
      _add('✓ borrado "$nombre" (.mld + filas SQL)');
      await _refrescarMoldes();
    } catch (e) {
      _add('✗ borrar: $e');
    }
  }

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _tf(TextEditingController c, String hint, {bool oculto = false}) {
    return TextField(
      controller: c,
      obscureText: oculto,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
          hintText: hint, isDense: true, border: const OutlineInputBorder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtroTag = _tagFiltroCtrl.text.trim();
    final archivos = _infoAbierta == null
        ? const <FichaArchivo>[]
        : [
            for (final f in _filas)
              if (filtroTag.isEmpty || f.tags.contains(filtroTag)) f
          ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Crear molde (carpeta → un solo .mld)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _tf(_nombreCtrl, 'nombre molde (ej. molde_test)'),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _tf(_carpetaCtrl, 'carpeta origen…')),
          const SizedBox(width: 6),
          FilledButton.tonal(
              onPressed: _elegirCarpeta, child: const Text('Elegir…')),
        ]),
        const SizedBox(height: 6),
        _tf(_claveCtrl, 'clave ÚNICA (tu SQL + molde)', oculto: true),
        const SizedBox(height: 6),
        _tf(_tagsCtrl, 'tags separados por coma (8 máx, 16 letras)'),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _creando ? null : _crear,
          icon: const Icon(Icons.archive_rounded, size: 18),
          label: Text(_creando ? 'cifrando…' : 'Crear molde'),
        ),
        const Divider(height: 20),
        Row(children: [
          const Text('Moldes en la SQL',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _refrescarMoldes,
          ),
        ]),
        for (final mInfo in _moldes)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              dense: true,
              selected: _infoAbierta?.nombre == mInfo.nombre,
              title: Text('${mInfo.nombre}.mld (${_fmt(mInfo.total)})',
                  style: const TextStyle(fontSize: 13)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                TextButton(
                    onPressed: () => _abrir(mInfo.nombre),
                    child: const Text('Abrir')),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.redAccent),
                  tooltip: 'Borrar molde',
                  onPressed: () => _borrarMolde(mInfo.nombre),
                ),
              ]),
            ),
          ),
        if (_infoAbierta != null) ...[
          const SizedBox(height: 6),
          Text('Abierto "${_infoAbierta!.nombre}" (tu SQL): archivos',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _tf(_tagFiltroCtrl, 'filtrar por tag…'),
          for (final f in archivos)
            ListTile(
              dense: true,
              selected: _selArchivo == f.nombre,
              title: Text(f.nombre, style: const TextStyle(fontSize: 12)),
              subtitle: Text(
                  '${f.formato} · ${_fmt(f.tamano)} · '
                  '[${f.inicio}-${f.fin}]'
                  '${f.tags.isEmpty ? '' : ' · ${f.tags.join(', ')}'}',
                  style: const TextStyle(fontSize: 10)),
              onTap: () => setState(() {
                _selArchivo = f.nombre;
                _hastaCtrl.text = '${f.tamano}';
                _rangoInfo = '';
              }),
              trailing: TextButton(
                onPressed: () => _recuperar(f),
                child: const Text('Recuperar',
                    style: TextStyle(fontSize: 11)),
              ),
            ),
          if (_selArchivo != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _tf(_desdeCtrl, 'desde')),
              const SizedBox(width: 6),
              Expanded(child: _tf(_hastaCtrl, 'hasta')),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: FilledButton.tonal(
                    onPressed: _pedirRango,
                    child: const Text('Pedir rango')),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: FilledButton.tonal(
                    onPressed: _pedirArchivo,
                    child: const Text('Archivo entero')),
              ),
            ]),
            if (_rangoInfo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText(_rangoInfo,
                    style: const TextStyle(fontSize: 11)),
              ),
          ],
        ],
        const Divider(height: 20),
        const Text('Bitácora', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final l in _log)
          SelectableText(l, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
