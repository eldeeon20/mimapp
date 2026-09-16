# media_server · SERVIDOR de moldes (idiota) + HERRAMIENTA aparte

```
lib/services/media_server/      ← SERVIDOR (solo .mld, sin SQL)
  media_server.dart  ← barrel
  media_server.md    ← este doc
  base.dart          ← carpeta moldes, validaciones, modelos, tags
  duro.dart          ← AES-256-GCM por trozos + descifrarRango
  servir.dart        ← MediaServer.abrir/leer (crudo)

lib/toolsec/create_molde_sql.dart ← HERRAMIENTA (crea .mld + TU sql)
```

## Reparto (no se mezclan)

- **Server** (`media_server/`): se abre UNA vez con la ruta del
  `.mld` y sirve bytes CRUDOS por offset absoluto (`leer`). No recibe
  clave, no abre SQL, no sabe qué trae el molde. Si no abrís tu SQL,
  no sabés qué trae.
- **User** (vos, tu SQL): guarda filas (nombre, formato, tamaño,
  inicio, fin, fecha, tags, trozo) + sal del molde. Con tu SQL
  calculás trozos (`Duro.offsetDe/largoDe`), pedís crudo y descifrás
  (`Duro.descifrarRango` con tu clave+sal+nombre).
- **Tool** (`create_molde_sql`, de una vez): carpeta → `.mld` +
  índice en tu SQL (db ChaCha20 con TU clave). Clave ÚNICA: la misma
  abre tu SQL y deriva claves del molde (PBKDF2 + sal por molde).

## Molde

UN solo `.mld` con N archivos: cada archivo en trozos de 64KB en
claro, cada trozo `nonce(12) + GCM + tag(16)` = 28 de más por trozo,
sin padding (500 B → 528). Primero en 0. Moldes xor viejos se leen
(fallback con su semilla).

## SQL (tuya, la deja el tool)

- `moldes(nombre UNIQUE, ruta, semilla, fecha, total, sal, cifrado)`
- `archivos(molde, nombre, formato, tamano, inicio, fin, fecha,
  tag1..tag8, trozo)` + `idx_archivos_molde`: abrir `molde_test`
  trae SOLO sus filas.

## Protocolo

1. Abrís TU sql → filas del molde.
2. `server.leer(absoluto, largo)` por cada trozo pisado.
3. `Duro.descifrarRango(claveArchivo, rango)` → `[desde, hasta)`.
4. Atajo: `CreateMoldeSql.pedirRango` hace 1-3 de una vez.
