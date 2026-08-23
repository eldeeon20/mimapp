import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/hf.dart';

/// Ejemplo de cliente HuggingFace (mejorado del example_hf.gd de Gtool):
/// token/init, repos, subir/bajar archivos, descarga por rango y búsqueda.
class HfTestScreen extends StatefulWidget {
  const HfTestScreen({super.key});

  @override
  State<HfTestScreen> createState() => _HfTestScreenState();
}

class _LogLine {
  final String text;
  final bool isError;
  _LogLine(this.text, this.isError);
}

class _HfTestScreenState extends State<HfTestScreen> {
  final _hf = HuggingFace();
  final _tokenCtrl = TextEditingController();
  final _repoCtrl = TextEditingController(text: 'mi-usuario/test-pr-app');
  final _localCtrl = TextEditingController();
  final _pathInRepoCtrl = TextEditingController();
  final _commitCtrl = TextEditingController(text: 'subido desde pr_app');
  final _dlFileCtrl = TextEditingController();
  final _dlDirCtrl = TextEditingController();
  final _rangeFileCtrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  String _rangeRepoCtrl = '';
  int _rangeStart = 0;
  int _rangeEnd = 4096;
  String _repoType = 'model';
  bool _private = true;
  bool _busy = false;
  final _logs = <_LogLine>[];
  List<String> _found = [];

  bool get ready => _hf.ready;

  void _log(String msg, {bool error = false}) {
    setState(() => _logs.add(_LogLine(msg, error)));
  }

