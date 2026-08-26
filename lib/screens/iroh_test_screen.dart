import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../build_info.dart';
import '../services/iroh_p2p.dart';

/// Ejemplo de transferencia de archivos por iroh-blobs:
///   ENVIAR:  iniciás nodo → ruta del archivo → ticket (copiá y mandalo
///            por donde quieras: Nostrn+, chat, QR…)
///   RECIBIR: pegás el ticket → nombre destino → baja directo P2P.
///
/// El hash BLAKE3 del ticket verifica los bytes al llegar: si cambia un
/// bit, la descarga falla en vez de guardar corrupto.
class IrohTestScreen extends StatefulWidget {
  const IrohTestScreen({super.key});

  @override
  State<IrohTestScreen> createState() => _IrohTestScreenState();
}

class _IrohTestScreenState extends State<IrohTestScreen> {
  final _rutaCtrl = TextEditingController(
      text: '/storage/emulated/0/Download/foto.jpg');
  final _ticketCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController(text: 'recibido.bin');
  String? _miId;
  String? _ticketGenerado;
  String? _resultado;
  bool _busy = false;
  List<String> _registro = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await IrohP2p.crear().then((n) => _nodo = n);
      setState(() {});
    } catch (e) {
      _say('ERROR init: $e');
    }
  }

  IrohP2p? _nodo;

  void _say(String l) => mounted
      ? setState(() => _registro = [l, ..._registro].take(60).toList())
      : null;

  Future<void> _guard(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('ERROR: $e',
                style: const TextStyle(color: Colors.redAccent)),
            backgroundColor: Colors.black));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  // ---- ENVIAR ----------------------------------------------------------
  Future<void> _iniciar() => _guard(() async {
        final id = await _nodo!.startServidor();
        setState(() => _miId = id);
      });

  Future<void> _ofrecer() => _guard(() async {
        if (!_nodo!.corriendo) {
          throw 'primero INICIAR el nodo';
        }
        final t = await _nodo!.ofrecer(_rutaCtrl.text.trim());
        setState(() => _ticketGenerado = t);
      });

  // ---- RECIBIR ---------------------------------------------------------
  Future<void> _bajar() => _guard(() async {
        if (!_nodo!.corriendo) {
          throw 'primero INICIAR el nodo';
        }
        final dir = (await getApplicationSupportDirectory()).path;
        final ruta =
            await _nodo!.bajar(_ticketCtrl.text.trim(), dir, _nombreCtrl.text);
        setState(() => _resultado = ruta);
      });

  void _copiar(String s, [String msg = 'copiado']) {
    Clipboard.setData(ClipboardData(text: s));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(color: Colors.greenAccent)),
        backgroundColor: Colors.black));
  }

  @override
  Widget build(BuildContext context) {
    final on = _nodo?.corriendo ?? false;
    return Scaffold(
      body: ListView(padding: const EdgeInsets.all(12), children: [
        // ---- nodo
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: (on ? Colors.greenAccent : Colors.grey)
                  .withValues(alpha: .08),
              borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(on ? 'nodo arriba · listo para transferir' : 'nodo apagado',
                style: const TextStyle(fontSize: 11.5)),
            if (_miId != null)
              Row(children: [
                Expanded(
                    child: SelectableText('id: $_miId',
                        style: const TextStyle(
                            fontSize: 9.5, fontFamily: 'monospace'))),
                IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: () => _copiar(_miId!, 'endpoint id copiado')),
              ]),
            const SizedBox(height: 6),
            FilledButton.icon(
                onPressed: _busy || on ? null : _iniciar,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Iniciar nodo')),
            Text('build $kSha',
                style: const TextStyle(fontSize: 8, color: Colors.white24)),
          ]),
        ),
        const SizedBox(height: 10),
        // ---- ENVIAR
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ENVIAR archivo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _rutaCtrl,
                decoration: const InputDecoration(
                    labelText: 'ruta del archivo',
                    hintText: '/storage/emulated/0/Download/foto.jpg'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                  onPressed: _busy ? null : _ofrecer,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Generar ticket')),
              if (_ticketGenerado != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(6)),
                  child: SelectableText(_ticketGenerado!,
                      style: const TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          color: Colors.lightGreenAccent)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                      onPressed: () =>
                          _copiar(_ticketGenerado!, 'ticket del ARCHIVO copiado'),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('copiar ticket del archivo')),
                ),
              ],
            ]),
          ),
        ),
        // ---- RECIBIR
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('RECIBIR archivo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _ticketCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'ticket recibido',
                    hintText: 'pega acá el ticket que te mandaron'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                    labelText: 'nombre del archivo destino',
                    hintText: 'foto.jpg / video.mp4…'),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                  onPressed: _busy ? null : _bajar,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Bajar por P2P')),
              if (_resultado != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText('✓ guardado en\n$_resultado',
                      style: const TextStyle(fontSize: 10.5)),
                ),
            ]),
          ),
        ),
        // ---- registro
        Container(
          height: 140,
          width: double.infinity,
          color: Colors.black.withValues(alpha: .5),
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(top: 10),
          child: ListView.builder(
            itemCount: _registro.length,
            itemBuilder: (_, i) => Text(_registro[i],
                style: const TextStyle(
                    fontSize: 9.5,
                    fontFamily: 'monospace',
                    color: Colors.greenAccent)),
          ),
        ),
      ]),
    );
  }
}

