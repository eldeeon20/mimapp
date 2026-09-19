import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'admin/panel_admin.dart';
import 'app/claves_app.dart';
import 'cache/previa_cache.dart';
import 'cache/sesion_cache.dart';
import 'cache/trozo_cache.dart';
import 'db/caja_sql.dart';
import 'indice/indice.dart';
import 'comun/archivos_fs.dart';
import 'comun/campos.dart';
import 'lista/borrar_entrada.dart';
import 'lista/descargar_archivo.dart';
import 'lista/explorador.dart';
import 'lista/lista_archivos.dart';
import 'lista/pedir_rango.dart';
import 'lista/rango_logica.dart';
import 'moldes/form_crear.dart';
import 'moldes/indexar_dialog.dart';
import 'moldes/lista_moldes.dart';
import 'moldes/tags_dialog.dart';
import 'media_server/media_server.dart';
import 'minis/mini_cache.dart';
import 'minis/mini_grid.dart';
import 'preview/cargar_completo.dart';
import 'preview/visor_preview.dart';
import 'preview/vista_archivo.dart';
import 'preview_molde.dart';
import 'puente_hf.dart';
import 'tool/create_molde_sql.dart';

/// Test de media_server: crear molde desde una carpeta (recursiva, todo
/// cifrado en UN solo .mld), abrirlo, listar archivos y pedir rangos.
class TestSqlScreen extends StatefulWidget {
  const TestSqlScreen({super.key});

  @override
  State<TestSqlScreen> createState() => _TestSqlScreenState();
}

