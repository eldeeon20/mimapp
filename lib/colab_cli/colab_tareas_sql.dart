import 'dart:convert';

import 'package:flutter/material.dart';

import '../modo_sql/db/caja_sql.dart';
import 'colab_task_models.dart';

/// Tareas + pockets en SQL NUEVA solo-tareas (`tareas.db`, ChaCha20 con
/// TU pass). Fuera del `config.pr` (ahí no se guardan más).
///
/// La pass vive SOLO en memoria (sesión): se pide al abrir la pantalla,
/// al guardar explícito y al tocar CDN si todavía no está. Nada
/// automático guarda sin tu pass.
abstract final class ColabTareasSql {
  static String _pass = '';
  static bool get tienePass => _pass.isNotEmpty;

  /// Olvida la pass (candado): lo próximo la vuelve a pedir.
  static void olvidar() => _pass = '';

  /// Solo asegura pass en memoria (pide si falta). true = hay pass.
  /// (Para el toque CDN: pide pass sin traer datos.)
  static Future<bool> asegurar(BuildContext context) async {
    if (!context.mounted) return false;
    return await _asegurarPass(context) != null;
  }

  /// Diálogo de pass. null = canceló.
  static Future<String?> _pedir(
      BuildContext context, String titulo) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Pass de tareas', border: OutlineInputBorder()),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Abrir')),
        ],
      ),
    );
    final v = ctrl.text;
    ctrl.dispose();
    if (ok != true) return null;
    return v;
  }

  static void _tablas(CajaSql caja) {
    caja.crearTabla('tareas', {
      'tid': 'TEXT',
      'nombre': 'TEXT',
      'code': 'TEXT',
      'hasArg': 'INTEGER',
      'lastArg': 'TEXT',
      'ayuda': 'TEXT',
      'campos': 'TEXT',
    });
    caja.crearTabla('pockets', {
      'pid': 'TEXT',
      'taskId': 'TEXT',
      'argumento': 'TEXT',
      'status': 'TEXT',
      'output': 'TEXT',
      'updatedAt': 'INTEGER',
    });
  }

  /// Abre la SQL con [pass] (crea tablas). Lanza si la pass está mal.
  static Future<CajaSql> _abrirCon(String pass) async {
    final caja = CajaSql();
    try {
      await caja.abrir('tareas', clave: pass);
      _tablas(caja);
      return caja;
    } catch (_) {
      caja.cerrar();
      rethrow;
    }
  }

  /// Asegura pass en memoria (pide si falta, reintenta si está mal).
  /// null = canceló (no hay pass).
  static Future<String?> _asegurarPass(BuildContext context) async {
    if (_pass.isNotEmpty) {
      try {
        (await _abrirCon(_pass)).cerrar();
        return _pass;
      } catch (_) {
        _pass = '';
      }
    }
    while (context.mounted) {
      final v = await _pedir(context, 'Pass de tareas');
      if (v == null) return null;
      if (v.isEmpty) continue;
      try {
        (await _abrirCon(v)).cerrar();
        _pass = v;
        return _pass;
      } catch (_) {
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pass mal, probá de nuevo')),
        );
      }
    }
    return null;
  }

  /// Lee todo. null = canceló (sin pass).
  static Future<({List<ColabTask> tasks, List<ColabPocket> pockets})?>
      cargar(BuildContext context) async {
    final p = await _asegurarPass(context);
    if (p == null) return null;
    final caja = await _abrirCon(p);
    try {
      final tasks = <ColabTask>[];
      for (final r in caja.listar('tareas', por: 'id')) {
        List<String> campos = const [];
        try {
          final d = jsonDecode("${r['campos'] ?? '[]'}");
          if (d is List) campos = [for (final c in d) '$c'];
        } catch (_) {}
        tasks.add(ColabTask(
          id: "${r['tid'] ?? ''}",
          nombre: "${r['nombre'] ?? ''}",
          code: "${r['code'] ?? ''}",
          hasArg: (r['hasArg'] as num? ?? 0) != 0,
          lastArg: "${r['lastArg'] ?? ''}",
          ayuda: "${r['ayuda'] ?? ''}",
          campos: campos,
        ));
      }
      final pockets = <ColabPocket>[];
      for (final r in caja.listar('pockets', por: 'id')) {
        pockets.add(ColabPocket(
          id: "${r['pid'] ?? ''}",
          taskId: "${r['taskId'] ?? ''}",
          argumento: "${r['argumento'] ?? ''}",
          status: "${r['status'] ?? 'pendiente'}",
          output: "${r['output'] ?? ''}",
          updatedAt: (r['updatedAt'] as num?)?.toInt(),
        ));
      }
      return (tasks: tasks, pockets: pockets);
    } finally {
      caja.cerrar();
    }
  }

  /// Guarda todo (borra + inserta: son pocas filas).
  /// [silencioso]: sin pass en memoria NO pide (fondo) y retorna false.
  /// false = no se guardó (canceló o sin pass en fondo).
  static Future<bool> guardar(
    BuildContext context,
    List<ColabTask> tasks,
    List<ColabPocket> pockets, {
    bool silencioso = false,
  }) async {
    String? p = _pass.isNotEmpty ? _pass : null;
    if (p == null) {
      if (silencioso) return false;
      p = await _asegurarPass(context);
      if (p == null) return false;
    } else {
      try {
        (await _abrirCon(p)).cerrar();
      } catch (_) {
        if (silencioso) return false;
        _pass = '';
        p = await _asegurarPass(context);
        if (p == null) return false;
      }
    }
    final caja = await _abrirCon(p!);
    try {
      caja.db.execute('DELETE FROM "tareas";');
      caja.db.execute('DELETE FROM "pockets";');
      if (tasks.isNotEmpty) {
        caja.agregarLote('tareas', [
          for (final t in tasks)
            {
              'tid': t.id,
              'nombre': t.nombre,
              'code': t.code,
              'hasArg': t.hasArg ? 1 : 0,
              'lastArg': t.lastArg,
              'ayuda': t.ayuda,
              'campos': jsonEncode(t.campos),
            }
        ]);
      }
      if (pockets.isNotEmpty) {
        caja.agregarLote('pockets', [
          for (final q in pockets)
            {
              'pid': q.id,
              'taskId': q.taskId,
              'argumento': q.argumento,
              'status': q.status,
              'output': q.output,
              'updatedAt': q.updatedAt,
            }
        ]);
      }
      return true;
    } finally {
      caja.cerrar();
    }
  }
}
