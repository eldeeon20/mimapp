import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';

/// Resultado que le devuelve al chat: archivo + tipo (+ duración si video).
class CapturedMedia {
  final String filePath;
  final MediaType tipo;
  final Duration duracion;
  CapturedMedia({required this.filePath, required this.tipo, this.duracion = Duration.zero});
}

/// Cámara full-screen para el chat: modo Foto/Video, flash y cámara
/// frontal/trasera. Devuelve [CapturedMedia] por Navigator.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

enum _Modo { foto, video }

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _ctrl;
  List<CameraDescription>? _cameras;
  int _idx = 0;
  bool _lista = false;
  String? _error;

  _Modo _modo = _Modo.foto;
  FlashMode _flash = FlashMode.off;
  bool _grabando = false;
  int _segundos = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pedirPermisosYArrancar();
  }

  Future<void> _pedirPermisosYArrancar() async {
    // Micrófono solo hace falta para video; pedirlo siempre simplifica.
    await [
      Permission.camera,
      Permission.microphone,
    ].request();
    if (!await Permission.camera.isGranted) {
      setState(() => _error = 'Permiso de cámara denegado');
      return;
    }
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _error = 'Sin cámaras disponibles');
        return;
      }
      await _abrirCamara(_idx);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _abrirCamara(int i) async {
    final previo = _ctrl;
    _lista = false;
    final cam = _cameras![i];
    final ctrl = CameraController(
      cam,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await ctrl.initialize();
      await ctrl.setFlashMode(_flash);
      previo?.dispose();
      if (!mounted) return;
      setState(() {
        _ctrl = ctrl;
        _idx = i;
        _lista = true;
        _error = null;
      });
    } catch (e) {
      await ctrl.dispose();
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _sacarFoto() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _busy) return;
    try {
      final xfile = await ctrl.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(
          CapturedMedia(filePath: xfile.path, tipo: MediaType.imagen));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Foto: $e')));
    }
  }

  bool get _busy => _ctrl?.value.isTakingPicture ?? false;

  Future<void> _toggleVideo() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    try {
      if (_grabando) {
        final xfile = await ctrl.stopVideoRecording();
        _timer?.cancel();
        if (!mounted) return;
        Navigator.of(context).pop(CapturedMedia(
          filePath: xfile.path,
          tipo: MediaType.video,
          duracion: Duration(seconds: _segundos),
        ));
      } else {
        // camera 0.11: graba a un archivo temporal de la plataforma;
        // la ruta real llega en el XFile de stopVideoRecording().
        await ctrl.startVideoRecording();
        setState(() {
          _grabando = true;
          _segundos = 0;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _segundos++);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Video: $e')));
      }
    }
  }

  Future<void> _ciclarFlash() async {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    FlashMode nuevo;
    switch (_flash) {
      case FlashMode.off:
        nuevo = FlashMode.torch;
      case FlashMode.torch:
        nuevo = FlashMode.auto;
      default:
        nuevo = FlashMode.off;
    }
    await ctrl.setFlashMode(nuevo);
    setState(() => _flash = nuevo);
  }

  IconData get _flashIcono => switch (_flash) {
        FlashMode.off => Icons.flash_off_rounded,
        FlashMode.torch => Icons.flashlight_on_rounded,
        _ => Icons.flash_auto_rounded,
      };

  String get _duracionTxt =>
      '${(_segundos ~/ 60).toString().padLeft(2, '0')}:${(_segundos % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (_error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Volver'),
                ),
              ]),
            ),
          )
        else if (!_lista)
          const Center(child: CircularProgressIndicator())
        else
          CameraPreview(_ctrl!),

        // Barra superior
        SafeArea(
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () async {
                if (_grabando) {
                  try {
                    await _ctrl?.stopVideoRecording();
                  } catch (_) {}
                }
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
            const Spacer(),
            IconButton(
              icon: Icon(_flashIcono, color: Colors.white),
              onPressed: _ciclarFlash,
            ),
          ]),
        ),

        // Controles inferiores
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SegmentedButton<_Modo>(
                  segments: const [
                    ButtonSegment(value: _Modo.foto, label: Text('Foto')),
                    ButtonSegment(value: _Modo.video, label: Text('Video')),
                  ],
                  selected: {_modo},
                  onSelectionChanged: _grabando
                      ? null
                      : (s) => setState(() => _modo = s.first),
                  style: const ButtonStyle(
                    backgroundColor:
                        WidgetStatePropertyAll(Colors.black54),
                  ),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  // Cambiar cámara
                  IconButton.filledTonal(
                    iconSize: 26,
                    onPressed: (_cameras == null || _cameras!.length < 2)
                        ? null
                        : () => _abrirCamara((_idx + 1) % _cameras!.length),
                    icon: const Icon(Icons.cameraswitch_rounded,
                        color: Colors.white),
                  ),
                  // Obturador
                  GestureDetector(
                    onTap:
                        _modo == _Modo.foto ? _sacarFoto : _toggleVideo,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _grabando
                                ? Colors.redAccent
                                : Colors.white,
                            width: 4),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              _grabando ? Colors.redAccent : Colors.white,
                        ),
                        child: _grabando
                            ? Center(
                                child: Text('$_duracionTxt',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)))
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balancea el switch de cámara
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
