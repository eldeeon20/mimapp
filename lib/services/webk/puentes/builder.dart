import '../../../db/caja_sql.dart';
import '../paginas/indice.dart';
import 'puente.dart';

/// Conector del editor builder: guarda las webs armadas en
/// webapp/sitio/ (cada app su carpeta) y las lista. Todo con llave.
/// SU archivo: comandos builder_* nuevos van acá, no en la pantalla.
class PuenteBuilder extends WebkConector implements WebkCerrable {
  final WebkIndex indice;
  final String Function() leerLlave;
  final void Function(String) log;
  final _zip = CajaSql();

  /// DB de páginas: db "paginas" (paginas.db cifrada), tabla "paginas".
  /// Muchas páginas con distinto nombre + versiones por nombre
  /// (1.0, 1.1, 1.2…): mismo nombre = versión nueva.
  final _pags = CajaSql();

  PuenteBuilder({
    required this.indice,
    required this.leerLlave,
    required this.log,
  });

  @override
  void cerrar() {
    _zip.cerrar();
    _pags.cerrar();
  }

  @override
  Set<String> get comandos => const {
        'builder_guardar',
        'builder_sitios',
        'builder_zip_abrir',
        'builder_zip_listar',
        'builder_zip_guardar',
        'builder_zip_bajar',
        'builder_zip_borrar',
        'builder_zip_cerrar',
        'builder_pagina_abrir',
        'builder_pagina_listar',
        'builder_pagina_guardar',
        'builder_pagina_ver',
        'builder_pagina_borrar',
        'builder_pagina_cerrar',
      };

  static String _sanear(String s) {
    var l = s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
    if (l.isEmpty) l = 'mi-web';
    if (l.length > 40) l = l.substring(0, 40);
    return l;
  }

  @override
  Future<dynamic> atender(Map<String, dynamic> cmd) async {
    if (!llaveOk(leerLlave(), cmd)) return 'DENEGADO';
    final cual = cmd['cmd']?.toString() ?? '';
    if (cual == 'builder_sitios') {
      return {
        'sitios': indice.paginas
            .where((p) => p.startsWith('webapp/sitio/'))
            .toList()
      };
    }
    if (cual.startsWith('builder_zip_')) return atenderZip(cmd);
    if (cual.startsWith('builder_pagina_')) return atenderPaginas(cmd);
    // builder_guardar {nombre, cuerpo, css, js} → sitio triple
    // (compat: {nombre, html} → página única vieja).
    final base =
        'webapp/sitio/${_sanear(cmd['nombre']?.toString() ?? '')}';
    final htmlViejo = cmd['html']?.toString() ?? '';
    if (htmlViejo.isNotEmpty) {
      final bajo = htmlViejo.toLowerCase();
      if (!bajo.contains('<html') || !bajo.contains('</html>')) {
        return 'ERROR: html mal formado';
      }
      final nombre = '$base.html';
      indice.registrarTexto(nombre, htmlViejo);
      log('· builder guardó "$nombre" (${htmlViejo.length} chars)');
      return {'ok': true, 'pagina': nombre};
    }
    final cuerpo = cmd['cuerpo']?.toString() ?? '';
    final css = cmd['css']?.toString() ?? '';
    final js = cmd['js']?.toString() ?? '';
    if (cuerpo.trim().isEmpty) return 'ERROR: cuerpo vacío';
    // Tope alto pero finito: el índice vive en RAM y el puente manda
    // todo en un solo mensaje (2MB ≈ 400 páginas normales).
    if (cuerpo.length + css.length + js.length > 2000000) {
      return 'ERROR: muy grande (máx 2MB)';
    }
    indice.registrarTexto('$base/style.css', css);
    indice.registrarTexto('$base/script.js', js);
    indice.registrarTexto('$base/index.html', _indiceSitio(base, cuerpo));
    log('· builder guardó sitio "$base/" (index+css+js)');
    return {'ok': true, 'pagina': '$base/index.html'};
  }

