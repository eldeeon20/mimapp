import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../build_info.dart';
import '../services/dht_busca.dart';
import '../services/nat_service.dart';
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
  List<rust.CapturaItem> _capturas = [];
  List<String> _logs = [];
  bool _sondeoAleatorio = true;
  rust.DhtStats? _stats;
  bool _busy = false;
  String _estado = 'motor sin iniciar';
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Usa la instancia SINGLETON en segundo plano: al volver a la pantalla
  /// NO se recrea el motor ni se reinicia el spider (sigue corriendo).
  Future<void> _init() async {
    try {
      final m = await DhtBusca.instancia;
      bool sondeo = true;
      try {
        sondeo = await m.sondeoAleatorio();
      } catch (_) {}
      setState(() {
        _motor = m;
        _sondeoAleatorio = sondeo;
        _estado = DhtBusca.corriendo
            ? 'spider corriendo · atrapando hashes de la red'
            : 'listo · tocá INICIAR para unirte a la red';
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
      final q = _buscaCtrl.text.trim();
      // Drena la cola de novedades en Rust (evita que crezca sin límite).
      await m.pollNuevos();
      await m.guardar();
      // La lista de capturas se filtra en vivo por la búsqueda (hash o nombre).
      final caps = q.isEmpty
          ? await m.capturas(limit: 400)
          : await m.capturasFiltradas(q, limit: 400);
      // RESUELTOS: si hay búsqueda, filtra por nombre; si no, el índice
      // completo (incluidos los metadatos recargados del JSON al abrir).
      final resueltos = q.isEmpty
          ? await m.resueltos(limit: 300)
          : await m.buscar(q);
      // logs en su propio try: si falla, no tumba el resto del tick.
      List<String> logs = _logs;
      try {
        logs = await m.logs();
      } catch (_) {}
      setState(() {
        _stats = st;
        _capturas = caps;
        _logs = logs;
        _resultados = resueltos;
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
        // Abre el puerto 6881 en el router (UPnP/NAT-PMP) antes de arrancar,
        // para que el DHT (que ahora escucha en 6881) reciba tráfico entrante.
        if (NatService.instance.enabled) {
          try {
            final ext = await NatService.instance.openUdp(
              localPort: 6881,
              externalPort: 6881,
              description: 'mimapp DHT spider',
            );
            if (ext != null) {
              setState(() => _estado = 'puerto UDP 6881 mapeado ($ext) · uniendo a la red…');
            }
          } catch (_) {
            // no fatal: el pasivo puede no funcionar sin reenvío
          }
        }
        await _motor!.start();
        setState(() =>
            _estado = 'spider corriendo · atrapando hashes de la red');
      });

  Future<void> _parar() => _guard(() async {
        await _motor!.stop();
        setState(() => _estado = 'detenido · índice guardado');
      });

  /// Abre el puerto default del spider (UDP 6881) en el router vía UPnP/NAT-PMP.
  Future<void> _abrirPuertos() => _guard(() async {
        if (!NatService.instance.enabled) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Activá "Puertos (UPnP/NAT-PMP)" en Ajustes',
                    style: TextStyle(color: Colors.redAccent)),
                backgroundColor: Colors.black));
          }
          return;
        }
        final ext = await NatService.instance.openUdp(
          localPort: 6881,
          externalPort: 6881,
          description: 'mimapp DHT spider',
        );
        setState(() => _estado = ext != null
            ? 'puerto UDP 6881 mapeado en el router (externo $ext)'
            : 'no se pudo mapear el puerto (sin gateway UPnP/NAT-PMP)');
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
      body: Column(children: [
        // ---- estado + control del spider
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.all(12),
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
                    color: Colors.blueAccent),
              ),
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
            const SizedBox(height: 6),
            Row(children: [
              Switch(
                  value: _sondeoAleatorio,
                  onChanged: _busy
                      ? null
                      : (v) async {
                          setState(() => _sondeoAleatorio = v);
                          try {
                            await _motor!.setSondeoAleatorio(v);
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('ERROR: $e',
                                      style: const TextStyle(
                                          color: Colors.redAccent)),
                                  backgroundColor: Colors.black));
                            }
                          }
                        }),
              const Expanded(
                  child: Text(
                      'Sondeo aleatorio (hashes): genera hashes al azar para '
                      'crecer la tabla. Apagalo para indexar solo torrents reales.',
                      style: TextStyle(fontSize: 10, color: Colors.white54))),
            ]),
            const SizedBox(height: 8),
            FilledButton.icon(
                onPressed: _abrirPuertos,
                icon: const Icon(Icons.router_rounded, size: 18),
                label: const Text('Abrir puertos (UDP 6881)')),
          ]),
        ),
        // ---- búsqueda (filtra ambas listas en vivo)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
                child: TextField(
              controller: _buscaCtrl,
              decoration: const InputDecoration(
                  labelText: 'buscar (hash o nombre, parcial)',
                  hintText: 'ubuntu…'),
              onChanged: (_) => _tick(),
              onSubmitted: (_) => _tick(),
            )),
            IconButton(onPressed: _tick, icon: const Icon(Icons.search_rounded)),
          ]),
        ),
        const SizedBox(height: 8),
        // ---- dos listas: capturas (hashes) + resueltos (metadatos)
        Expanded(
          child: ListView(children: [
            _seccion('CAPTURADOS (hashes) · ${_capturas.length}'),
            if (_capturas.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'El spider atrapa lo que la red busca. Aparece acá en vivo.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)))
            else
              ..._capturas.map(_capturaTile),
            const Divider(height: 18),
            _seccion('RESUELTOS (metadatos) · ${_resultados.length}'),
            if (_resultados.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                      'Lo resuelto (nombre/tamaño) aparece acá. Con el tiempo crece.',
                      style: TextStyle(color: Colors.white38, fontSize: 12)))
            else
              ..._resultados.map((h) => ListTile(
                    dense: true,
                    title: Text(h.nombre,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${_tamano(h.tamano.toInt())} · ${h.archivos} arch'
                        '${h.creationDate.isNotEmpty ? " · ${h.creationDate}" : ""}'
                        '${h.comment.isNotEmpty ? " · ${h.comment}" : ""}',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 10)),
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
            const Divider(height: 18),
            _seccion('LOG (rqbit / red) · ${_logs.length}'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _logs.reversed
                    .take(25)
                    .map((l) => Text(l,
                        style: const TextStyle(
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            color: Colors.white54)))
                    .toList(),
              ),
            ),
          ]),
        ),
        // ---- probar hash manual
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
                child: TextField(
              controller: _pruebaCtrl,
              decoration: const InputDecoration(
                  labelText: 'probar info_hash (40 hex) o magnet',
                  hintText: 'magnet:?xt=urn:btih:…'),
              onSubmitted: (_) => _probar(),
            )),
            IconButton(onPressed: _probar, icon: const Icon(Icons.send_rounded)),
          ]),
        ),
      ]),
    );
  }

  Widget _seccion(String t) => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        color: Colors.white10,
        child: Text(t,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.cyanAccent)),
      );

  Widget _capturaTile(rust.CapturaItem c) => ListTile(
        dense: true,
        leading: Icon(
            c.resuelto ? Icons.check_circle : Icons.hourglass_bottom,
            size: 18,
            color: c.resuelto ? Colors.greenAccent : Colors.orangeAccent),
        title: Text(
            c.resuelto && c.nombre.isNotEmpty ? c.nombre : 'resolviendo…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13)),
        subtitle: Text(c.infoHash,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
        onTap: () {
          Clipboard.setData(ClipboardData(text: c.infoHash));
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('hash copiado',
                  style: TextStyle(color: Colors.greenAccent)),
              backgroundColor: Colors.black));
        },
      );
}

