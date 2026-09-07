import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/koni/koni.dart';

/// Test de Koni (koni_archive, Dart puro): abrir ZIP/7Z/RAR y NAVEGAR el
/// índice SIN volcar nada a disco; preview en RAM para textos chicos y
/// extracción a la carpeta que elijas (una entrada o todo).
class KoniTestScreen extends StatefulWidget {
  const KoniTestScreen({super.key});

  @override
  State<KoniTestScreen> createState() => _KoniTestScreenState();
}

class _KoniTestScreenState extends State<KoniTestScreen> {
  final _pwdCtrl = TextEditingController();
  final _buscarCtrl = TextEditingController();
  final _log = <String>[];

  String _ruta = '';
  KoniSesion? _sesion;
  String _query = '';
  bool _busy = false;
  bool _verPwd = false;

  @override
  void initState() {
    super.initState();
    _buscarCtrl.addListener(() {
      if (mounted) setState(() => _query = _buscarCtrl.text);
    });
  }

  @override
  void dispose() {
    _pwdCtrl.dispose();
    _buscarCtrl.dispose();
    _sesion?.cerrar();
    super.dispose();
  }

  void _add(String s) => setState(() {
        _log.add(s);
        if (_log.length > 60) _log.removeAt(0);
      });

  static String _humano(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// Carpeta destino por defecto si el usuario no elige: <docs>/koni/<base>/
  Future<String> _destinoDefault() async {
    final docs = await getApplicationDocumentsDirectory();
    final f = _ruta.split('/').last;
    final punto = f.indexOf('.');
    final base = punto > 0 ? f.substring(0, punto) : f;
    return '${docs.path}/koni/${base.isEmpty ? 'sin_nombre' : base}';
  }

  /// El usuario elige DÓNDE descomprimir (null = canceló).
  Future<String?> _elegirDonde() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null && dir.isNotEmpty) return dir;
    return _destinoDefault();
  }

  Future<void> _elegirArchivo() async {
    if (_busy) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: Koni.extensiones,
    );
    final files = res?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final ruta = files.first.path;
    if (ruta == null || ruta.isEmpty) return;
    await _abrir(ruta);
  }

  /// Abre el archive: SOLO índice (metadata), nada se vuelca a disco.
  Future<void> _abrir(String ruta) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _sesion?.cerrar();
      final sesion =
          await Koni.abrir(ruta, password: _pwdCtrl.text);
      if (!mounted) {
        await sesion.cerrar();
        return;
      }
      setState(() {
        _ruta = ruta;
        _sesion = sesion;
      });
      final n = sesion.items.length;
      _add('✓ abierto [${sesion.formatoId}] ${sesion.formatoDetectado} · '
          '$n entradas (solo índice, sin volcar a disco)');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ruta = ruta;
        _sesion = null;
      });
      _add('✗ abrir: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ¿Pinta como texto plano? → tap = preview en RAM (sin disco).
  bool _esTexto(KoniItem e) {
    if (e.esDir || e.tamano > 2 * 1024 * 1024) return false;
    const exts = [
      'txt', 'md', 'json', 'csv', 'log', 'ini', 'cfg', 'conf', 'xml',
      'html', 'htm', 'js', 'ts', 'py', 'sh', 'bat', 'yml', 'yaml',
      'srt', 'nfo', 'toml', 'url',
    ];
    final n = e.nombre.toLowerCase();
    return exts.any(n.endsWith);
  }

  /// Lee la entrada DIRECTO a memoria: nada toca el disco.
  Future<void> _preview(KoniItem e) async {
    final s = _sesion;
    if (s == null || _busy || e.esDir) return;
    setState(() => _busy = true);
    try {
      final data = await s.leerBytes(e.ruta, max: 256 * 1024);
      final texto = utf8.decode(data, allowMalformed: true);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(e.ruta,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(texto,
                  style:
                      const TextStyle(fontSize: 11, fontFamily: 'monospace')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      _add('✓ preview en RAM: ${e.ruta} (${data.length} B, sin disco)');
    } catch (err) {
      _add('✗ ${e.ruta}: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extraerUna(KoniItem e) async {
    final s = _sesion;
    if (s == null || _busy || e.esDir) return;
    final dir = await _elegirDonde();
    if (dir == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final destino = '$dir/${e.ruta}';
      final bytes = await s.extraerEntrada(e.ruta, destino);
      _add('✓ ${e.ruta} (${_humano(bytes)}) → $destino');
    } catch (err) {
      _add('✗ ${e.ruta}: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extraerTodo() async {
    final s = _sesion;
    if (s == null || _busy) return;
    final dir = await _elegirDonde();
    if (dir == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await s.extraerTodo(dir);
      _add('✓ ${r.archivos} archivos (${_humano(r.bytes)}) → $dir'
          '${r.omitidos > 0 ? ' · omitidos: ${r.omitidos}' : ''}');
    } catch (err) {
      _add('✗ extraer todo: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cerrar() async {
    await _sesion?.cerrar();
    if (!mounted) return;
    setState(() {
      _sesion = null;
      _ruta = '';
    });
    _add('· sesión cerrada');
  }

  @override
  Widget build(BuildContext context) {
    final s = _sesion;
    final items = s?.buscar(_query) ?? const <KoniItem>[];
    final archivos = items.where((e) => !e.esDir).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _ruta.isEmpty
                      ? 'Elegí un .zip / .7z / .rar…'
                      : _ruta.split('/').last,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontFamily: 'monospace'),
                ),
              ),
              if (s != null)
                Chip(
                  label: Text(s.formatoId,
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                tooltip: 'Elegir archive',
                onPressed: _busy ? null : _elegirArchivo,
                icon: const Icon(Icons.folder_open_rounded),
              ),
              if (s != null)
                IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: _busy ? null : _cerrar,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pwdCtrl,
                  obscureText: !_verPwd,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña (si pide)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) {
                    if (_ruta.isNotEmpty) _abrir(_ruta);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Ver contraseña',
                onPressed: () =>
                    setState(() => _verPwd = !_verPwd),
                icon: Icon(_verPwd
                    ? Icons.visibility_off
                    : Icons.visibility),
              ),
              FilledButton.icon(
                onPressed:
                    (_ruta.isEmpty || _busy) ? null : () => _abrir(_ruta),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reabrir',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        if (s != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _buscarCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'Buscar en ${s.items.length} entradas…',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Text('$archivos archivos',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _busy ? null : _extraerTodo,
                  icon: const Icon(Icons.unarchive_rounded, size: 18),
                  label: const Text('Extraer todo…',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text('Sin coincidencias',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          e.esDir
                              ? Icons.folder_rounded
                              : _esTexto(e)
                                  ? Icons.description_outlined
                                  : Icons.insert_drive_file_outlined,
                          color: e.esDir
                              ? Colors.amberAccent
                              : Colors.grey,
                          size: 22,
                        ),
                        title: Text(e.nombre.isEmpty ? e.ruta : e.nombre,
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: e.esDir
                            ? null
                            : Text(
                                '${_humano(e.tamano)}'
                                '${e.cifrado ? ' · [cifrado]' : ''}'
                                '${e.ruta.contains('/') ? ' · ${e.ruta}' : ''}',
                                style: const TextStyle(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        trailing: e.esDir
                            ? null
                            : IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Extraer acá…',
                                icon: const Icon(
                                    Icons.download_rounded,
                                    size: 20),
                                onPressed: _busy
                                    ? null
                                    : () => _extraerUna(e),
                              ),
                        onTap: e.esDir
                            ? null
                            : () => _esTexto(e)
                                ? _preview(e)
                                : _extraerUna(e),
                      );
                    },
                  ),
          ),
        ],
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Container(
          height: 110,
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[800]!),
          ),
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              _log.isEmpty ? '· log ·' : _log.join('\n'),
              style: const TextStyle(
                  fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }
}
