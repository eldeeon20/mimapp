import '../paginas/indice.dart';
import '../servidor/servidor.dart';
import 'puente.dart';

/// Conector núcleo de WebK: estado/hora/autorizar/abrir/pase.
/// Vive en SU archivo; la pantalla solo lo registra.
class PuenteNucleo extends WebkConector {
  final WebkServer server;
  final WebkIndex indice;
  final String Function() leerLlave;
  final void Function(String) log;
  final Future<void> Function(String pagina) cargar;

  PuenteNucleo({
    required this.server,
    required this.indice,
    required this.leerLlave,
    required this.log,
    required this.cargar,
  });

  @override
  Set<String> get comandos => const {
        'estado',
        'hora',
        'autorizar',
        'abrir',
        'pase',
      };

  @override
  Future<dynamic> atender(Map<String, dynamic> cmd) async {
    switch (cmd['cmd']?.toString() ?? '') {
      case 'estado':
        return {
          'servidas': server.servidas,
          'rechazadas': server.rechazadas,
          'retosActivos': server.retosActivos,
          'retosCaidos': server.retosCaidos,
          'puerto': server.puerto,
        };
      case 'hora':
        return {'dart_ahora': DateTime.now().toIso8601String()};
      case 'autorizar':
        final ok = llaveOk(leerLlave(), cmd);
        log(ok
            ? '· la página pidió autorización (llave OK)'
            : '✗ la página pidió autorización (llave MAL)');
        if (ok) server.autorizarUna();
        return ok ? 'OK' : 'DENEGADO';
      case 'abrir':
        final okAbrir = llaveOk(leerLlave(), cmd);
        final pagina = cmd['pagina']?.toString() ?? '';
        if (!okAbrir || !indice.paginas.contains(pagina)) {
          log('✗ abrir "$pagina": DENEGADO (puente no verificado)');
          return 'DENEGADO';
        }
        log('· Dart habilita "$pagina" (puente OK)');
        server.autorizarUna();
        await cargar(pagina);
        return 'OK';
      case 'pase':
        // Composición interna (iframe/fetch): la página ya cargada pide
        // un pase de una sola vez para incrustar otra. Solo con llave.
        final okPase = llaveOk(leerLlave(), cmd);
        final destino = cmd['pagina']?.toString() ?? '';
        if (!okPase || !indice.paginas.contains(destino)) {
          log('✗ pase "$destino": DENEGADO');
          return 'DENEGADO';
        }
        log('· pase emitido para "$destino" (iframe/fetch)');
        return server.emitirPase(destino);
      default:
        return 'CMD?';
    }
  }
}