  /// ZIP en SQL (db "sitios" cifrada, tabla zips).
  /// El zip viaja en base64 porque el puente solo pasa texto/JSON.
  Future<dynamic> atenderZip(Map<String, dynamic> cmd) async {
    if (!llaveOk(leerLlave(), cmd)) return 'DENEGADO';
    final cual = cmd['cmd']?.toString() ?? '';
    switch (cual) {
      case 'builder_zip_abrir':
        final zpass = cmd['pass']?.toString() ?? '';
        if (zpass.isEmpty) return 'ERROR: falta pass';
        await _zip.abrir('sitios', clave: zpass);
        _zip.crearTabla('zips', {
          'nombre': 'TEXT',
          'datos': 'TEXT',
          'fecha': 'INTEGER',
        });
        log('· zip-sql abierto (${_zip.contar('zips')} guardados)');
        return 'OK';
      case 'builder_zip_listar':
        if (!_zip.abierta) return 'ERROR: sin zip-sql abierto';
        final metas =
            _zip.listar('zips', por: 'id', asc: false, limite: 100);
        return {
          'zips': [
            for (final m in metas)
              {
                'nombre': '${m['nombre']}',
                'fecha': m['fecha'],
                'tamB64': (m['datos'] as String?)?.length ?? 0,
              }
          ]
        };
      case 'builder_zip_guardar':
        if (!_zip.abierta) return 'ERROR: sin zip-sql abierto';
        final znombre = _sanear(cmd['nombre']?.toString() ?? '');
        final b64 = cmd['b64']?.toString() ?? '';
        if (znombre.isEmpty || b64.isEmpty) {
          return 'ERROR: falta nombre o zip';
        }
        // ~6MB de zip: el base64 viaja en un solo mensaje del puente.
        if (b64.length > 8000000) {
          return 'ERROR: muy grande (máx ~6MB de zip)';
        }
        _zip.quitarDonde('zips', 'nombre = ?', [znombre]);
        _zip.agregar('zips', {
          'nombre': znombre,
          'datos': b64,
          'fecha': DateTime.now().millisecondsSinceEpoch,
        });
        log('· zip-sql guardó "$znombre.zip" (${b64.length} chars b64)');
        return 'OK';
      case 'builder_zip_bajar':
        if (!_zip.abierta) return 'ERROR: sin zip-sql abierto';
        final qnombre = _sanear(cmd['nombre']?.toString() ?? '');
        final fila = _zip.uno('zips', 'nombre = ?', [qnombre]);
        if (fila == null) return 'ERROR: no existe "$qnombre"';
        return {
          'nombre': '${fila['nombre']}',
          'b64': '${fila['datos']}',
        };
      case 'builder_zip_borrar':
        if (!_zip.abierta) return 'ERROR: sin zip-sql abierto';
        final bnombre = _sanear(cmd['nombre']?.toString() ?? '');
        final n = _zip.quitarDonde('zips', 'nombre = ?', [bnombre]);
        return n > 0 ? 'OK' : 'ERROR: no existe "$bnombre"';
      case 'builder_zip_cerrar':
        _zip.cerrar();
        log('· zip-sql cerrado');
        return 'OK';
      default:
        return 'CMD?';
    }
  }

  /// Siguiente versión para [nombre]: 1.0, 1.1, 1.2…
  /// Distinto nombre arranca en 1.0; mismo nombre suma minor.
  static String _siguienteVersion(List<String> existentes) {
    var mayor = 1;
    var menor = -1;
    for (final v in existentes) {
      final p = v.split('.');
      final a = int.tryParse(p[0]) ?? 0;
      final b = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
      if (a > mayor || (a == mayor && b > menor)) {
        mayor = a;
        menor = b;
      }
    }
    if (existentes.isEmpty) return '1.0';
    return '$mayor.${menor + 1}';
  }

  static int _cmpVersion(String a, String b) {
    List<int> partes(String v) {
      final p = v.split('.');
      return [
        int.tryParse(p[0]) ?? 0,
        int.tryParse(p.length > 1 ? p[1] : '0') ?? 0,
      ];
    }

    final pa = partes(a);
    final pb = partes(b);
    if (pa[0] != pb[0]) return pa[0].compareTo(pb[0]);
    return pa[1].compareTo(pb[1]);
  }

