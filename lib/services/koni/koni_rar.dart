import 'package:koni_archive/io.dart';

import 'koni.dart';

/// RAR/CBR para Koni: valida extensión y abre con auto-detección.
///
/// Solo responde por `.rar`/`.cbr` (RAR4 + RAR5 clean-room). El resto lo
/// rechaza con error legible para que [Koni] derive al formato que
/// corresponda. NOTA koni_archive 0.9.0: sin headers cifrados (`-hp`)
/// ni multivolumen → esos casos tiran error tipado del paquete.
class KoniRar implements KoniFormato {
  @override
  String get etiqueta => 'RAR';

  @override
  List<String> get extensiones => const ['rar', 'cbr'];

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
      throw UnsupportedError('KoniRar: no es RAR ($ruta)');
    }
    return Koni.abrirArchivo(
      ruta,
      etiqueta: etiqueta,
      password: password,
      maxEntradaBytes: maxEntradaBytes,
    );
  }
}
