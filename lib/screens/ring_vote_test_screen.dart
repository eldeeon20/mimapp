import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/nostringer.dart';

/// Port de Gtool `test_nostringer_group.gd`: voto anónimo con BLSAG.
///
/// N votantes generan claves; cada voto se firma dentro del ring de todos,
/// así el conteo sabe que votó ALGUIEN del grupo, no quién. La key image
/// hace imposible votar dos veces con la misma identidad: si dos firmas
/// comparten key image, la segunda se rechaza.
class RingVoteTestScreen extends StatefulWidget {
  const RingVoteTestScreen({super.key});

  @override
  State<RingVoteTestScreen> createState() => _RingVoteTestScreenState();
}

class _RingVoteTestScreenState extends State<RingVoteTestScreen> {
  final _nostringer = Nostringer();
  final _log = <String>[];

  final _keys = <RingKeypair>[];
  final _usedKeyImages = <String>[]; // una por voto aceptado
  int _votantes = 5;
  int _aceptados = 0;
  int _rechazados = 0;
  bool _busy = false;

  Uint8List _msg(String texto) => Uint8List.fromList(texto.codeUnits);

  void _add(String s) => setState(() {
        _log.add(s);
        if (_log.length > 80) _log.removeAt(0);
      });

  Future<void> _crearGrupo() async {
    setState(() => _busy = true);
    try {
      final keys = <RingKeypair>[];
      for (var i = 0; i < _votantes; i++) {
        keys.add(await _nostringer.generateKeypair(variant: 'blsag'));
      }
      setState(() {
        _keys
          ..clear()
          ..addAll(keys);
        _usedKeyImages.clear();
        _aceptados = 0;
        _rechazados = 0;
      });
      _add('✓ grupo creado: $_votantes votantes');
    } catch (e) {
      _add('✗ grupo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Firma un voto como [idx] y lo procesa con dedup por key image.
  Future<void> _votar(int idx, String propuesta) async {
    final ring = _keys.map((k) => k.publicKey).toList();
    try {
      final sig = await _nostringer.sign(
        message: _msg('VOTO: $propuesta'),
        privateKey: _keys[idx].privateKey,
        ring: ring,
        variant: 'blsag',
      );

      // Verificación pública normal.
      final ver = await _nostringer.verify(
        signature: sig.signature,
        message: _msg('VOTO: $propuesta'),
        ring: ring,
      );
      if (!ver.valid) {
        _rechazados++;
        _add('✗ voto #${idx + 1}: firma inválida (descartado)');
        return;
      }

      // Anti doble-voto: ¿esta key image ya votó?
      for (final ki in _usedKeyImages) {
        if (await _nostringer.keyImagesMatch(ki, sig.keyImage)) {
          _rechazados++;
          _add('✗ DOBLE VOTO bloqueado · clave #${idx + 1} ya había votado '
              '(misma key image ${sig.keyImage.substring(0, 10)}…)');
          return;
        }
      }

      _usedKeyImages.add(sig.keyImage);
      _aceptados++;
      _add('✓ voto #${idx + 1} contado · ki ${sig.keyImage.substring(0, 10)}… '
          '(identidad oculta en el ring)');
    } catch (e) {
      _add('✗ voto #${idx + 1}: $e');
    }
  }

  Future<void> _todosVotan(String propuesta) async {
    if (_keys.isEmpty || _busy) return;
    setState(() => _busy = true);
    for (var i = 0; i < _keys.length; i++) {
      await _votar(i, propuesta);
    }
    _add('— total: $_aceptados aceptados · $_rechazados rechazados —');
    if (mounted) setState(() => _busy = false);
  }

  /// Igual que el .gd: alguien intenta votar OTRA vez.
  Future<void> _intentoDobleVoto() async {
    if (_keys.isEmpty || _busy) return;
    setState(() => _busy = true);
    _add('… clave #1 intenta votar de nuevo …');
    await _votar(0, 'Sí');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
          backgroundColor: const Color(0xFF17212B),
          title: const Text('Voto anónimo · BLSAG')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Text('Votantes: $_votantes',
                style: const TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: _votantes.toDouble(),
                min: 2,
                max: 10,
                divisions: 8,
                label: '$_votantes',
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _votantes = v.round()),
              ),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _crearGrupo,
              icon: const Icon(Icons.groups_rounded, size: 18),
              label: const Text('Crear grupo'),
            ),
          ]),
          Wrap(spacing: 8, children: [
            FilledButton.icon(
              onPressed: (_keys.isEmpty || _busy)
                  ? null
                  : () => _todosVotan('Sí'),
              icon: const Icon(Icons.how_to_vote_rounded, size: 18),
              label: const Text('Todos votan "Sí"'),
            ),
            OutlinedButton.icon(
              onPressed: (_keys.isEmpty || _busy || _aceptados == 0)
                  ? null
                  : _intentoDobleVoto,
              icon: const Icon(Icons.warning_amber_rounded, size: 18),
              label: const Text('Doble voto'),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _contador('$_aceptados', 'aceptados', Colors.greenAccent),
              _contador('$_rechazados', 'rechazados', Colors.redAccent),
              _contador('${_usedKeyImages.length}', 'key images', Colors.cyanAccent),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(child: _logPanel()),
        ]),
      ),
    );
  }

  Widget _contador(String n, String label, Color c) => Column(children: [
        Text(n,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)),
        Text(label, style: TextStyle(fontSize: 11, color: c.withValues(alpha: .7))),
      ]);

  Widget _logPanel() => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Text('Registro (${_log.length})',
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _log.length,
              itemBuilder: (_, i) => SelectableText(
                '[${i.toString().padLeft(2, '0')}] ${_log[i]}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    color: _log[i].startsWith('✓')
                        ? Colors.greenAccent
                        : _log[i].startsWith('✗')
                            ? Colors.redAccent
                            : Colors.white70),
              ),
            ),
          ),
        ]),
      );
}
