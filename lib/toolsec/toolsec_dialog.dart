import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'toolsec.dart';

/// Diálogo ToolSec: cifra/descifra archivos con XOR por semilla.
/// Muestra preview hexadecimal y la ruta del archivo resultado.
Future<void> showToolSecDialog(BuildContext context) async {
  final seedCtrl = TextEditingController();
  String? filePath;
  String? fileName;
  bool processing = false;
  String? resultMsg;
  String? hexPreview;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) => AlertDialog(
        title: const Text('ToolSec — XOR por semilla'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: seedCtrl,
                decoration: const InputDecoration(
                  labelText: 'Semilla (clave)',
                  hintText: 'Escribí tu semilla...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: processing
                    ? null
                    : () async {
                        final result =
                            await FilePicker.platform.pickFiles();
                        if (result != null &&
                            result.files.single.path != null) {
                          setDlgState(() {
                            filePath = result.files.single.path;
                            fileName = result.files.single.name;
                            hexPreview = null;
                          });
                        }
                      },
                icon: const Icon(Icons.folder_open),
                label: Text(fileName ?? 'Seleccionar archivo'),
              ),
              if (filePath != null) ...[
                const SizedBox(height: 8),
                Text('Archivo: $fileName',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ],
              if (processing) ...[
                const SizedBox(height: 12),
                const CircularProgressIndicator(),
              ],
              if (resultMsg != null) ...[
                const SizedBox(height: 8),
                Text(resultMsg!,
                    style: TextStyle(
                        fontSize: 12,
                        color: resultMsg!.startsWith('Error')
                            ? Colors.red
                            : Colors.green)),
              ],
              if (hexPreview != null) ...[
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Preview (hex):',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(hexPreview!,
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.greenAccent)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton(
            onPressed: (processing ||
                    filePath == null ||
                    seedCtrl.text.isEmpty)
                ? null
                : () async {
                    setDlgState(() {
                      processing = true;
                      resultMsg = null;
                      hexPreview = null;
                    });
                    try {
                      final ts = ToolSec(seedCtrl.text);
                      final outPath =
                          await ts.encodeFileSecure(filePath!);
                      final bytes =
                          await File(outPath).readAsBytes();
                      final preview = bytes
                          .take(50)
                          .map((b) =>
                              b.toRadixString(16).padLeft(2, '0'))
                          .join(' ');
                      setDlgState(() {
                        resultMsg =
                            'Guardado en: ${outPath.split('/').last}';
                        hexPreview = preview;
                      });
                    } catch (e) {
                      setDlgState(
                          () => resultMsg = 'Error: $e');
                    } finally {
                      setDlgState(() => processing = false);
                    }
                  },
            child: const Text('Cifrar / Descifrar'),
          ),
        ],
      ),
    ),
  );
  seedCtrl.dispose();
}
