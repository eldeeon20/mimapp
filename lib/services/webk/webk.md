# WebK · servidor html local + páginas + puentes

Web criptográfica de prueba: un servidor HTTP en el propio teléfono
(loopback, puerto aleatorio) que sirve páginas SOLO a su WebView.
Chrome puede ver el puerto pero jamás recibe el html.

## Regla de oro

**El html real NUNCA sale directo.** Cada carga pasa por:

```
app → autorizarUna() ─┐
                      ▼
navegador pide /pagina ──→ ¿pase válido? ── sí ──→ html+js real (pase quemado)
                           │
                           no
                           ▼
                      ¿señal autorizarUna? ── no ──→ 403 sordo (sin banner)
                           │
                           sí (se consume)
                           ▼
                      server manda RETO (js de prueba, sin contenido)
                           │
                ┌──────────┴──────────┐
                ▼                     ▼ (10s)
  js responde PING          nadie responde → pendiente BORRADO
  {nonce, llave, fecha}     (conexión cortada, cuenta en retosCaidos)
                │
                ▼
  server verifica: nonce existe + llave == sesión + fecha fresca (±30s)
                │
        ┌───────┴───────┐
        ▼               ▼
  {ok, pase}     403 DENEGADO (Chrome: sin llave, siempre acá)
        │
        ▼
  js recarga /pagina?pase=… → html real
```

La **llave de sesión** la genera la app al iniciar el server y la inyecta
SOLO en su WebView (Dart→JS). Chrome no la tiene: su ping muere.

## Carpetas (qué tiene cada una y para qué)

```
lib/services/webk/
  webk.dart        ← barrel: exporta todo (la pantalla importa solo esto)
  webk.md          ← este archivo

  servidor/        ← EL SERVIDOR html (Dart puro, sin UI)
    servidor.dart  ← WebkServer: loopback, reto, ping, pases de un uso,
                     emitirPase(), stats (servidas/rechazadas/retosCaidos)
    reto.dart      ← RetoPendiente, PaseUnico, html+js del reto,
                     pingJson(). El reto espera window.WEBK_LLAVE.
    mime.dart      ← extensión → Content-Type

  paginas/         ← EL ÍNDICE + las páginas como ARCHIVOS
    indice.dart    ← WebkIndex: registra, resuelve, valida forma,
                     hook verificarContenido (fase 2: hash/firma),
                     cargaAsset (fallback a demanda, con veto a "..").
                     Nada de html suelto en Dart.
    *.html         ← hola, puerta, demo, pagina2, app (SPA),
                     twitch, face, agenda-sql… (a futuro, muchas más)

  puentes/         ← EL PUENTE JS→Dart, un conector por archivo
    puente.dart    ← interfaz WebkConector (comandos + atender),
                     WebkCerrable, llaveOk()
    registro.dart  ← RegistroPuentes: rutea cmd → su conector.
                     Sin conector → 'CMD?'; si lanza → 'ERROR'.
    nucleo.dart    ← estado, hora, autorizar, abrir, pase
    agenda.dart    ← agenda_* (CajaSql cifrada, no el .pr)
    builder.dart   ← builder_* (sitios en RAM, zips y páginas en SQL)

  webapp/          ← LAS WEBAPPS (cada app su carpeta)
    builder/       ← editor de páginas web
      builder.html ← marcas + cargador (pide css/js con pase)
      builder.css  ← todo el estilo
      js/          ← lógica partida (ver "El json" abajo)
    sitio/         ← (se llena solo) sitios guardados desde el builder
```

`pubspec.yaml` declara `paginas/` entera (es plana: archivo nuevo entra
solo al APK). En `webapp/` cada subcarpeta (`builder/`, `builder/js/`,
toda app nueva) necesita su propia entrada: el empaquetador no recorre
subcarpetas. `sitio/` no se declara (se llena en disco en runtime).

## El puente de ida y vuelta

### JS → Dart (la página pide)

```js
const r = await window.flutter_inappwebview.callHandler(
  'webk', {cmd: 'abrir', pagina: 'demo.html', llave: window.WEBK_LLAVE || ''});
```

- `cmd`: nombre del comando (lo rutea el registro a su conector).
- `llave`: la de sesión (inyectada por Dart; sin ella → DENEGADO).
- Respuesta: String (`'OK'`/`'DENEGADO'`/`'ERROR: …'`) o Map/List
  (deben ser JSON: solo texto, números, listas, mapas).