  Future<void> _guard(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      _log('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(10),
          children: [
            _section('Cliente'),
            TextField(
              controller: _tokenCtrl,
              obscureText: true,
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                labelText: 'Token HF (vacío = anónimo)',
                labelStyle: const TextStyle(fontSize: 10),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(ready ? Icons.check_circle : Icons.login,
                      size: 18,
                      color: ready ? Colors.greenAccent : Colors.white54),
                  onPressed: _busy
                      ? null
                      : () => _guard(() async {
                            await _hf.init(_tokenCtrl.text.trim());
                            _log(ready
                                ? 'Cliente inicializado'
                                : 'Cliente anónimo (solo lectura pública)');
                          }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _section('Repositorio'),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _repoCtrl,
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    labelText: 'repo_id (autor/nombre)',
                    labelStyle: TextStyle(fontSize: 10),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              DropdownButton<String>(
                value: _repoType,
                underline: const SizedBox.shrink(),
                dropdownColor: const Color(0xFF0B1226),
                items: const [
                  DropdownMenuItem(value: 'model', child: Text('model')),
                  DropdownMenuItem(value: 'dataset', child: Text('dataset')),
                  DropdownMenuItem(value: 'space', child: Text('space')),
                ],
                onChanged: (v) => setState(() => _repoType = v ?? 'model'),
              ),
              Switch(
                value: _private,
                onChanged: (v) => setState(() => _private = v),
              ),
            ]),
            Wrap(spacing: 6, children: [
              _action('Crear repo', Icons.create_new_folder_rounded,
                  Colors.greenAccent, _createRepo),
              _action('Borrar repo', Icons.delete_forever_rounded,
                  Colors.redAccent, _deleteRepo),
              _action('¿Existe?', Icons.help_outline_rounded,
                  Colors.orangeAccent, _repoExists),
            ]),
            const SizedBox(height: 12),
            _section('Subir archivo'),
            TextField(
              controller: _localCtrl,
              style: const TextStyle(fontSize: 11),
              decoration:
                  _input('Path local (/sdcard/... o appSupport/...)'),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _pathInRepoCtrl,
              style: const TextStyle(fontSize: 11),
              decoration: _input('path/en/repo.ext'),
            ),
            const SizedBox(height: 6),
            _action('Subir', Icons.upload_rounded, Colors.cyanAccent, _upload),
            const SizedBox(height: 12),
            _section('Descargar'),
            TextField(
              controller: _dlFileCtrl,
              style: const TextStyle(fontSize: 11),
              decoration: _input('archivo.en.repo'),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _dlDirCtrl,
              style: const TextStyle(fontSize: 11),
              decoration: _input('directorio local destino'),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              _action('Descargar', Icons.download_rounded, Colors.lightBlueAccent,
                  _download),
              _action('Borrar archivo', Icons.delete_outline_rounded,
                  Colors.redAccent, _deleteFile),
            ]),
            const SizedBox(height: 12),
            _section('Rango de bytes (sin bajar todo)'),
            Row(children: [
              Flexible(
                child: TextField(
                  controller: _rangeFileCtrl,
                  style: const TextStyle(fontSize: 11),
                  decoration: _input('checkpoint.pt'),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 70,
                child: TextField(
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 11),
                  decoration: _input('start'),
                  onChanged: (v) =>
                      _rangeStart = int.tryParse(v.trim()) ?? 0,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 80,
                child: TextField(
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 11),
                  decoration:
                      _input(_rangeEnd.toString()),
                  onChanged: (v) =>
                      _rangeEnd = int.tryParse(v.trim()) ?? 4096,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            _action('Bajar rango', Icons.data_object_rounded,
                Colors.purpleAccent, _downloadRange),
            const SizedBox(height: 12),
            _section('Buscar modelos por autor'),
            TextField(
              controller: _authorCtrl,
              style: const TextStyle(fontSize: 11),
              decoration: _input('autor (ej. ScortexIA)'),
            ),
            const SizedBox(height: 6),
            _action('Buscar', Icons.search_rounded, Colors.amberAccent, _search),
            for (final f in _found)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text('· $f',
                    style: const TextStyle(fontSize: 10, color: Colors.white60)),
              ),
            const SizedBox(height: 12),
            _section('Log'),
          ],
        ),
      ),
      Container(
        height: 120,
        width: double.infinity,
        color: Colors.black.withValues(alpha: .4),
        padding: const EdgeInsets.all(8),
        child: _logs.isEmpty
            ? const Text('sin actividad',
                style: TextStyle(fontSize: 10, color: Colors.white24))
            : ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (_, i) {
                  final l = _logs[i];
                  return Text(l.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          color: l.isError
                              ? Colors.redAccent
                              : Colors.greenAccent));
                },
              ),
      ),
    ]);
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: Colors.white.withValues(alpha: .35))),
      );

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 10),
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget _action(
      String label, IconData icon, Color color, Future<void> Function() fn) {
    return ActionChip(
      avatar: _busy
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: .08),
      side: BorderSide(color: color.withValues(alpha: .5)),
      onPressed: _busy ? null : () => _guard(fn),
    );
  }

  // ---------------- acciones ----------------

  Future<void> _requireReady() async {
    if (!ready) throw StateError('Inicializá el cliente primero');
  }

  Future<void> _createRepo() async {
    await _requireReady();
    await _hf.createRepository(
        repoId: _repoCtrl.text.trim(), repoType: _repoType, private: _private);
    _log('Repo creado: ${_repoCtrl.text.trim()} ($_repoType, privado=$_private)');
  }

  Future<void> _deleteRepo() async {
    await _requireReady();
    await _hf.deleteRepository(repoId: _repoCtrl.text.trim(), repoType: _repoType);
    _log('Repo borrado: ${_repoCtrl.text.trim()}');
  }

  Future<void> _repoExists() async {
    await _requireReady();
    final exists =
        await _hf.repoExists(repoId: _repoCtrl.text.trim(), repoType: _repoType);
    _log('${_repoCtrl.text.trim()} existe? $exists');
  }

  Future<void> _upload() async {
    await _requireReady();
    await _hf.uploadFile(
      repoId: _repoCtrl.text.trim(),
      localFilePath: _localCtrl.text.trim(),
      pathInRepo: _pathInRepoCtrl.text.trim(),
      commitMessage: _commitCtrl.text.trim(),
      repoType: _repoType,
    );
    _log('Subido ${_pathInRepoCtrl.text.trim()} a ${_repoCtrl.text.trim()}');
  }

  Future<void> _deleteFile() async {
    await _requireReady();
    await _hf.deleteFile(
      repoId: _repoCtrl.text.trim(),
      pathInRepo: _pathInRepoCtrl.text.trim(),
      repoType: _repoType,
    );
    _log('Archivo borrado del repo');
  }

  Future<void> _download() async {
    await _requireReady();
    final path = await _hf.downloadFile(
      repoId: _repoCtrl.text.trim(),
      filename: _dlFileCtrl.text.trim(),
      localDir: _dlDirCtrl.text.trim(),
      repoType: _repoType,
    );
    _log('Descargado a: $path');
  }

  Future<void> _downloadRange() async {
    final bytes = await HuggingFace.downloadFileRange(
      repoId: (_rangeRepoCtrl.isNotEmpty
          ? _rangeRepoCtrl
          : _repoCtrl.text.trim()),
      filename: _rangeFileCtrl.text.trim(),
      start: _rangeStart,
      end: _rangeEnd,
      token: _tokenCtrl.text.trim(),
      repoType: _repoType,
    );
    _log('Rango bajado: ${bytes.length} bytes');
    _showBytesDialog(Uint8List.fromList(bytes));
  }

  Future<void> _search() async {
    await _requireReady();
    final models = await _hf.searchModels(author: _authorCtrl.text.trim(), limit: 10);
    setState(() => _found = models);
    _log('${models.length} modelos encontrados');
  }

  void _showBytesDialog(Uint8List bytes) {
    final printable =
        bytes.take(200).every((b) => b == 9 || b == 10 || b == 13 || (b >= 32 && b < 127));
    final preview = printable
        ? utf8.decode(bytes.take(500).toList(), allowMalformed: true)
        : bytes
            .take(48)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Preview del rango'),
        content: SingleChildScrollView(child: Text(preview)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }
}
