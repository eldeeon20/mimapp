import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../build_info.dart';
import '../services/dht_busca.dart';
import '../services/rqbit.dart';
import '../src/rust/api/dht_busca.dart' as rust;
import 'torrent_screen.dart';

/// DHT Busca: spider de la red Mainline. Atrapa info_hashes de lo que la
/// red busca (pasivo), sondea activo, resuelve metadatos y arma un
/// índice local buscable. De un hallazgo útil se manda directo a rqbit.
class DhtBuscaScreen extends StatefulWidget {
  const DhtBuscaScreen({super.key});

  @override
  State<DhtBuscaScreen> createState() => _DhtBuscaScreenState();
}

class _DhtBuscaScreenState extends State<DhtBuscaScreen> {
  DhtBusca? _motor;
  final _buscaCtrl = TextEditingController();
  final _pruebaCtrl = TextEditingController();
  List<rust.HalladoItem> _resultados = [];
  rust.DhtStats? _stats;
  bool _busy = false;
  String _estado = 'motor sin iniciar';
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final m = await DhtBusca.crear('${dir.path}/dhtbusca');
      setState(() {
        _motor = m;
        _estado = 'listo · tocá INICIAR para unirte a la red';
      });
      _ticker = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    } catch (e) {
      setState(() => _estado = 'ERROR init: $e');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Poll periódico: stats + nuevos hallazgos en vivo.
  Future<void> _tick() async {
    final m = _motor;
    if (m == null || _busy) return;
    try {
      final st = await m.stats();
      final nuevos = await m.pollNuevos();
      await m.guardar();
      setState(() {
        _stats = st;
        if (nuevos.isNotEmpty) {
          _resultados = [...nuevos, ..._resultados].take(200).toList();
        }
      });
    } catch (_) {}
  }

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

  Future<void> _iniciar() => _guard(() async {
        setState(() => _estado = 'conectando a bootstrap…');
        await _motor!.start();
        setState(() =>
            _estado = 'spider corriendo · atrapando hashes de la red');
      });

  Future<void> _parar() => _guard(() async {
        await _motor!.stop();
        setState(() => _estado = 'detenido · índice guardado');
      });

  Future<void> _probar() => _guard(() async {
        await _motor!.probar(_pruebaCtrl.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('inyectado: mirá CAPTURADOS/resueltos en unos segundos',
                  style: const TextStyle(color: Colors.greenAccent)),
              backgroundColor: Colors.black));
        }
      });

  Future<void> _buscar() => _guard(() async {
        final r = await _motor!.buscar(_buscaCtrl.text);
        setState(() => _resultados = r);
        if (r.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'sin resultados para "${_buscaCtrl.text}" (el índice crece con el tiempo)'),
              backgroundColor: Colors.black));
        }
      });

  void _copiarMagnet(rust.HalladoItem h) {
    final magnet = _motor!.magnet(h);
    Clipboard.setData(ClipboardData(text: magnet));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('magnet copiado · pegalo en Torrents',
            style: const TextStyle(color: Colors.greenAccent)),
        backgroundColor: Colors.black));
  }

  /// Mandar DIRECTO a rqbit: usa la API torrent existente.
  Future<void> _aRqbit(rust.HalladoItem h) => _guard(() async {
        final magnet = _motor!.magnet(h);
        await RqbitBridge.addUrl(magnet);
        if (mounted) {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TorrentScreen()));
        }
      });

  String _tamano(int n) {
    if (n < 1024) return '${n}B';
    if (n < 1048576) return '${(n / 1024).toStringAsFixed(1)}K';
    if (n < 1073741824) return '${(n / 1048576).toStringAsFixed(1)}M';
    return '${(n / 1073741824).toStringAsFixed(2)}G';
  }

  String _semillasTexto() {
    final st = _stats;
    if (st == null) return 'semillas: probando…';
    if (st.semillasTotal == 0) return 'semillas: probando…';
    if (st.semillasOk == 0) {
      return 'SORDO: 0/${st.semillasTotal} semillas responden → '
          'tu red bloquea UDP o DNS';
    }
    return 'semillas: ${st.semillasOk}/${st.semillasTotal} responden ✓ · '
        'paquetes vistos: ${st.pedidos}';
  }

  @override
  Widget build(BuildContext context) {
    final corriendo = _estado.contains('corriendo');
    return Scaffold(
      body: ListView(padding: const EdgeInsets.all(12), children: [
        // ---- estado + control del spider
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: (corriendo ? Colors.greenAccent : Colors.grey)
                  .withValues(alpha: .08),
              borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('estado: $_estado', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            if (_stats != null)
              Text(
                  'CAPTURADOS ${_stats!.capturados} · índice ${_stats!.totalIndice} · resueltos ${_stats!.resueltos} · pendientes ${_stats!.pendientes}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.amberAccent)),
            if (_stats != null)
              Text(
                'tabla Kademlia: ${_stats!.nodosTabla} nodos',
                style: const TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: Colors.blueAccent)),
            if (_stats != null)
              Text(
                _semillasTexto(),
                style: TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: _stats!.pedidos == 0
                        ? Colors.redAccent
                        : Colors.greenAccent),
              ),
            Text('build $kSha',
                style: const TextStyle(fontSize: 8, color: Colors.white24)),

            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(
                  onPressed: _busy || corriendo ? null : _iniciar,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Iniciar')),
              OutlinedButton.icon(
                  onPressed: !corriendo ? null : _parar,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Detener')),
            ]),
            const SizedBox(height: 2),
            const Text('modo nodo servidor · ayudás a rutear la red',
                style: TextStyle(fontSize: 10, color: Colors.white38)),
          ]),
        ),
        const SizedBox(height: 10),
        // ---- búsqueda por texto sobre el índice local
        Row(children: [
          Expanded(
              child: TextField(
            controller: _buscaCtrl,
            decoration: const InputDecoration(
                labelText: 'buscar en el índice local',
                hintText: 'linux iso…'),
            onSubmitted: (_) => _buscar(),
          )),
          IconButton(onPressed: _buscar, icon: const Icon(Icons.search_rounded)),
        ]),
        const SizedBox(height: 8),
        // ---- resultados
        if (_resultados.isEmpty)
          Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                  _buscaCtrl.text.isEmpty
                      ? 'El spider atrapa lo que la red busca.\n'
                          'Con el tiempo el índice local crece solo.\n'
                          '(Kademlia no busca por nombre:\n'
                          'se olfatea y se indexa acá.)'
                      : 'sin resultados aún',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)))
        else
          ..._resultados.map((h) => ListTile(
                dense: true,
                title: Text(h.nombre,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${_tamano(h.tamano.toInt())} · ${h.archivos} arch · ${h.infoHash.substring(0, 16)}…',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'copiar magnet',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () => _copiarMagnet(h)),
                  IconButton(
                      tooltip: 'bajar con rqbit',
                      icon: const Icon(Icons.download_rounded, size: 18),
                      onPressed: _busy ? null : () => _aRqbit(h)),
                ]),
              )),
      ]),
    );
  }
}