### Dart → JS (la app manda)

1. **Llave**: en cada `onLoadStop` la pantalla inyecta
   `window.WEBK_LLAVE='<sesión>'`. El html estático nunca la trae.
2. **Cargar página**: el conector `abrir` verifica la llave, manda
   `autorizarUna()` y hace `loadUrl(baseUrl/pagina)`.
3. **Pases para incrustar**: `emitirPase(pagina)` → la página lo usa en
   `iframe.src = '/x.html?pase=…'` o `fetch('/x.html?pase=…')`
   (cada pase se quema al usarse; pedir uno por carga).

### Agregar un conector nuevo (ej: `puentes/clima.dart`)

```dart
class PuenteClima extends WebkConector {
  PuenteClima({required this.leerLlave, required this.log});
  final String Function() leerLlave;
  final void Function(String) log;

  @override
  Set<String> get comandos => const {'clima_hoy'};

  @override
  Future<dynamic> atender(Map<String, dynamic> cmd) async {
    if (!llaveOk(leerLlave(), cmd)) return 'DENEGADO';
    return {'temp': 22};
  }
}
```

1. Crear el archivo en `puentes/`.
2. Exportarlo en `webk.dart`.
3. Registrarlo en la pantalla ( UNA línea ):
   `..registrar(PuenteClima(leerLlave: () => _llaveSesion, log: _logPuente))`
4. La página JS lo llama con `{cmd: 'clima_hoy', llave: …}`.

Si el conector guarda algo abierto (db, archivo), implementa
`WebkCerrable` y la pantalla lo cierra con `cerrarTodos()` al salir.
La pantalla (`webk_test_screen.dart`, ~340 líneas) SOLO registra:
1000 páginas = 1000 archivos, ella no crece.

## El json (cómo partir una webapp sin tocar Dart)

`webapp/<app>/js/partes.json` es la lista de partes, en orden:

```json
["componentes.js", "generar.js", "...", "preview.js"]
```

- El `builder.html` trae un **cargador** mínimo: pide el css, lee el
  manifiesto y trae cada js **con pase** (un `<script src>` común
  recibiría el reto, no el código: por eso no se usa).
- El servidor trae cada parte **a demanda** (`cargaAsset`): agregar un
  js nuevo = agregarlo al json. Ni el html ni Dart se tocan.
- En Dart solo se registran los **puntos de entrada** (para el menú):
  `_entradasWebapp = ['webapp/builder/builder.html']`.

## Las páginas en DB (db `paginas`, db `sitios`)

El índice vive en **RAM** (se pierde al cerrar). Para persistir hay dos
db cifradas (ChaCha20, pass pedido en la página):

| db (archivo) | tabla | qué guarda |
|---|---|---|
| `paginas.db` | `paginas(nombre, version, cuerpo, css, js, fecha)` | páginas con **versiones**: mismo nombre → 1.0, 1.1, 1.2…; distinto nombre → arranca en 1.0 |
| `sitios.db` | `zips(nombre, datos, fecha)` | sitios empaquetados en ZIP (base64, porque el puente pasa texto) |

Comandos (todos con llave):

- `builder_pagina_guardar {nombre, cuerpo, css, js}` → `{ok, nombre, version}`
- `builder_pagina_listar` → `{paginas: [{nombre, versiones: […]}]}`
- `builder_pagina_ver {nombre, version?}` → carga esa versión al índice
  y devuelve `{ok, pagina, version}` (después `abrir` la muestra)
- `builder_pagina_borrar {nombre, version?}` → una versión o todas
- `builder_zip_guardar/listar/bajar/borrar/abrir/cerrar` → lo mismo en ZIP

Flujo típico (builder): `BD 💾` → guarda v1.3 → `BD 📂` → ▶ v1.1 →
se carga al índice → se abre con reto+ping+pase como cualquier página.

## Límites y prueba

- Sitio triple (cuerpo+css+js): máx **2MB**. Zip en base64: máx **~6MB**.
  ¿Por qué hay tope? El índice vive en RAM y el puente manda todo en un
  solo mensaje: sin tope, una página podría comerse la memoria.
  El ZIP en sí NO comprime (store): empaqueta sin cifrar; lo cifrado es
  la db donde se guarda.
- Prueba = sin segundo plano: al detener/salir se quema la llave y se
  borran cookies, historial e índice. No como el módulo web.
