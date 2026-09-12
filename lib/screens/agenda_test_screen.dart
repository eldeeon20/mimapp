import 'package:flutter/material.dart';

import '../agenda/agenda_store.dart';

/// Test de la Agenda: agregar / listar / buscar / editar / borrar
/// cosas y notas. Todo se guarda CIFRADO (CryptoVault AES-256-GCM v2)
/// en appSupport/agenda.pr.
class AgendaTestScreen extends StatefulWidget {
  const AgendaTestScreen({super.key});

  @override
  State<AgendaTestScreen> createState() => _AgendaTestScreenState();
}

class _AgendaTestScreenState extends State<AgendaTestScreen> {
  final _tituloCtrl = TextEditingController();
  final _cuerpoCtrl = TextEditingController();
  final _buscarCtrl = TextEditingController();
  final _log = <String>[];

  String? _editandoId;
  String _query = '';
  bool _cargando = true;

  AgendaStore get _store => AgendaStore.instance;

  @override
  void initState() {
    super.initState();
    _buscarCtrl.addListener(() {
      if (mounted) setState(() => _query = _buscarCtrl.text);
    });
    _store.addListener(_alCambiar);
    _init();
  }

  Future<void> _init() async {
    await _store.ensureLoaded();
    if (!mounted) return;
    setState(() => _cargando = false);
    final ruta = await _store.ruta();
    _add('✓ agenda cargada · ${_store.items.length} items · $ruta');
  }

  void _alCambiar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _store.removeListener(_alCambiar);
    _tituloCtrl.dispose();
    _cuerpoCtrl.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  void _add(String s) => setState(() {
        _log.add(s);
        if (_log.length > 60) _log.removeAt(0);
      });

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
      _add('✓ agregada [${it.id}] "$titulo" (cifrada en agenda.pr)');
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
    final lista = _store.buscar(_query);
    return Scaffold(
      appBar: AppBar(
          title: Text(_editandoId == null
              ? 'Agenda · test cifrado'
              : 'Agenda · editando')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
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
                      '(guardados cifrados AES-GCM v2)',
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
            ),
    );
  }
}