  /// DB "paginas": guarda versiones, lista, trae una al índice, borra.
  /// La db queda en disco cifrada; el índice (RAM) solo recibe la
  /// versión que se quiere ver.
  Future<dynamic> atenderPaginas(Map<String, dynamic> cmd) async {
    if (!llaveOk(leerLlave(), cmd)) return 'DENEGADO';
    final cual = cmd['cmd']?.toString() ?? '';
    switch (cual) {
      case 'builder_pagina_abrir':
        final ppass = cmd['pass']?.toString() ?? '';
        if (ppass.isEmpty) return 'ERROR: falta pass';
        await _pags.abrir('paginas', clave: ppass);
        _pags.crearTabla('paginas', {
          'nombre': 'TEXT',
          'version': 'TEXT',
          'cuerpo': 'TEXT',
          'css': 'TEXT',
          'js': 'TEXT',
          'fecha': 'INTEGER',
        });
        log('· db paginas abierta (${_pags.contar('paginas')} filas)');
        return 'OK';
      case 'builder_pagina_listar':
        if (!_pags.abierta) return 'ERROR: sin db paginas abierta';
        final filas =
            _pags.listar('paginas', por: 'id', asc: false, limite: 500);
        final grupos = <String, List<String>>{};
        for (final f in filas) {
          final n = '${f['nombre']}';
          grupos.putIfAbsent(n, () => []).add('${f['version']}');
        }
        for (final v in grupos.values) {
          v.sort(_cmpVersion);
        }
        return {
          'paginas': [
            for (final e in grupos.entries)
              {'nombre': e.key, 'versiones': e.value}
          ]
        };
      case 'builder_pagina_guardar':
        if (!_pags.abierta) return 'ERROR: sin db paginas abierta';
        final gnombre = _sanear(cmd['nombre']?.toString() ?? '');
        final cuerpo = cmd['cuerpo']?.toString() ?? '';
        final css = cmd['css']?.toString() ?? '';
        final js = cmd['js']?.toString() ?? '';
        if (gnombre.isEmpty || cuerpo.trim().isEmpty) {
          return 'ERROR: falta nombre o cuerpo';
        }
        if (cuerpo.length + css.length + js.length > 2000000) {
          return 'ERROR: muy grande (máx 2MB)';
        }
        final todas =
            _pags.listar('paginas', por: 'id', asc: false, limite: 2000);
        final previas = [
          for (final f in todas)
            if ('${f['nombre']}' == gnombre) '${f['version']}',
        ];
        final version = _siguienteVersion(previas);
        _pags.agregar('paginas', {
          'nombre': gnombre,
          'version': version,
          'cuerpo': cuerpo,
          'css': css,
          'js': js,
          'fecha': DateTime.now().millisecondsSinceEpoch,
        });
        log('· db paginas guardó "$gnombre" v$version');
        return {'ok': true, 'nombre': gnombre, 'version': version};
      case 'builder_pagina_ver':
        if (!_pags.abierta) return 'ERROR: sin db paginas abierta';
        final vnombre = _sanear(cmd['nombre']?.toString() ?? '');
        final vpedida = cmd['version']?.toString() ?? '';
        final todasV =
            _pags.listar('paginas', por: 'id', asc: false, limite: 2000);
        final candidatas = [
          for (final f in todasV)
            if ('${f['nombre']}' == vnombre) f,
        ];
        if (candidatas.isEmpty) return 'ERROR: no existe "$vnombre"';
        candidatas.sort((a, b) =>
            _cmpVersion('${a['version']}', '${b['version']}'));
        Map<String, Object?>? elegida;
        if (vpedida.isEmpty) {
          elegida = candidatas.last;
        } else {
          for (final f in candidatas) {
            if ('${f['version']}' == vpedida) elegida = f;
          }
        }
        if (elegida == null) {
          return 'ERROR: "$vnombre" no tiene v$vpedida';
        }
        final base = 'webapp/sitio/$vnombre';
        indice.registrarTexto('$base/style.css', '${elegida['css']}');
        indice.registrarTexto('$base/script.js', '${elegida['js']}');
        indice.registrarTexto('$base/index.html',
            _indiceSitio(base, '${elegida['cuerpo']}'));
        log('· db paginas cargó "$vnombre" v${elegida['version']} al índice');
        return {
          'ok': true,
          'pagina': '$base/index.html',
          'version': '${elegida['version']}',
        };
      case 'builder_pagina_borrar':
        if (!_pags.abierta) return 'ERROR: sin db paginas abierta';
        final bnombre = _sanear(cmd['nombre']?.toString() ?? '');
        final bversion = cmd['version']?.toString() ?? '';
        final int n;
        if (bversion.isEmpty) {
          n = _pags.quitarDonde('paginas', 'nombre = ?', [bnombre]);
        } else {
          n = _pags.quitarDonde(
              'paginas', 'nombre = ? AND version = ?', [bnombre, bversion]);
        }
        return n > 0 ? 'OK' : 'ERROR: no existe "$bnombre"';
      case 'builder_pagina_cerrar':
        _pags.cerrar();
        log('· db paginas cerrada');
        return 'OK';
      default:
        return 'CMD?';
    }
  }

  /// index del sitio: el cuerpo + cargador que trae css/js con pase.
  /// Igual que builder.html: sin llave no sale nada.
  static String _indiceSitio(String base, String cuerpo) =>
      '''<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$base</title>
</head>
<body>
$cuerpo
<script>
(function(){
  async function pasePara(pagina){
    const r = await window.flutter_inappwebview.callHandler(
      'webk', {cmd: 'pase', pagina: pagina, llave: window.WEBK_LLAVE || ''});
    return (typeof r === 'string') ? r : '';
  }
  async function cargar(pagina, tipo){
    const p = await pasePara(pagina);
    if(!p || p === 'DENEGADO') return;
    const t = await fetch('/' + pagina + '?pase=' + encodeURIComponent(p))
      .then(function(r){ return r.text(); });
    var el = document.createElement(tipo === 'css' ? 'style' : 'script');
    el.textContent = t;
    (tipo === 'css' ? document.head : document.body).appendChild(el);
  }
  async function arrancar(){
    if(!window.flutter_inappwebview) return;
    for(var i = 0; i < 40 && !window.WEBK_LLAVE; i++){
      await new Promise(function(r){ setTimeout(r, 200); });
    }
    cargar('$base/style.css', 'css');
    cargar('$base/script.js', 'js');
  }
  arrancar();
})();
</script>
</body>
</html>
''';
}
