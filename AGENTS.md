# División de trabajo mimapp

Reglas generales:
- Español en código, commits y UI.
- Módulos gt/* independientes entre sí; nada compartido salvo eventlog.
- No borrar código existente sin orden explícita.
- En archivos compartidos (rust/src/api/mod.rs, lib/app/app.dart) cada
  agente toca SOLO su línea/case.
- Push por batch tras CI verde; ciclo fix-push hasta verde.
- Concurrencia manejada por Rust; Dart sin threads/guards salvo flags
  triviales.
- Errores SIEMPRE legibles y con contexto (dónde falló y por qué).

## Agente A (ox-alpha)

### 1. LUA HARDENING (lib/lua/lua_controller.dart)
- Sacar next() del conteo de children (contar con getI secuencial):
  elimina para siempre la clase de error "table expected for
  iteration" (crash "nodo 9 de page.body").
- Errores con contexto completo: nodo N (tipo real) · children[i] ·
  causa.

### 2. NOSTR BUSCA (módulo nuevo independiente)
- rust/src/gt/nostrbusca.rs: cliente efímero read-only propio (no
  comparte cliente ni estado con nostrn/nostrpeer).
  - perfil_fetch(npub, relays_csv, timeout): B1 — kind 0 del autor.
  - buscar_usuarios(query, relays_csv, límite, timeout): B2 —
    Filter::kind(0).search(query) (NIP-50), parsea Metadata por evento,
    ordenado por nombre.
- rust/src/api/nostr_busca.rs: wrapper FRB fino,
  PerfilItem{npub,name,display_name,about,picture,nip05}, patrón
  ok/error del proyecto.
- lib/services/nostr_busca.dart: clase NostrBusca reutilizable desde
  cualquier pantalla o página Lua caliente.
- lib/screens/nostr_busca_screen.dart: un campo de texto que detecta
  npub/nprofile → B1 directo, si no → B2; lista de resultados → ficha;
  RelayEditor con defaults damus/nos.social/nostr.band/
  search.nos.today.
- radial_catalog.dart: entrada 'ub' (Nostr Busca).

### 3. MENÚ RADIAL EN CAPAS (refactor autorizado)
- Separar en clases bajo lib/app/widgets/radial/:
  - radial_item.dart: modelo RadialMenuItem{key,label,icon,color}.
  - radial_catalog.dart: catálogo único de items (único lugar donde se
    agregan entradas nuevas).
  - radial_layer.dart: UN anillo de máx 8 botones (geometría +
    animación escalonada actual).
  - radial_menu.dart: corta el catálogo en trozos de 8 y apila capas.
- Comportamiento:
  - El botón central CAMBIA DE MENÚ CIRCULAR: [+] apila el siguiente
    anillo con los items que no entraron; y así sucesivamente.
  - Tocar afuera cierra SOLO la capa actual (vuelve al anillo anterior).
  - Última capa: centro pasa a [×] y cierra todo.
  - Nostringer ('ring') pasa a item normal del anillo (el centro ya no
    es suyo cuando hay más de una capa).
  - Estado inicial de cada apertura: capa 1.

## Agente B

### PKARR versión nueva (github.com/pubky/pkarr)
1. rust/Cargo.toml: pkarr = "=8.0.0" (las 5.0.4/5.0.5 están yanked; NO
   bajar de versión).
2. Adaptar rust/src/api/pkarr.rs a la API 8.0 (firmas de
   publish/resolve, Timestamp, caché) verificando contra
   docs.rs/pkarr/8.0.0.
3. Generar + GUARDAR secret key CIFRADA localmente: AES-GCM con clave
   derivada del PIN (agregar aes-gcm + pbkdf2/scrypt al Cargo.toml).
   Lo publicado NO va cifrado: TXT público firmado como corresponde a
   pkarr.
4. Cargar/descifrar la key al arrancar la app.
5. Publicar público firmado; modo "both" (DHT Kademlia Mainline +
   relays) por defecto.
6. CONSULTAR claves públicas de TERCEROS: resolve arbitrario por
   zbase32 + listar los registros TXT del paquete de forma legible (no
   string crudo).
7. lib/screens/pkarr_test_screen.dart: generar / guardar cifrada /
   cargar / publicar / consultar cualquier pubkey.
   radial_catalog.dart: entrada 'up' (Pkarr).
