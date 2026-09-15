import '../../../db/caja_sql.dart';
import 'puente.dart';

/// Conector agenda-sql: la página agenda-sql usa la CajaSql cifrada
/// (SQLite ChaCha20) en vez del .pr. Todo con llave del puente.
///
/// SU archivo: los comandos agenda_* nuevos van acá, no en la pantalla.
class PuenteAgenda extends WebkConector implements WebkCerrable {
  final String Function() leerLlave;
  final void Function(String) log;
  final _caja = CajaSql();

  PuenteAgenda({required this.leerLlave, required this.log});

  @override
  Set<String> get comandos => const {
        'agenda_bases',
        'agenda_abrir',
        'agenda_listar',
        'agenda_agregar',
        'agenda_borrar',
        'agenda_cerrar',
      };

  @override
  void cerrar() => _caja.cerrar();

  /// Nombre a base: solo letras/números/guion/piso, máx 40.
  static String _sanearBase(String s) {
    final limpio =
        s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    if (limpio.isEmpty) return '';
    return limpio.length > 40 ? limpio.substring(0, 40) : limpio;
  }

  @override
  Future<dynamic> atender(Map<String, dynamic> cmd) async {
    final cual = cmd['cmd']?.toString() ?? '';
    if (cual == 'agenda_bases') {
      return {'bases': await CajaSql.listarBases()};
    }
    if (!llaveOk(leerLlave(), cmd)) return 'DENEGADO';
    switch (cual) {
      case 'agenda_abrir':
        final nombre = _sanearBase(cmd['nombre']?.toString() ?? '');
        final pass = cmd['pass']?.toString() ?? '';
        if (nombre.isEmpty || pass.isEmpty) {
          return 'ERROR: falta nombre o pass';
        }
        await _caja.abrir(nombre, clave: pass);
        _caja.crearTabla('entradas', {
          'titulo': 'TEXT',
          'cuerpo': 'TEXT',
          'fecha': 'TEXT',
          'creada': 'INTEGER',
        });
        final n = _caja.contar('entradas');
        log('· agenda-sql "$nombre" abierta ($n entradas)');
        return 'OK';
      case 'agenda_listar':
        if (!_caja.abierta) return 'ERROR: sin agenda abierta';
        final q = cmd['buscar']?.toString().trim() ?? '';
        var filas =
            _caja.listar('entradas', por: 'id', asc: false, limite: 100);
        if (q.isNotEmpty) {
          final ql = q.toLowerCase();
          filas = filas
              .where((f) =>
                  '${f['titulo']}'.toLowerCase().contains(ql) ||
                  '${f['cuerpo']}'.toLowerCase().contains(ql))
              .toList();
        }
        return {'items': filas};
      case 'agenda_agregar':
        if (!_caja.abierta) return 'ERROR: sin agenda abierta';
        final titulo = cmd['titulo']?.toString().trim() ?? '';
        if (titulo.isEmpty) return 'ERROR: título vacío';
        final id = _caja.agregar('entradas', {
          'titulo': titulo,
          'cuerpo': cmd['cuerpo']?.toString() ?? '',
          'fecha': cmd['fecha']?.toString() ?? '',
          'creada': DateTime.now().millisecondsSinceEpoch,
        });
        return {'id': id};
      case 'agenda_borrar':
        if (!_caja.abierta) return 'ERROR: sin agenda abierta';
        final id =
            (cmd['id'] is num) ? (cmd['id'] as num).toInt() : -1;
        final n = _caja.quitar('entradas', id);
        return n > 0 ? 'OK' : 'ERROR: no existe id $id';
      case 'agenda_cerrar':
        _caja.cerrar();
        log('· agenda-sql cerrada');
        return 'OK';
      default:
        return 'CMD?';
    }
  }
}
