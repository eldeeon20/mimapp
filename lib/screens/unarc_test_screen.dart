import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/unarc.dart';

/// Port de Gtool `unarc_godot.rs` como pantalla de prueba: abrís un archive
/// (7z/ZIP/RAR5/tar/arj/lha/zoo, multi-volumen .001/.z01 incluido), listás
/// entradas y extraés todo o de a una. Password opcional para cifrados.
class UnarcTestScreen extends StatefulWidget {
  const UnarcTestScreen({super.key});

  @override
  State<UnarcTestScreen> createState() => _UnarcTestScreenState();
}

class _UnarcTestScreenState extends State<UnarcTestScreen> {
  final _unarc = Unarc();
  final _pwdCtrl = TextEditingController();
  final _log = <String>[];

  String? _path;
  String _formato = '';
  bool _encriptado = false;
  List<UnarcEntry> _entries = const [];
  bool _busy = false;
  bool _verPwd = false;

  void _add(String s) => setState(() {
        _log.add(s);
        if (_log.length > 60) _log.removeAt(0);
      });

  /// Carpeta destino: <docs>/unarc/<nombre archive sin extensión>/
  Future<String> _destino() async {
    final docs = await getApplicationDocumentsDirectory();
    final base =
        (_path == null) ? 'sin_nombre' : _nombreBase(_path!);
    return '${docs.path}/unarc/$base';
  }

  static String _nombreBase(String p) {
    final f = p.split('/').last;
    // x.7z.001 → x ; x.zip → x
    var sinExt = f;
    for (final suf in const ['.tar.gz', '.tar.bz2']) {
      if (sinExt.toLowerCase().endsWith(suf)) {
        sinExt = sinExt.substring(0, sinExt.length - suf.length);
      }
    }
    final punto = sinExt.indexOf('.');
    return punto > 0 ? sinExt.substring(0, punto) : sinExt;
  }

  Future<void> _elegir() async {
    if (_busy) return;
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.singleOrNull?.path;
    if (path == null || path.isEmpty) return;
    setState(() {
      _path = path;
      _entries = const [];
      _formato = '';
      _encriptado = false;
    });
    await _cargar();
  }

  Future<void> _cargar() async {
    final path = _path;
    if (path == null || _busy) return;
    setState(() => _busy = true);
    try {
      final soportado = await _unarc.soportado(path);
      _add(soportado
          ? '✓ extensión soportada'
          : '⚠ extensión no estándar, igual intento abrir');
      final formato = await _unarc.formato(path);
      final pwd = _pwdCtrl.text;
      final entries = await _unarc.listar(path, password: pwd);
      final encriptado =
          entries.any((e) => e.encrypted) && pwd.isEmpty;
      setState(() {
        _formato = formato;
        _encriptado = encriptado;
        _entries = entries;
      });
      _add('✓ ${entries.length} entradas · formato: ${formato.isEmpty ? '?' : formato}'
          '${encriptado ? ' · PIDE PASSWORD' : ''}');
    } catch (e) {
      setState(() => _entries = const []);
      final msg = '$e';
      _add('✗ listar: $msg');
      if (msg.contains('password') ||
          msg.toLowerCase().contains('encrypt') ||
          msg.toLowerCase().contains('crc')) {
        _add('  ↳ probá poner la contraseña y recargar');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extraerTodo() async {
    final path = _path;
    if (path == null || _busy) return;
    setState(() => _busy = true);
    try {
      final dest = await _destino();
      final r = await _unarc.extraerTodo(
        path,
        dest,
        password: _pwdCtrl.text,
      );
      _add('✓ ${r.files} archivos (${_humano(r.bytes)}) → $dest');
    } catch (e) {
      _add('✗ extraer todo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extraerUna(UnarcEntry e) async {
    final path = _path;
    if (path == null || _busy || e.isDir) return;
    setState(() => _busy = true);
    try {
      final destDir = await _destino();
      final nombre = e.name.replaceAll('\\', '/').split('/').last;
      final dest = '$destDir/$nombre';
      final bytes = await _unarc.extraerEntrada(
        path,
        e.name,
        dest,
        password: _pwdCtrl.text,
      );
      _add('✓ ${e.name} (${_humano(bytes)}) → $dest');
    } catch (err) {
      _add('✗ ${e.name}: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _humano(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(n / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _path == null
                      ? 'Elegí un archive…'
                      : _path!.split('/').last,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontFamily: 'monospace'),
                ),
              ),
              if (_formato.isNotEmpty)
                Chip(
                  label: Text(_formato,
                      style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                ),
              IconButton(
                onPressed: _busy ? null : _elegir,
                icon: const Icon(Icons.folder_open_rounded),
                tooltip: 'Abrir archive',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            controller: _pwdCtrl,
            obscureText: !_verPwd,
            decoration: InputDecoration(
              isDense: true,
              hintText: _encriptado
                  ? 'contraseña REQUERIDA'
                  : 'contraseña (opcional)',
              prefixIcon: Icon(
                Icons.lock_rounded,
                size: 18,
                color: _encriptado ? Colors.redAccent : null,
              ),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: Icon(_verPwd
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded),
                  onPressed: () => setState(() => _verPwd = !_verPwd),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Recargar con esta contraseña',
                  onPressed: _busy ? null : _cargar,
                ),
              ]),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  (_busy || _entries.isEmpty) ? null : _extraerTodo,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.unarchive_rounded),
              label: Text(_entries.isEmpty
                  ? 'Sin entradas cargadas'
                  : 'Extraer todo (${_entries.length})'),
            ),
          ),
        ),
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Text(
                    _path == null
                        ? 'Abrí un .zip/.7z/.rar/…\ntambién split .001 o .z01'
                        : (_busy ? 'Leyendo…' : 'Sin entradas'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _entries.length,
                  itemBuilder: (_, i) {
                    final e = _entries[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        e.isDir
                            ? Icons.folder_rounded
                            : (e.encrypted
                                ? Icons.lock_outline_rounded
                                : Icons.description_outlined),
                        color: e.isDir
                            ? Colors.amberAccent
                            : (e.encrypted
                                ? Colors.redAccent
                                : Colors.white54),
                      ),
                      title: Text(e.name,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: e.isDir
                          ? null
                          : Text(_humano(e.size),
                              style: const TextStyle(fontSize: 11)),
                      onTap: e.isDir ? null : () => _extraerUna(e),
                    );
                  },
                ),
        ),
        Container(
          height: 130,
          width: double.infinity,
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF061021),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: ListView.builder(
            itemCount: _log.length,
            itemBuilder: (_, i) => Text(
              _log[i],
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: _log[i].startsWith('✗')
                    ? Colors.redAccent
                    : (_log[i].startsWith('✓')
                        ? Colors.greenAccent
                        : Colors.white60),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }
}

extension _SingleOrNull<T> on List<T> {
  T? get singleOrNull => length == 1 ? first : null;
}