class _TestSqlScreenState extends State<TestSqlScreen>
    with SingleTickerProviderStateMixin {
  /// Controller propio (el DefaultTabController.of con el contexto del
  /// State daba null y reventaba al crear: "Null check operator…").
  late final TabController _tabs;
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

  /// Filas ya filtradas EN SQL (LIKE). null = sin filtro o fallback RAM.
  List<FichaArchivo>? _filasTag;
  final _tagFiltroCtrl = TextEditingController();

  /// Minis en RAM (clase) + caché local cifrada de trozos (LRU 512KB).
  final _minis = MiniCache();

  /// Previas guardadas por archivo (memo, se llena solo).
  final _previas = <String, List<Uint8List>>{};

  /// Lee las previas guardadas de un archivo ([] = sin previas,
  /// moldes viejos: el grid usa mini al vuelo).
  Future<List<Uint8List>> _previasDe(FichaArchivo f) async {
    final m = _infoAbierta?.nombre;
    if (m == null) return [];
    final ya = _previas[f.nombre];
    if (ya != null) return ya;
    // Disco primero (no re-abrir el original).
    try {
      final disco = await _previaCache?.leer(archivo: f.nombre);
      if (disco != null && disco.isNotEmpty) {
        _previas[f.nombre] = [disco];
        return [disco];
      }
    } catch (_) {}
    try {
      final p = await CreateMoldeSql.previasDe(
        claveSql: _clave,
        molde: m,
        archivo: f.nombre,
        cache: _cache,
        info: _infoAbierta,
      );
      _previas[f.nombre] = p;
      // Primera a disco (las demás viven en la transición en RAM).
      if (p.isNotEmpty) {
        try {
          await _previaCache?.guardar(archivo: f.nombre, previa: p.first);
        } catch (_) {}
      }
      return p;
    } catch (_) {
      return [];
    }
  }

  /// Captura de video (surface oculta mientras se crea).
  final _captura = CapturaVideo();
  TrozoCache? _cache;

  /// Caché de previas en disco (no re-abrir originales).
  PreviaCache? _previaCache;

  /// Ajustes: topes de caché (viven en ajustes_modo.json).
  int _limiteTrozosKb = 512;
  int _limitePreviasMb = 8;

  Future<File> _ajustesFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/ajustes_modo.json');
  }

  Future<void> _cargarAjustes() async {
    try {
      final f = await _ajustesFile();
      if (await f.exists()) {
        final m =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        _limiteTrozosKb =
            ((m['trozosKb'] as num?)?.toInt() ?? 512).clamp(128, 8192);
        _limitePreviasMb =
            ((m['previasMb'] as num?)?.toInt() ?? 8).clamp(1, 64);
      }
    } catch (_) {}
    final c = _cache;
    if (c != null) c.limiteBytes = _limiteTrozosKb * 1024;
    final p = _previaCache;
    if (p != null) p.limiteBytes = _limitePreviasMb * 1024 * 1024;
    if (mounted) setState(() {});
  }

  Future<void> _guardarAjustes() async {
    try {
      final f = await _ajustesFile();
      await f.writeAsString(
        jsonEncode({
          'trozosKb': _limiteTrozosKb,
          'previasMb': _limitePreviasMb,
        }),
        flush: true,
      );
    } catch (_) {}
  }

  /// Recordar clave cifrada en la SQL local de la app.
  bool _recordar = true;

  /// Bytes completos memoizados para el visor (clase).
  final _completos = CargadorCompleto();

  // Rango.
  String? _selArchivo;
  final _desdeCtrl = TextEditingController(text: '0');
  final _hastaCtrl = TextEditingController();
  String _rangoInfo = '';

  final List<String> _log = [];
  bool _cargando = false;

  /// HF: repo (dir/user) + token por molde + puente.
  final _hfRepoCtrl = TextEditingController();
  final _hfTokenCtrl = TextEditingController();
  final _hfSqlCtrl = TextEditingController();
  final _puenteHf = PuenteHf();
  bool _hfOcupado = false;

  @override
  void dispose() {
    _filtroT?.cancel();
    _tagFiltroCtrl.removeListener(_filtroCambio);
    CajaSql.log = null;
    Indice.log = null;
    _captura.cerrar();
    _nombreCtrl.dispose();
    _carpetaCtrl.dispose();
    _claveCtrl.dispose();
    _tagsCtrl.dispose();
    _tagFiltroCtrl.dispose();
    _desdeCtrl.dispose();
    _hastaCtrl.dispose();
    _indiceCtrl.dispose();
    _sesionCache.cerrar();
    _tabs.dispose();
    super.dispose();
  }

  void _add(String s) {
    if (!mounted) return;
    setState(() => _log.add(s));
  }

  String get _clave => _claveCtrl.text;

  Future<void> _elegirCarpeta() async {
    final p = await elegirCarpeta();
    if (p != null && mounted) setState(() => _carpetaCtrl.text = p);
  }

  /// Estado visible EN Crear (antes el resultado solo iba a la
  /// bitácora de Moldes y parecía que "no hacía nada").
  String _crearEstado = '';

  Future<void> _crear() async {
    if (_creando) return;
    if (!mounted) return;
    setState(() {
      _creando = true;
      _crearEstado = '· pidiendo permiso…';
    });
    if (!await accesoCarpeta()) {
      const m = '✗ sin permiso: dale acceso total en '
          'Ajustes → Apps → test_sql';
      _add(m);
      if (!mounted) return;
      setState(() {
        _creando = false;
        _crearEstado = m;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _crearEstado = '· cifrando…');
    try {
      final tags = _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      final nombre = _nombreCtrl.text.trim();
      final n = await CreateMoldeSql.crear(
        nombre: nombre,
        origenDir: _carpetaCtrl.text.trim(),
        clave: _clave,
        tags: tags,
        passIndice: await _passIndice(),
        captura: _captura,
        log: _add,
      );
      _add('✓ molde "$nombre.mld" con $n archivos '
          '(uno solo, primero en 0)');
      await _refrescarMoldes();
      if (!mounted) return;
      setState(() {
        _crearEstado =
            '✓ "$nombre" con $n archivos → mirá la pestaña Moldes';
      });
      _nombreCtrl.clear();
      _tabs.animateTo(3);
    } catch (e) {
      _add('✗ crear: $e');
      if (!mounted) return;
      setState(() => _crearEstado = '✗ crear: $e');
    }
    if (mounted) setState(() => _creando = false);
  }

  /// Sesión de caché (se desbloquea con la pass del índice).
  final _sesionCache = SesionCache();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    // Filtro de tag en vivo con debounce: sin esto solo filtraba
    // cuando otro rebuild lo arrastraba (ej. al abrir una imagen).
    _tagFiltroCtrl.addListener(_filtroCambio);
    // Avisos de formato (lo viejo sale en rojo en la bitácora).
    CajaSql.log = _add;
    Indice.log = _add;
    _cargarAjustes();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _preguntarIndice());
  }

  /// Debounce del filtro (~300ms): con texto va a SQL (LIKE sobre
  /// columnas en bruto); vacío vuelve al listado en RAM.
  Timer? _filtroT;
  void _filtroCambio() {
    _filtroT?.cancel();
    _filtroT = Timer(const Duration(milliseconds: 300), () async {
      final m = _infoAbierta?.nombre;
      final t = _tagFiltroCtrl.text.trim();
      if (m == null || t.isEmpty) {
        if (mounted) setState(() => _filasTag = null);
        return;
      }
      try {
        final filas = await CreateMoldeSql.filasPorTag(
            claveSql: _clave, molde: m, tag: t);
        if (!mounted) return;
        // El filtro cambió mientras consultaba: se descarta.
        if (_tagFiltroCtrl.text.trim() != t) return;
        setState(() => _filasTag = filas);
      } catch (e) {
        _add('✗ filtro tag: $e');
      }
    });
  }

  /// Al entrar SIEMPRE pide la pass del índice (no se guarda).
  /// Se puede saltear con "Ahora no" y ponerla en Moldes.
  Future<void> _preguntarIndice() async {
    if (!mounted) return;
    // Permiso de primera: sin "todos los archivos" no lista carpetas.
    if (!await accesoCarpeta()) {
      if (!mounted) return;
      final ir = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Permiso de archivos',
              style: TextStyle(fontSize: 14)),
          content: const Text(
            'Sin acceso total no se listan carpetas ni moldes. '
            'Dalo en Ajustes → Apps → test_sql.',
            style: TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Seguir igual')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Abrir ajustes')),
          ],
        ),
      );
      if (ir == true) await abrirAjustes();
      if (!mounted) return;
    }
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Clave del índice',
            style: TextStyle(fontSize: 14)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'propia del índice (no se guarda)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ahora no')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Abrir')),
        ],
      ),
    );
    try {
      ctrl.dispose();
    } catch (_) {}
    if (!mounted) return;
    if (ok == true && ctrl.text.isNotEmpty) {
      setState(() => _indiceCtrl.text = ctrl.text);
    }
    await _refrescarMoldes(auto: true);
  }

  /// Clave del ÍNDICE (propia, se pide al iniciar, NO se guarda).
  final _indiceCtrl = TextEditingController();

  /// Clave del índice: solo la escrita (nunca recordada).
  Future<String> _passIndice() async => _indiceCtrl.text;

  /// Pass de cada molde según el índice (liviano: qué sql + su pass).
  final Map<String, String> _passPorMolde = {};

  /// Entradas crudas del índice (para el panel admin).
  final Map<String, Map<String, Object?>> _entradas = {};

  /// Carpetas desde el ÍNDICE cifrado (sin abrir las SQL de moldes).
  /// Con [auto] y un solo molde, lo abre solo.
  Future<void> _refrescarMoldes({bool auto = false}) async {
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final p = await _passIndice();
      if (p.isEmpty) {
        _add('· poné la clave del ÍNDICE para ver el historial');
        if (mounted) setState(() {});
        return;
      }
      await Indice.asegurar(p);
      // La caché comparte la pass del índice: se desbloquea acá.
      try {
        await _sesionCache.abrir(p);
        _add('· caché desbloqueada (misma pass del índice)');
      } catch (e) {
        _add('✗ caché: $e');
      }
      final crudo = await Indice.listarRaw(p);
      final vistos = <String>{};
      _moldes = [];
      _passPorMolde.clear();
      _entradas.clear();
      for (final m in crudo) {
        final nombre = '${m['nombre'] ?? ''}';
        if (nombre.isEmpty || !vistos.add(nombre)) continue;
        _moldes.add(MoldeInfo(
          nombre: nombre,
          ruta: '${m['mld_ruta'] ?? ''}',
          fecha: (m['fecha'] as int?) ?? 0,
          total: (m['total'] as int?) ?? 0,
          sal: '${m['sal'] ?? ''}',
          cifrado: '${m['cifrado'] ?? ''}',
        ));
        final pm = '${m['pass'] ?? ''}';
        if (pm.isNotEmpty) _passPorMolde[nombre] = pm;
        _entradas[nombre] = m;
      }
      // SQL vieja compartida: suma los que el índice aún no tiene.
      try {
        final viejos =
            await CreateMoldeSql.listarMoldes(claveSql: 'x');
        for (final v in viejos) {
          if (vistos.add(v.nombre)) _moldes.add(v);
        }
      } catch (_) {}
      if (mounted) setState(() {});
      _add('· ${_moldes.length} molde(s) en el índice');
      // Un solo molde = se abre solo (sin tap).
      if (auto &&
          _moldes.length == 1 &&
          _infoAbierta == null &&
          mounted) {
        await _abrirMolde(_moldes.first.nombre);
      }
    } catch (e) {
      _add('✗ índice: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
      // Caché en bruto sobre la sesión (misma pass del índice).
      final TrozoCache? cache = _sesionCache.abierta
          ? TrozoCache(
              sesion: _sesionCache,
              molde: nombre,
              limiteBytes: _limiteTrozosKb * 1024)
          : null;
      final PreviaCache? pcache = _sesionCache.abierta
          ? PreviaCache(
              sesion: _sesionCache,
              molde: nombre,
              limiteBytes: _limitePreviasMb * 1024 * 1024)
          : null;
      if (cache == null) {
        _add('· sin caché (índice bloqueado: solo server)');
      }
      if (!mounted) return;
      setState(() {
        _infoAbierta = info;
        _filas = filas;
        _filasTag = null;
        _previas.clear();
        _selArchivo = null;
        _rangoInfo = '';
        _minis.limpiar();
        _completos.limpiar();
        // Misma referencia: el visor reusa lo que el grid descifró.
        _completos.minis = _minis.minis;
        _rutaExp = const [];
        _cache = cache;
        _previaCache = pcache;
      });
      _add('✓ abierto "$nombre": ${filas.length} filas de tu SQL, '
          'server solo ve ${fmtBytes(m.total)} crudos, '
          'caché local 512KB lista');
      // Prefetch EN ORDEN del nivel actual (los carriles las sacan
      // en orden y el grid se llena sin saltar grillas).
      _preFetchMinis(
          nombre, info, hijosDe(filas, _rutaExp).directos);
      if (_recordar) {
        await ClavesApp().guardar(nombre, _clave);
        _add('· clave de "$nombre" recordada (cifrada, app local)');
      }
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
    final texto = await pedirRangoTexto(
      claveSql: _clave,
      molde: molde,
      archivo: a,
      desde: desde,
      hasta: hasta,
      cache: _cache,
      info: _infoAbierta,
      filas: _filas,
    );
    if (!mounted) return;
    setState(() => _rangoInfo = texto);
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
    final texto = await pedirArchivoTexto(
      claveSql: _clave,
      molde: molde,
      ficha: ficha,
      cache: _cache,
      info: _infoAbierta,
      filas: _filas,
    );
    if (!mounted) return;
    setState(() => _rangoInfo = texto);
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
      _add('✗ recuperar "${f.nombre}": ${fmtBytes(f.tamano)}, muy grande '
          'para RAM (pedí por rangos)');
      return;
    }
    // Imágenes → visor pantalla completa con swipe (principal).
    if (_imgs.contains(f.formato.toLowerCase())) {
      final lista = _soloImgs(_filtrados());
      final vista = lista.isEmpty ? [f] : lista;
      var idx = vista.indexWhere((x) => x.nombre == f.nombre);
      if (idx < 0) idx = 0;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.black,
          child: VisorPreview(
            imagenes: vista,
            indiceInicial: idx,
            cargar: _bytesCompletos,
            tagsDe: _tagsFrescos,
            onTags: (a) => _editarTags(a),
            onGuardar: (a, b) => _guardarCopia(a.nombre, b),
          ),
        ),
      );
      return;
    }
    late final List<int> datos;
    try {
      // Tu SQL dice el rango, la caché/server da crudo, vos descifrás.
      datos = await CreateMoldeSql.pedirRango(
        claveSql: _clave,
        molde: molde,
        archivo: f.nombre,
        desde: 0,
        hasta: f.tamano,
        cache: _cache,
        info: _infoAbierta,
        filas: _filas,
      );
      if (_cache != null) _add('· ${_cache!.resumen()}');
    } catch (e) {
      _add('✗ recuperar: $e');
      return;
    }
    if (!mounted) return;
    final copia = Uint8List.fromList(datos);
    await mostrarVistaArchivo(
      context: context,
      f: f,
      datos: copia,
      imgs: _imgs,
      textos: _textos,
      onTags: () => _editarTags(f),
      tagsFrescos: () {
        for (final x in _filas) {
          if (x.nombre == f.nombre) return x.tags.join(', ');
        }
        return f.tags.join(', ');
      },
      onGuardarCopia: () => _guardarCopia(f.nombre, copia),
    );
  }

  /// Guarda copia en Descargas (bytes ya descifrados).
  Future<void> _guardarCopia(String nombre, Uint8List datos) =>
      guardarCopia(nombre: nombre, datos: datos, log: _add);

  /// Edita los tags de UNA entrada (popup en su archivo).
  Future<void> _editarTags(FichaArchivo f) async {
    final molde = _infoAbierta?.nombre;
    if (molde == null) return;
    await editarTagsMolde(
      context: context,
      f: f,
      claveSql: _clave,
      molde: molde,
      onListo: () => _abrir(molde),
      log: _add,
    );
  }

  /// Descarga un archivo a Download (por partes, sin tope RAM).
  /// El tap abre preview; el botón Descargar baja el archivo.
  Future<void> _descargarArchivo(FichaArchivo f) async {
    final molde = _infoAbierta?.nombre;
    if (molde == null) return;
    await descargarArchivo(
      claveSql: _clave,
      molde: molde,
      ficha: f,
      cache: _cache,
      info: _infoAbierta,
      filas: _filas,
      log: _add,
    );
    if (_cache != null) _add('· ${_cache!.resumen()}');
  }

  /// Cierra el molde y vuelve a la RAÍZ (la lista de moldes
  /// en la misma pestaña: el grid/lista la muestran solos).
  void _cerrarMolde() {
    setState(() {
      _infoAbierta = null;
      _filas = [];
      _filasTag = null;
      _previas.clear();
      _selArchivo = null;
      _rangoInfo = '';
      _rutaExp = const [];
      _minis.limpiar();
      _completos.limpiar();
    });
    _add('· molde cerrado (de vuelta a los moldes)');
  }

  /// Mueve un molde a otro directorio (admin): .db + .mld juntos,
  /// actualiza la SQL y el índice. Si era el abierto, lo reabre.
  Future<void> _moverMolde(String nombre) async {
    final dir = await elegirCarpeta();
    if (dir == null || dir.isEmpty) return;
    if (!mounted) return;
    try {
      _add('· moviendo "$nombre" a "$dir"…');
      await CreateMoldeSql.moverMolde(
        claveSql: _passPorMolde[nombre] ?? _clave,
        molde: nombre,
        passIndice: await _passIndice(),
        nuevoDir: dir,
      );
      _add('✓ "$nombre" movido a "$dir"');
      if (_infoAbierta?.nombre == nombre) {
        await _abrirMolde(nombre);
      } else {
        await _refrescarMoldes();
      }
    } catch (e) {
      _add('✗ mover: $e');
    }
  }

  /// Edita a mano las rutas de un molde (URL, IP, no físico).
  /// No valida: si no abre, el error sale al abrir el molde.
  Future<void> _editarRutas(String nombre) async {
    final ent = _entradas[nombre];
    final dbCtrl = TextEditingController(
        text: '${ent?['db_ruta'] ?? ''}');
    final mldCtrl = TextEditingController(
        text: '${ent?['mld_ruta'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rutas de $nombre',
            style: const TextStyle(fontSize: 13)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dbCtrl,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  labelText: 'SQL (ruta, URL o IP)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: mldCtrl,
                style: const TextStyle(fontSize: 11),
                decoration: const InputDecoration(
                  labelText: 'MLD (ruta, URL o IP)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
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
    final dbRuta = dbCtrl.text.trim();
    final mldRuta = mldCtrl.text.trim();
    try {
      dbCtrl.dispose();
      mldCtrl.dispose();
    } catch (_) {}
    if (ok != true) return;
    try {
      await Indice.actualizarRutas(
        pass: await _passIndice(),
        nombre: nombre,
        dbRuta: dbRuta,
        mldRuta: mldRuta,
      );
      _add('✓ rutas de "$nombre" editadas a mano');
      if (_infoAbierta?.nombre == nombre) {
        await _abrirMolde(nombre);
      } else {
        await _refrescarMoldes();
      }
    } catch (e) {
      _add('✗ editar rutas: $e');
    }
  }

  /// Indexa por carpeta: rastrea .mld y añade al índice con su pass.
  /// (molde = carpeta: 30 moldes = 30 lugares, se indexan al elegir).
  Future<void> _indexarCarpeta() async {
    final dir = await elegirCarpeta();
    if (dir == null || dir.isEmpty) return;
    if (!mounted) return;
    try {
      _add('· rastreando "$dir"…');
      final hallados = await CreateMoldeSql.rastrearCarpeta(
        dir,
        claveSql: _clave,
      );
      if (hallados.isEmpty) {
        _add('· sin .mld con SQL en "$dir"');
        return;
      }
      _add('· ${hallados.length} molde(s) en "$dir"');
      if (!mounted) return;
      await mostrarParaIndexar(
        context: context,
        hallados: hallados,
        onAnadir: (nombre, passMolde) async {
          try {
            final h = hallados.firstWhere(
                (e) => '${e['nombre']}' == nombre);
            await Indice.registrar(
              pass: await _passIndice(),
              nombre: nombre,
              dbRuta: '${h['db_ruta'] ?? ''}',
              mldRuta: '${h['mld_ruta'] ?? ''}',
              n: (h['n'] as int?) ?? 0,
              total: (h['total'] as int?) ?? 0,
              sal: '${h['sal'] ?? ''}',
              passMolde: passMolde,
            );
            if (_recordar && passMolde.isNotEmpty) {
              await ClavesApp().guardar(nombre, passMolde);
            }
            _add('✓ "$nombre" al índice');
            await _refrescarMoldes();
          } catch (e) {
            _add('✗ indexar "$nombre": $e');
          }
        },
      );
    } catch (e) {
      _add('✗ rastrear: $e');
    }
  }

  /// Borra UNA entrada del índice con aviso (popup).
  Future<void> _borrarEntrada(FichaArchivo f) async {
    final molde = _infoAbierta?.nombre;
    if (molde == null) return;
    await borrarEntrada(
      context: context,
      f: f,
      claveSql: _clave,
      molde: molde,
      onListo: () => _abrir(molde),
      log: _add,
      alBorrar: () {
        if (!mounted) return;
        setState(() {
          if (_selArchivo == f.nombre) {
            _selArchivo = null;
            _rangoInfo = '';
          }
        });
      },
    );
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

  /// Abre un molde: pass del ÍNDICE → recordada → escrita.
  /// Si vive en la SQL vieja, lo migra a su propia SQL al abrir.
  Future<void> _abrirMolde(String nombre) async {
    if (_infoAbierta?.nombre == nombre) {
      // Ya está abierto: solo ir al grid si estamos en Moldes.
      if (mounted && _tabs.index == 3) _tabs.animateTo(0);
      return;
    }
    var pass = _passPorMolde[nombre] ?? '';
    if (pass.isEmpty) {
      pass = await ClavesApp().leer(nombre) ?? '';
    }
    if (pass.isEmpty) pass = _clave;
    if (pass.isEmpty) {
      _add('· poné la clave de "$nombre" para abrir');
      return;
    }
    if (mounted && _clave != pass) {
      setState(() => _claveCtrl.text = pass);
    }
    try {
      final migro = await CreateMoldeSql.migrarSiHaceFalta(
        claveSql: pass,
        molde: nombre,
        passIndice: await _passIndice(),
      );
      if (migro) {
        _add('✓ "$nombre" migrado a su propia SQL');
        await _refrescarMoldes();
      }
    } catch (e) {
      _add('✗ migrar: $e');
    }
    await _abrir(nombre);
    // Si se abrió desde la pestaña Moldes, llevar al grid a verlo.
    if (mounted && _infoAbierta != null && _tabs.index == 3) {
      _tabs.animateTo(0);
    }
  }

  Future<void> _borrarMolde(String nombre) async {
    try {
      await CreateMoldeSql.borrar(
        nombre: nombre,
        claveSql: _clave.isEmpty ? 'x' : _clave,
        passIndice: await _passIndice(),
      );
      await ClavesApp().borrar(nombre);
      if (!mounted) return;
      setState(() {
        if (_infoAbierta?.nombre == nombre) {
          _infoAbierta = null;
          _filas = [];
          _filasTag = null;
          _previas.clear();
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

  /// Ruta dentro del molde (explorador). Se limpia al abrir.
  List<String> _rutaExp = const [];

  /// Solo imágenes, en orden alfabético (respeta carpetas/orden).
  static List<FichaArchivo> _soloImgs(List<FichaArchivo> archivos) {
    final imgs = [
      for (final f in archivos)
        if (_imgs.contains(f.formato.toLowerCase())) f
    ];
    imgs.sort((a, b) => a.nombre.compareTo(b.nombre));
    return imgs;
  }

  /// Filas del abierto con el filtro de tag aplicado.
  /// Con texto: ya vienen filtradas de SQL. Sin texto o legacy:
  /// filtro manual en RAM.
  List<FichaArchivo> _filtrados() {
    final ft = _filasTag;
    if (ft != null) return ft;
    final t = _tagFiltroCtrl.text.trim();
    return [
      for (final f in _filas)
        if (t.isEmpty || f.tags.contains(t)) f
    ];
  }

  /// Encola minis en orden de índice (sin await: la cola manda).
  void _preFetchMinis(
      String molde, MoldeInfo info, List<FichaArchivo> filas) {
    var n = 0;
    for (final f in filas) {
      if (!_imgs.contains(f.formato.toLowerCase())) continue;
      if (n >= 60) break;
      n++;
      // Sin await a propósito: entra a la cola en orden.
      _minis.de(
        claveSql: _clave,
        molde: molde,
        f: f,
        imgs: _imgs,
        cache: _cache,
        info: info,
        filas: filas,
      );
    }
  }

  /// Tags frescos de un archivo (tras editar tags + reabrir).
  String _tagsFrescos(FichaArchivo f) {
    for (final x in _filas) {
      if (x.nombre == f.nombre) return x.tags.join(', ');
    }
    return f.tags.join(', ');
  }

  /// Bytes completos para el visor (clase, memoizados, con caché).
  Future<Uint8List?> _bytesCompletos(FichaArchivo f) {
    final molde = _infoAbierta?.nombre;
    if (molde == null) return Future.value(null);
    return _completos.de(
      claveSql: _clave,
      molde: molde,
      f: f,
      cache: _cache,
      info: _infoAbierta,
      filas: _filas,
    );
  }

  @override
  Widget build(BuildContext context) {
    final archivos = _filtrados();
    // Atrás del celu navega: subcarpeta → raíz del molde → moldes.
    final dentro = _infoAbierta != null || _rutaExp.isNotEmpty;
    return PopScope(
      canPop: !dentro,
      onPopInvokedWithResult: (salio, _) {
        if (salio) return;
        if (_rutaExp.isNotEmpty) {
          setState(() => _rutaExp =
              _rutaExp.sublist(0, _rutaExp.length - 1));
        } else if (_infoAbierta != null) {
          _cerrarMolde();
        }
      },
      child: Stack(children: [
        Column(children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Cuadrícula'),
            Tab(text: 'Lista'),
            Tab(text: 'Crear'),
            Tab(text: 'Moldes'),
            Tab(text: 'Ajustes'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            // Sin deslizar: las pestañas solo cambian tocando arriba.
            // El dedo horizontal ya no te saca del grid/lista.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _tabCuadricula(archivos),
              _tabLista(archivos),
              _tabCrear(),
              _tabMoldes(),
              _tabAdmin(),
            ],
          ),
        ),
        ]),
        // Surface oculta para capturas de video al crear (1px,
        // sin esto el mpv no renderiza y no hay frames).
        Positioned(
          left: 0,
          top: 0,
          width: 1,
          height: 1,
          child: _captura.vista(),
        ),
      ]),
    );
  }

  /// Modo suave: 2 hilos de descifrado (scroll libre, en orden).
  bool _suave = false;

  /// Caché visible en Admin (bytes por molde + hits/miss).
  final Map<String, int> _cacheBytes = {};
  String _cacheResumen = '';

  Future<void> _medirCache() async {
    final c = _cache;
    final molde = _infoAbierta?.nombre;
    if (c == null || molde == null) return;
    try {
      final b = await c.bytesEnCache();
      if (!mounted) return;
      setState(() {
        _cacheBytes[molde] = b;
        _cacheResumen = c.resumen();
      });
    } catch (_) {}
  }

  Future<void> _vaciarCache() async {
    try {
      await TrozoCache.limpiarTodo(_sesionCache);
      await PreviaCache.limpiarTodo(_sesionCache);
      if (!mounted) return;
      setState(() {
        _cacheBytes.clear();
        _cacheResumen = 'vacía';
      });
      _add('✓ cachés vaciadas (trozos + previas, se reconstruyen solas)');
    } catch (e) {
      _add('✗ vaciar cachés: $e');
    }
  }

  /// Ajustes: cachés (trozos + previas) + admin clásico abajo.
  /// (PanelAdmin ya es ListView: va en Expanded, no anidado.)
  Widget _tabAdmin() {
    final lista = _entradas.values.toList()
      ..sort((a, b) =>
          '${a['nombre']}'.compareTo('${b['nombre']}'));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cachés (sqlite cifradas, misma pass del índice)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Trozos por molde: $_limiteTrozosKb KB '
                  '(bloques del .mld, no re-pedir)'),
              Slider(
                min: 128,
                max: 8192,
                divisions: 31,
                value: _limiteTrozosKb.toDouble().clamp(128, 8192),
                label: '$_limiteTrozosKb KB',
                onChanged: (v) {
                  setState(
                      () => _limiteTrozosKb = v.toInt().clamp(128, 8192));
                  final c = _cache;
                  if (c != null) c.limiteBytes = _limiteTrozosKb * 1024;
                  _guardarAjustes();
                },
              ),
              Text('Previas por molde: $_limitePreviasMb MB '
                  '(libres: miles de previas mínimas)'),
              Slider(
                min: 1,
                max: 64,
                divisions: 63,
                value: _limitePreviasMb.toDouble().clamp(1, 64),
                label: '$_limitePreviasMb MB',
                onChanged: (v) {
                  setState(
                      () => _limitePreviasMb = v.toInt().clamp(1, 64));
                  final p = _previaCache;
                  if (p != null) {
                    p.limiteBytes = _limitePreviasMb * 1024 * 1024;
                  }
                  _guardarAjustes();
                },
              ),
              Text(_cacheResumen.isEmpty
                  ? 'Sin medición todavía'
                  : _cacheResumen),
              const Divider(height: 12),
            ],
          ),
        ),
        Expanded(
          child: PanelAdmin(
            entradas: lista,
            onMover: _moverMolde,
            onEditarRutas: _editarRutas,
            cacheBytes: _cacheBytes,
            cacheResumen: _cacheResumen,
            cacheLimiteKb: _limiteTrozosKb,
            onVaciarCache: _vaciarCache,
            suave: _suave,
            onSuave: (v) => setState(() {
              _suave = v;
              _minis.maxEnVuelo = v ? 2 : 6;
            }),
            hilosEnUso: _minis.enVuelo,
            maxHilos: _minis.maxEnVuelo,
          ),
        ),
      ],
    );
  }

  /// Principal: visor en cuadrícula con scroll LIBRE (un solo
  /// scroll sliver, sin caja anidada que trabe el dedo).
  /// Carpetas de moldes (para grid y lista cuando no hay abierto).
  Widget _carpetasMoldes() {
    return ListaMoldes(
      moldes: _moldes,
      abierta: _infoAbierta?.nombre,
      cargando: _cargando,
      onRecargar: _refrescarMoldes,
      onAbrir: _abrirMolde,
      onBorrar: _borrarMolde,
      // Grid/lista no borran: eso es de la pestaña Moldes.
      conBorrar: false,
    );
  }

  Widget _tabCuadricula(List<FichaArchivo> archivos) {
    if (_infoAbierta == null) {
      // Grid y lista también muestran los moldes como carpetas.
      if (_moldes.isEmpty) {
        return VacioConMas(
          texto: 'No hay moldes cargados',
          boton: 'Crear molde',
          onMas: () => _tabs.animateTo(2),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Moldes (tocá la carpeta para abrir)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _carpetasMoldes(),
        ],
      );
    }
    // Explorador también en grid: carpetas + imágenes de la ruta.
    final hijos = hijosDe(archivos, _rutaExp);
    return MiniGrid(
      imagenes: _soloImgs(hijos.directos),
      otros: [
        for (final f in hijos.directos)
          if (!_imgs.contains(f.formato.toLowerCase())) f
      ],
      minis: _minis.minis,
      minisEnRam: _minis.cuantas,
      selNombre: _selArchivo,
      previas: _previas,
      previasDe: _previasDe,
      esVideo: (f) => PreviewMolde.esVideo(f.formato),
      dirs: hijos.subdirs,
      onEntrarDir: (d) =>
          setState(() => _rutaExp = [..._rutaExp, d]),
      encabezado: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Visor (tocá para pantalla completa)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          campoTexto(_tagFiltroCtrl, 'filtrar por tag…'),
          const SizedBox(height: 6),
          migasRuta(
            molde: _infoAbierta!.nombre,
            ruta: _rutaExp,
            onRuta: (nueva) =>
                setState(() => _rutaExp = nueva),
            onSalir: _cerrarMolde,
          ),
        ],
      ),
      miniDe: (f) => _minis.de(
        claveSql: _clave,
        molde: _infoAbierta!.nombre,
        f: f,
        imgs: _imgs,
        cache: _cache,
        info: _infoAbierta,
        filas: _filas,
        log: _add,
      ),
      onTap: (f) {
        setState(() {
          _selArchivo = f.nombre;
          _hastaCtrl.text = '${f.tamano}';
          _rangoInfo = '';
        });
        _recuperar(f);
      },
    );
  }

  /// Explorador del molde (sus carpetas nativas, se entra y sale).
  Widget _tabLista(List<FichaArchivo> archivos) {
    if (_infoAbierta == null) {
      if (_moldes.isEmpty) {
        return VacioConMas(
          texto: 'No hay moldes cargados',
          boton: 'Crear molde',
          onMas: () => _tabs.animateTo(2),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Moldes (tocá la carpeta para abrir)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          _carpetasMoldes(),
        ],
      );
    }
    // Un solo scroll libre + filas perezosas (solo lo visible).
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                        'Lista de "${_infoAbierta!.nombre}"',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: _quitarDuplicados,
                    child: const Text('Quitar duplicados',
                        style: TextStyle(fontSize: 11)),
                  ),
                ]),
                const SizedBox(height: 6),
                campoTexto(_tagFiltroCtrl, 'filtrar por tag…'),
              ],
            ),
          ),
        ),
        ...sliversExplorador(
          molde: _infoAbierta!.nombre,
          archivos: archivos,
          ruta: _rutaExp,
          onRuta: (nueva) => setState(() => _rutaExp = nueva),
          sel: _selArchivo,
          onSel: (f) {
            setState(() {
              _selArchivo = f.nombre;
              _hastaCtrl.text = '${f.tamano}';
              _rangoInfo = '';
            });
            // Tap = preview directo (visor si es imagen, si no abre).
            _recuperar(f);
          },
          onTags: _editarTags,
          onRecuperar: _descargarArchivo,
          onBorrar: _borrarEntrada,
          onSalir: _cerrarMolde,
        ),
        if (_selArchivo != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: PedirRango(
                desde: _desdeCtrl,
                hasta: _hastaCtrl,
                info: _rangoInfo,
                onRango: _pedirRango,
                onEntero: _pedirArchivo,
              ),
            ),
          ),
      ],
    );
  }

  /// Crear: solo el formulario.
  Widget _tabCrear() {
    return FormCrear(
      nombre: _nombreCtrl,
      carpeta: _carpetaCtrl,
      clave: _claveCtrl,
      tags: _tagsCtrl,
      creando: _creando,
      estado: _crearEstado,
      onElegir: _elegirCarpeta,
      onCrear: _crear,
    );
  }

  /// HF: guarda repo (dir/user) + token del molde ABIERTO.
  Future<void> _hfGuardar() async {
    final m = _infoAbierta?.nombre;
    if (m == null) {
      _add('· HF: abrí un molde primero');
      return;
    }
    try {
      await Indice.guardarHf(
        pass: await _passIndice(),
        nombre: m,
        hfRepo: _hfRepoCtrl.text.trim(),
        hfToken: _hfTokenCtrl.text.trim(),
      );
      _add('✓ HF de "$m" guardado');
      if (mounted) setState(() {});
    } catch (e) {
      _add('✗ HF guardar: $e');
    }
  }

  /// HF: sube .mld + SQL + indice.db del molde abierto.
  Future<void> _hfSubir() async {
    if (_hfOcupado) return;
    final m = _infoAbierta?.nombre;
    if (m == null) {
      _add('· HF: abrí un molde primero');
      return;
    }
    setState(() => _hfOcupado = true);
    try {
      await _puenteHf.subirMolde(
        passIndice: await _passIndice(),
        nombre: m,
        log: _add,
      );
      if (mounted) setState(() {});
    } catch (e) {
      _add('✗ HF subir: $e');
    } finally {
      if (mounted) setState(() => _hfOcupado = false);
    }
  }

  /// HF: baja la SQL entera si falta y abre el molde.
  /// El .mld nunca se baja: se consulta por rangos.
  Future<void> _hfBajarSql() async {
    if (_hfOcupado) return;
    final m = _infoAbierta?.nombre ?? _hfRepoCtrl.text.trim();
    if (m.isEmpty) {
      _add('· HF: abrí un molde o poné su nombre en repo');
      return;
    }
    setState(() => _hfOcupado = true);
    try {
      final ruta = await _puenteHf.bajarSql(
        passIndice: await _passIndice(),
        nombre: _infoAbierta?.nombre ?? m,
      );
      _add('✓ SQL en $ruta');
      if (_infoAbierta == null && mounted) {
        await _abrirMolde(m);
      }
    } catch (e) {
      _add('✗ HF bajar SQL: $e');
    } finally {
      if (mounted) setState(() => _hfOcupado = false);
    }
  }

  /// Índice: "esta SQL, ¿tiene algún molde?" La SQL dice qué
  /// moldes trae y dónde está cada .mld; el índice los registra.
  Future<void> _hfEscanearSql() async {
    final ruta = _hfSqlCtrl.text.trim();
    if (ruta.isEmpty) {
      _add('· poné la ruta de la .db a escanear');
      return;
    }
    try {
      final nombres = await Indice.escanearSql(
        pass: await _passIndice(),
        sqlPath: ruta,
        claveSql: _clave,
      );
      if (nombres.isEmpty) {
        _add('· sin moldes en "$ruta"');
      } else {
        _add('✓ ${nombres.length} molde(s) desde "$ruta": '
            '${nombres.join(', ')}');
        await _refrescarMoldes();
      }
      if (mounted) setState(() {});
    } catch (e) {
      _add('✗ escanear SQL: $e');
    }
  }

  /// Moldes: clave + recordar + historial + bitácora.
  Widget _tabMoldes() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        campoTexto(_indiceCtrl, 'clave del ÍNDICE (propia)',
            oculto: true),
        const SizedBox(height: 6),
        campoTexto(_claveCtrl, 'clave ÚNICA (tu SQL + molde)',
            oculto: true),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Recordar clave (cifrada, app local)',
              style: TextStyle(fontSize: 12)),
          value: _recordar,
          onChanged: (v) =>
              setState(() => _recordar = v ?? true),
        ),
        FilledButton.tonalIcon(
          onPressed: _indexarCarpeta,
          icon: const Icon(Icons.folder_open_rounded, size: 18),
          label: const Text('Indexar carpeta…'),
        ),
        const SizedBox(height: 6),
        ListaMoldes(
          moldes: _moldes,
          abierta: _infoAbierta?.nombre,
          cargando: _cargando,
          onRecargar: _refrescarMoldes,
          onAbrir: _abrirMolde,
          onBorrar: _borrarMolde,
        ),
        const Divider(height: 20),
        const Text('HuggingFace (repo + token del molde abierto)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        campoTexto(_hfRepoCtrl, 'repo dir/user (ej. miuser/mis-moldes)'),
        const SizedBox(height: 6),
        campoTexto(_hfTokenCtrl, 'token HF (write para subir)',
            oculto: true),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: _hfOcupado ? null : _hfGuardar,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Guardar HF'),
          ),
          FilledButton.tonalIcon(
            onPressed: _hfOcupado ? null : _hfSubir,
            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
            label: const Text('Subir molde+SQL+índice'),
          ),
          FilledButton.tonalIcon(
            onPressed: _hfOcupado ? null : _hfBajarSql,
            icon: const Icon(Icons.cloud_download_rounded, size: 18),
            label: const Text('Bajar SQL'),
          ),
        ]),
        const SizedBox(height: 6),
        campoTexto(_hfSqlCtrl, 'ruta .db suelta para escanear'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: _hfEscanearSql,
            icon: const Icon(Icons.find_in_page_rounded, size: 18),
            label: const Text('Escanear SQL'),
          ),
        ]),
        const Divider(height: 20),
        Row(children: [
          const Text('Bitácora',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            tooltip: 'Copiar toda (para pegar el error)',
            onPressed: () async {
              final todo = _log.join('\n');
              if (todo.isEmpty) return;
              await Clipboard.setData(ClipboardData(text: todo));
              _add('· bitácora copiada (${_log.length} líneas)');
            },
          ),
        ]),
        for (final l in _log)
          if (l.startsWith('⚠'))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade900,
                border: Border.all(color: Colors.redAccent, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.yellowAccent, size: 32),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      l,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SelectableText(l,
                style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
