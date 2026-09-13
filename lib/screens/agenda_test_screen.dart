import 'package:flutter/material.dart';

import '../agenda/agenda_store.dart';

/// Test de la Agenda: pide NOMBRE + PASS, abre el <nombre>.pr cifrado
/// (CryptoVault AES-256-GCM v2) y deja agregar / listar / buscar /
/// editar / borrar. Sin AppBar propia: la da el contenedor (una sola
/// flecha atrás).
class AgendaTestScreen extends StatefulWidget {
  const AgendaTestScreen({super.key});

  @override
  State<AgendaTestScreen> createState() => _AgendaTestScreenState();
}

class _AgendaTestScreenState extends State<AgendaTestScreen> {
  final _nombreCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _tituloCtrl = TextEditingController();
  final _cuerpoCtrl = TextEditingController();
  final _buscarCtrl = TextEditingController();
  final _log = <String>[];

  String? _editandoId;
  String _query = '';
  bool _abriendo = false;

  AgendaStore get _store => AgendaStore.instance;

  @override
  void initState() {
    super.initState();
    _buscarCtrl.addListener(() {
      if (mounted) setState(() => _query = _buscarCtrl.text);
    });
    _store.addListener(_alCambiar);
  }

  void _alCambiar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_alCambiar);
    _nombreCtrl.dispose();
    _passCtrl.dispose();
    _tituloCtrl.dispose();
    _cuerpoCtrl.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  void _add(String s) => setState(() {
        _log.add(s);
        if (_log.length > 60) _log.removeAt(0);
      });

  /// Abre la agenda con nombre+pass (crea el .pr si no existe).
  Future<void> _abrir() async {
    final nombre = _nombreCtrl.text.trim();
    final pass = _passCtrl.text;
    if (nombre.isEmpty) {
      _add('✗ poné nombre de agenda');
      return;
    }
    if (pass.isEmpty) {
      _add('✗ poné contraseña');
      return;
    }
    setState(() => _abriendo = true);
    final ok = await _store.abrir(nombre, pass);
    if (!mounted) return;
    setState(() => _abriendo = false);
    if (!ok) {
      _add('✗ no abre: ¿pass mal? (${AgendaStore.sanearNombre(nombre)}.pr existe con otra pass)');
      return;
    }
    final ruta = await _store.ruta();
    _passCtrl.clear(); // no guardar la pass en el campo
    _add('✓ agenda "${_store.nombreActual}" abierta · ${_store.items.length} items · $ruta');
  }

  void _cerrar() {
    _store.cerrar();
    _tituloCtrl.clear();
    _cuerpoCtrl.clear();
    setState(() => _editandoId = null);
    _add('✓ agenda cerrada (pass olvidada, .pr queda en disco)');
  }

  Future<void> _guardar() async {
    final titulo = _tituloCtrl.text.trim();
    if (titulo.isEmpty) {
      _add('✗ título vacío, no se guarda');
      return;
    }
    if (_editandoId == null) {
      final it = await _store.agregar(titulo, _cuerpoCtrl.text);
      if (it == null) {
        _add('✗ agregar: falló el guardado cifrado');
        return;
      }
      _add('✓ agregada [${it.id}] "$titulo" (cifrada en ${_store.nombreActual}.pr)');
    } else {
      final ok = await _store.editar(_editandoId!,
          titulo: titulo, cuerpo: _cuerpoCtrl.text);
      if (!ok) {
        _add('✗ editar: no existe o falló el guardado');
        return;
      }
      _add('✓ editada [$_editandoId] "$titulo"');
    }
    _tituloCtrl.clear();
    _cuerpoCtrl.clear();
    setState(() => _editandoId = null);
  }

  void _aEditar(AgendaItem it) {
    setState(() {
      _editandoId = it.id;
      _tituloCtrl.text = it.titulo;
      _cuerpoCtrl.text = it.cuerpo;
    });
  }

  void _cancelarEdicion() {
    setState(() => _editandoId = null);
    _tituloCtrl.clear();
    _cuerpoCtrl.clear();
  }

  Future<void> _borrar(AgendaItem it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar'),
        content: Text('¿Borrar "${it.titulo}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí')),
        ],
      ),
    );
    if (ok != true) return;
    if (_editandoId == it.id) _cancelarEdicion();
    final borrado = await _store.borrar(it.id);
    _add(borrado ? '✓ borrada [${it.id}]' : '✗ borrar: falló el guardado');
  }

  static String _fechaHumana(int ms) {
    if (ms <= 0) return 'sin fecha';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final dos = (int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} '
        '${dos(d.hour)}:${dos(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    // Sin AppBar propia (la da el contenedor con una sola flecha).
    // Cerrada = formulario nombre+pass; abierta = lista.
    return Scaffold(
      body: !_store.abierta ? _candado() : _lista(),
    );
  }

  /// Formulario de apertura: nombre de agenda + contraseña.
  Widget _candado() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.lock_rounded, size: 48, color: Colors.amberAccent),
        const SizedBox(height: 12),
        const Text(
          'Agenda cifrada: poné nombre y contraseña.\n'
          'Cada nombre guarda su propio <nombre>.pr.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nombreCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre de la agenda',
            hintText: 'personal…',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _abrir(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _abrir(),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _abriendo ? null : _abrir,
          icon: _abriendo
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock_open_rounded),
          label: const Text('Abrir / crear (cifrado)'),
        ),
        const SizedBox(height: 12),
        ..._log.reversed.map((l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(l, style: Theme.of(context).textTheme.bodySmall),
            )),
      ],
    );
  }

  Widget _lista() {
    final lista = _store.buscar(_query);
    return Column(
      children: [
        // Encabezado: nombre de la agenda abierta + candado para cerrar.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              const Icon(Icons.lock_open_rounded,
                  size: 16, color: Colors.greenAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Agenda "${_store.nombreActual}"',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              TextButton.icon(
                onPressed: _cerrar,
                icon: const Icon(Icons.lock_rounded, size: 16),
                label: const Text('Cerrar'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
                      TextField(
                        controller: _tituloCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Título de la cosa/nota',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cuerpoCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Nota / detalle',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _guardar,
                              icon: Icon(_editandoId == null
                                  ? Icons.add_rounded
                                  : Icons.save_rounded),
                              label: Text(_editandoId == null
                                  ? 'Agregar (cifrado)'
                                  : 'Guardar cambios'),
                            ),
                          ),
                          if (_editandoId != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                                onPressed: _cancelarEdicion,
                                child: const Text('Cancelar')),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _buscarCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Buscar en lista',
                          prefixIcon: Icon(Icons.search_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Lista: ${lista.length} items '
                      '("${_store.nombreActual}.pr" cifrado AES-GCM v2)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: lista.isEmpty
                      ? const Center(child: Text('Vacía: agregá la primera'))
                      : ListView.builder(
                          itemCount: lista.length,
                          itemBuilder: (_, i) {
                            final it = lista[i];
                            final editando = it.id == _editandoId;
                            return Card(
                              color: editando
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : null,
                              child: ListTile(
                                title: Text(it.titulo),
                                subtitle: Text(
                                  '${it.cuerpo.isEmpty ? '(sin nota)' : it.cuerpo}\n'
                                  'creada: ${_fechaHumana(it.creada)}',
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar',
                                      icon: const Icon(Icons.edit_rounded),
                                      onPressed: () => _aEditar(it),
                                    ),
                                    IconButton(
                                      tooltip: 'Borrar',
                                      icon: const Icon(
                                          Icons.delete_rounded,
                                          color: Colors.redAccent),
                                      onPressed: () => _borrar(it),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                Expanded(
                  flex: 2,
                  child: ListView.builder(
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      child: Text(_log[i],
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),
                ),
              ],
    );
  }
}
