import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/kem.dart';

/// Test de KEM post-cuántico (equivalente del example_kem.gd de Gtool):
/// keyGen(A) -> encapsulate(B) -> decapsulate(A) con timings y tamaños.
class KemTestScreen extends StatefulWidget {
  const KemTestScreen({super.key});

  @override
  State<KemTestScreen> createState() => _KemTestScreenState();
}

class _KemResult {
  final String algo;
  final bool match;
  final double keygenMs;
  final double encapMs;
  final double decapMs;
  final int skSize;
  final int pkSize;
  final int ctSize;
  final String ssPreview;

  _KemResult({
    required this.algo,
    required this.match,
    required this.keygenMs,
    required this.encapMs,
    required this.decapMs,
    required this.skSize,
    required this.pkSize,
    required this.ctSize,
    required this.ssPreview,
  });
}

class _KemTestScreenState extends State<KemTestScreen> {
  final _kem = Kem();
  List<String> _algos = [];
  String _algo = '';
  bool _busy = false;
  final _results = <_KemResult>[];

  @override
  void initState() {
    super.initState();
    _loadAlgos();
  }

  Future<void> _loadAlgos() async {
    try {
      final algos = await _kem.listAlgorithms();
      if (!mounted) return;
      setState(() {
        _algos = algos;
        if (algos.isNotEmpty) {
          _algo = algos.firstWhere((a) => a == 'XWingKemDraft06',
              orElse: () => algos.first);
        }
      });
    } catch (_) {}
  }

  Future<void> _runTest(String algo) async {
    setState(() => _busy = true);
    try {
      final sw = Stopwatch()..start();

      final kpA = await _kem.keyGen(algo);
      final keygenMs = sw.elapsedMicroseconds / 1000;

      sw.reset();
      final enc =
          await _kem.encapsulate(algorithm: algo, publicKey: kpA.publicKey);
      final encapMs = sw.elapsedMicroseconds / 1000;

      sw.reset();
      final ssB = await _kem.decapsulate(
          algorithm: algo,
          ciphertext: enc.ciphertext,
          privateKey: kpA.privateKey);
      final decapMs = sw.elapsedMicroseconds / 1000;

      final match = _bytesEqual(Uint8List.fromList(enc.sharedSecret), ssB);

      if (!mounted) return;
      setState(() {
        _results.insert(
            0,
            _KemResult(
              algo: algo,
              match: match,
              keygenMs: keygenMs,
              encapMs: encapMs,
              decapMs: decapMs,
              skSize: kpA.privateKey.length,
              pkSize: kpA.publicKey.length,
              ctSize: enc.ciphertext.length,
              ssPreview: _hexPreview(enc.sharedSecret),
            ));
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAll() async {
    for (final a in _algos) {
      await _runTest(a);
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _hexPreview(List<int> bytes) {
    final hex = bytes
        .take(24)
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$hex…';
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _algo.isEmpty ? null : _algo,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Algoritmo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final a in _algos)
                  DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 12)))
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _algo = v ?? _algo),
            ),
          ),
          IconButton(
            onPressed: _busy || _algo.isEmpty ? null : () => _runTest(_algo),
            icon: Icon(Icons.play_arrow_rounded,
                size: 26, color: Colors.greenAccent),
            tooltip: 'Roundtrip',
          ),
          IconButton(
            onPressed: _busy ? null : _runAll,
            icon: const Icon(Icons.playlist_play_rounded,
                size: 26, color: Colors.orangeAccent),
            tooltip: 'Probar todos',
          ),
        ]),
      ),
      Expanded(
        child: _results.isEmpty
            ? Center(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.enhanced_encryption_rounded,
                          size: 48, color: Colors.white12),
                      SizedBox(height: 8),
                      Text('Elegí un algoritmo y tocá play',
                          style: TextStyle(color: Colors.grey)),
                    ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: _results.length,
                itemBuilder: (_, i) => _resultCard(_results[i]),
              ),
      ),
    ]);
  }

  Widget _resultCard(_KemResult r) {
    final color = r.match ? Colors.greenAccent : Colors.redAccent;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF0B1226),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: .4))),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(r.match ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: color, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(r.algo,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
          ]),
          const SizedBox(height: 4),
          Text(
            'keygen ${r.keygenMs.toStringAsFixed(2)}ms · '
            'encaps ${r.encapMs.toStringAsFixed(2)}ms · '
            'decaps ${r.decapMs.toStringAsFixed(2)}ms',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
          ),
          Text('SK:${r.skSize}B · PK:${r.pkSize}B · CT:${r.ctSize}B',
              style:
                  const TextStyle(fontSize: 10, fontFamily: 'monospace')),
          Text('SS: ${r.ssPreview}',
              style: const TextStyle(
                  fontSize: 9, fontFamily: 'monospace', color: Colors.white38)),
        ]),
      ),
    );
  }
}
