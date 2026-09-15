import 'package:flutter/material.dart';

/// Barras finas de WebK: estado + botones + filtros (imágenes/cookies).
/// Widget tonto: la pantalla pasa datos y callbacks.
class ControlesWebk extends StatelessWidget {
  final bool corriendo;
  final bool busy;
  final bool indiceListo;
  final String baseUrl;
  final String stats;
  final bool bloqImg;
  final bool bloqCookies3ros;
  final VoidCallback onIniciar;
  final VoidCallback onPaginas;
  final VoidCallback onBuilder;
  final VoidCallback onAutorizarOtra;
  final VoidCallback onDetener;
  final VoidCallback onCambiarImg;
  final VoidCallback onCambiarCookies3ros;
  final VoidCallback onLimpiarCookies;

  const ControlesWebk({
    super.key,
    required this.corriendo,
    required this.busy,
    required this.indiceListo,
    required this.baseUrl,
    required this.stats,
    required this.bloqImg,
    required this.bloqCookies3ros,
    required this.onIniciar,
    required this.onPaginas,
    required this.onBuilder,
    required this.onAutorizarOtra,
    required this.onDetener,
    required this.onCambiarImg,
    required this.onCambiarCookies3ros,
    required this.onLimpiarCookies,
  });

  static const _chico = TextStyle(fontSize: 12);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              Icon(
                corriendo ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: corriendo ? Colors.greenAccent : Colors.grey,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  corriendo ? baseUrl : 'server detenido',
                  style: const TextStyle(
                      fontSize: 10, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(stats,
                  style:
                      const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed: (busy || corriendo) ? null : onIniciar,
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text('Iniciar', style: _chico),
              ),
              FilledButton.icon(
                onPressed:
                    (!corriendo || !indiceListo) ? null : onPaginas,
                icon: const Icon(Icons.menu_rounded, size: 16),
                label: const Text('Páginas', style: _chico),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    (!corriendo || !indiceListo) ? null : onBuilder,
                icon: const Icon(Icons.build_rounded, size: 16),
                label: const Text('Builder', style: _chico),
              ),
              OutlinedButton.icon(
                onPressed: corriendo ? onAutorizarOtra : null,
                icon: const Icon(Icons.key_rounded, size: 16),
                label: const Text('Autorizar otra', style: _chico),
              ),
              OutlinedButton.icon(
                onPressed: corriendo ? onDetener : null,
                icon: const Icon(Icons.stop_rounded, size: 16),
                label: const Text('Detener', style: _chico),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(
                onPressed: !corriendo ? null : onCambiarImg,
                icon: Icon(
                    bloqImg
                        ? Icons.image_not_supported_rounded
                        : Icons.image_rounded,
                    size: 16),
                label: Text(bloqImg ? 'Img: no' : 'Img: sí',
                    style: _chico),
              ),
              FilledButton.tonalIcon(
                onPressed: !corriendo ? null : onCambiarCookies3ros,
                icon: Icon(
                    bloqCookies3ros
                        ? Icons.cookie_rounded
                        : Icons.cookie_outlined,
                    size: 16),
                label: Text(bloqCookies3ros ? '3ros: no' : '3ros: sí',
                    style: _chico),
              ),
              OutlinedButton.icon(
                onPressed: !corriendo ? null : onLimpiarCookies,
                icon: const Icon(Icons.cleaning_services_rounded,
                    size: 16),
                label: const Text('Cookies', style: _chico),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
