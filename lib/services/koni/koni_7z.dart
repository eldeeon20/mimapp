import 'package:koni_archive/io.dart';

import 'koni.dart';

/// 7z/CB7 para Koni: valida extensión y abre con auto-detección.
///
/// Solo responde por `.7z`/`.cb7`; el resto lo rechaza con error legible
/// para que [Koni] derive al formato que corresponda.
class Koni7z implements KoniFormato {
  @override
  String get etiqueta => '7Z';

  @override
  List<String> get extensiones => const ['7z', 'cb7'];

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
      throw UnsupportedError('Koni7z: no es 7z ($ruta)');
    }
    return Koni.abrirArchivo(
      ruta,
      etiqueta: etiqueta,
      password: password,
      maxEntradaBytes: maxEntradaBytes,
    );
  }
}
