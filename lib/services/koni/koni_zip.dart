import 'package:koni_archive/io.dart';

import 'koni.dart';

/// ZIP/CBZ para Koni: valida extensión y abre con auto-detección.
///
/// Solo responde por `.zip`/`.cbz`; el resto lo rechaza con error legible
/// para que [Koni] derive al formato que corresponda.
class KoniZip implements KoniFormato {
  @override
  String get etiqueta => 'ZIP';

  @override
  List<String> get extensiones => const ['zip', 'cbz'];

  @override
  int get maxEntradaBytes => 1 << 30;

  @override
  bool soporta(String ruta) {
    final r = ruta.toLowerCase();
    return extensiones.any((e) => r.endsWith('.$e'));
  }

  @override
  Future<Archive> abrir(String ruta, {String? password}) {
    if (!soporta(ruta)) {
      throw UnsupportedError('KoniZip: no es ZIP ($ruta)');
    }
    return Koni.abrirArchivo(
      ruta,
      etiqueta: etiqueta,
      password: password,
      maxEntradaBytes: maxEntradaBytes,
    );
  }
}
