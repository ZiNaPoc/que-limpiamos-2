# 12 — Respaldo y recuperación (antes de cualquier cambio de schema)

- **Fecha:** 2026-11-24 · **Aplica a:** SQL 002 y a cualquier cambio de estructura futuro.
- **Motor:** TiDB Cloud Serverless v8.5.3 (MySQL 8.0). No hay `mysqldump`, `mysql` ni `dumpling` instalados en el equipo, por eso el respaldo se hace con un script Node que usa la misma conexión TLS de la app y no necesita dependencias nuevas.

## 1. Herramientas preparadas (todas de solo lectura sobre la BD)

| Comando (desde `limpiandotuhogar/backend`) | Qué hace | Estado |
|---|---|---|
| `npm run db:verificar-002` | Lista cuáles de los 84 objetos del 002 (v9) y la precondición de `updated_at` existen y cuántas filas tienen las tablas que toca. Sale con código 2 si el 002 quedó a medias | **Probado** 2026-11-24: 0/84 (v9), "NO APLICADO" |
| `npm run db:respaldo` | Crea `backups/<fecha>/restore.sql` (DDL con `SHOW CREATE TABLE` + `INSERT` de todas las filas) y `resumen.json` (filas por tabla, motor, SHA-256) | **Probado** 2026-11-24: 13 tablas, 4 filas (servicios 3, usuarios 1) |
| `docs/backend/sql/002_rollback.sql` | Deshace el 002 en orden inverso | Preparado, no ejecutado |

- `backups/` está en `.gitignore` (verificado con `git check-ignore`).
- ⚠ `restore.sql` contiene datos personales y el hash de la contraseña del admin. No subirlo ni compartirlo. Si se guarda una copia fuera del equipo, que esté cifrada.
- Los valores se exportan con `CAST(... AS CHAR)`: fechas, decimales y enums quedan con su valor exacto. Las columnas generadas no se exportan (la BD las recalcula).
- **No verificado:** restaurar `restore.sql`, porque requiere una BD vacía y crearla es un cambio que necesita autorización (ver §3, paso 3).

## 2. Respaldo del proveedor (complementario)
Revisa en la consola de TiDB Cloud (cluster → **Backup**) qué respaldos automáticos tiene tu plan y su retención. Si permite crear uno manual o restaurar a un momento anterior, hazlo justo antes de ejecutar el 002. No lo verifiqué: no tengo acceso a la consola.

## 3. Procedimiento para ejecutar el 002

1. **Sin escrituras:** que nadie use las apps ni el panel durante el cambio (hoy no hay solicitudes ni trabajadores).
2. **Precondición:** `npm run db:verificar-002` debe decir `0/84 … NO APLICADO`.
3. **Respaldo:** `npm run db:respaldo`. Anota el SHA-256 y comprueba los conteos de `resumen.json`.
4. **Ensayo:** `ENSAYO_DATABASE_NAME=queLimpiamos_proyecto npm run db:ensayo-002` (ver §6). Debe terminar en `ENSAYO OK` justo antes de aplicar.
5. **Ejecutar:** `npx prisma db execute --file ../../docs/backend/sql/002_detalle_solicitud_especialidades_invitaciones.sql`
6. **Verificar:** `npm run db:verificar-002` → `84/84 … APLICADO COMPLETO`. Los conteos de las tablas existentes deben ser iguales a los de `resumen.json`.
7. **Prisma:** copiar `docs/backend/sql/002_schema_prisma_previsto.prisma` a `prisma/schema.prisma` (ajustando el comentario de cabecera). Después `npx prisma db pull --print` (solo imprime, no sobrescribe) para comparar, `npx prisma validate`, `npx prisma generate` y `npm run typecheck`.

## 3b. Procedimiento para ejecutar el 003 (justo después del 002; solo con autorización)
1. `npm run db:verificar-002` → `84/84 … APLICADO COMPLETO`.
2. `npm run db:verificar-003` → `0/14 … NO APLICADO` y "se puede aplicar" (código 0). Si da código 3, **no aplicar**: el mensaje dice qué lo bloquea.
3. `npm run db:respaldo` (respaldo nuevo, con el 002 ya aplicado).
4. Ensayo: `ENSAYO_DATABASE_NAME=queLimpiamos_proyecto npm run db:ensayo-003` → `ENSAYO 003 OK`.
5. Ejecutar `docs/backend/sql/003_notificaciones_unicas_permisos_admin.sql`. Sus primeras sentencias son guardas: si fallan, no se cambió nada.
6. `npm run db:verificar-003` → `14/14 … APLICADO COMPLETO`.
7. **Prisma:** copiar `docs/backend/sql/003_schema_prisma_previsto.prisma` (incluye el 002) a `prisma/schema.prisma`, y correr `prisma generate` y `npm run typecheck`.
8. Reversión: `sql/003_rollback.sql`. Su guarda lo detiene si ya hay resoluciones.

## 4. Recuperación

| Situación | Qué hacer |
|---|---|
| **El 002 falló a la mitad** (el DDL no es transaccional: lo anterior a la sentencia fallida queda aplicado) | `npm run db:verificar-002` muestra qué existe. Opción A: corregir la causa y ejecutar solo las sentencias que faltan. Opción B: en `002_rollback.sql`, quitar las líneas de objetos que **no** existen (MySQL no tiene `DROP COLUMN IF EXISTS`) y ejecutarlo |
| **Hay que deshacer el 002 completo** | Respaldo nuevo (`db:respaldo`), luego `npx prisma db execute --file ../../docs/backend/sql/002_rollback.sql`, `db:verificar-002` → 0/84, y quitar del schema de Prisma los modelos y campos añadidos |
| **Datos existentes dañados** (muy improbable: el 002 no modifica filas existentes) | Crear una BD nueva vacía (p. ej. `queLimpiamos_restaurada`), ejecutar en ella el `restore.sql` del paso 3, comparar conteos con `resumen.json` y apuntar `DATABASE_NAME`/`DATABASE_URL` a esa BD. Nunca restaurar encima de la BD actual |

## 5. Riesgos del 002 y cómo se mitigan
| Riesgo | Mitigación |
|---|---|
| DDL a medias | Respaldo + `db:verificar-002` + rollback ordenado |
| Sintaxis no aceptada por TiDB (columna generada VIRTUAL con UNIQUE, FK por `ALTER`) | Funciones documentadas en MySQL 8 y TiDB 8.x. El ensayo del paso 4 lo confirma en el mismo motor |
| `MODIFY` de los enums `notificaciones.tipo` y `trabajadores.estado` | Solo agregan valores al final; ambas tablas tienen 0 filas |
| Pérdida de datos al revertir | El rollback borra solo objetos nuevos y falla a propósito si hay trabajadores en BAJA o notificaciones con los tipos nuevos |

## 6. Ensayo completo en BD temporal — `npm run db:ensayo-002`

Script: `src/scripts/ensayo-002.ts`. La lógica común está en `src/scripts/lib/`: `db-directa.ts`, `sql.ts`, `respaldo.ts` y `objetos-002.ts`, que comparten `db:respaldo` y `db:verificar-002`.

**Pasos que ejecuta:**
1. Toma una foto de producción (estructura y huella de datos de cada tabla) y genera el respaldo (`restore.sql`, con las tablas ordenadas por dependencias de FK).
2. Prepara la BD del ensayo y **restaura** el respaldo en ella.
3. Compara la BD del ensayo con producción (estructura normalizada y huellas SHA-256 de datos).
4. Corre la verificación previa: 0/84 y la precondición de `updated_at`.
5. Aplica el SQL 002 → 84/84. Comprueba que no se modificó ninguna fila existente y que los datos iniciales se insertaron (6 áreas, 5 extras, una fila de cálculo por servicio, 2 reglas, 8 parámetros).
6. Compara `prisma db pull --print` de la BD del ensayo con `sql/002_schema_prisma_previsto.prisma` (modelos, campos escalares, tipos y enums).
7. Genera el cliente Prisma **previsto** en `.ensayo/` (ignorado por git) y prueba con datos de prueba:
   - snapshot de la solicitud;
   - renombrar un área sin alterar lo que ya se pidió;
   - columna generada oculta en Prisma;
   - la BD impide dos aceptadas en una solicitud y reinvitar al mismo trabajador;
   - **dos aceptaciones simultáneas reales** (solo una gana);
   - idempotencia y AJUSTE en el libro;
   - no se puede borrar un trabajador con historial;
   - baja administrativa;
   - `updated_at` lo actualizan tanto Prisma como la BD;
   - tipos nuevos de notificación.
8. Borra los datos de prueba, aplica el **rollback** y comprueba que la BD queda **idéntica** a producción (estructura y datos).
9. Limpieza: borra la BD temporal (modo A) o la deja vacía (modo B).
10. Vuelve a comparar producción con la foto inicial: **debe seguir idéntica**.

El reporte queda en `backend/backups/<fecha>-ensayo/` (ignorado por git): `reporte.json`, `schema-introspeccionado.prisma`, `diferencias-schema.txt` y `restore.sql`. Este último contiene datos personales, así que no se debe compartir.

**Modos:**
- **A (por defecto):** crea `queLimpiamos_ensayo_<AAAAMMDDhhmmss>` y la borra al final. Requiere permiso `CREATE` y `DROP` de bases de datos.
- **B:** `ENSAYO_DATABASE_NAME=<bd>` usa una BD **ya existente y vacía**:
  - Solo se aceptan `queLimpiamos_shadow` o nombres que empiecen por `queLimpiamos_ensayo`, y nunca la de producción.
  - Si la BD tiene alguna tabla, el script **se niega a empezar**.
  - Al final borra solo las tablas que creó; la BD queda vacía y no se borra.

**Protecciones verificadas:** con `ENSAYO_DATABASE_NAME=queLimpiamos` o `=PIXAN` el script se detiene antes de conectarse ("no está permitida como BD de ensayo").

### Resultado del intento del 2026-11-24 (modo A)
- **Detenido en el paso 2:** el usuario de la app no tiene permiso para crear bases de datos (error 1044). `SHOW GRANTS` muestra que solo tiene `ALL PRIVILEGES` sobre `queLimpiamos`, `queLimpiamos_shadow` y `PIXAN`.
- **Producción intacta:** comprobado por el propio script (paso 10). Misma estructura y mismos datos en las 13 tablas.
- Se corrigió un fallo del script, que había impreso "ENSAYO OK" pese a detenerse. Ahora un error se registra como paso fallido.
- `queLimpiamos_shadow` existe y está **vacía** (0 tablas): candidata para el modo B **si el usuario la autoriza**.
- **Pendiente:** elegir dónde ensayar y volver a ejecutarlo. Ni el ensayo ni el SQL 002 se han aplicado en ninguna base.

### Resultado del ensayo del 2026-11-24 (modo B, `queLimpiamos_proyecto`) — SQL 002 v6
Comando: `ENSAYO_DATABASE_NAME=queLimpiamos_proyecto npx tsx src/scripts/ensayo-002.ts`. La BD la autorizó el usuario como base de pruebas; estaba vacía (verificado).

**Resultado final: ENSAYO OK, 29/29 pasos.** Reporte en `backend/backups/2026-11-24T18-07-14-909Z-ensayo/reporte.json`.

| Paso | Resultado |
|---|---|
| 1. Respaldo de producción | 13 tablas, 4 filas |
| 2–3. Restauración en la BD de ensayo | **Idéntica** a producción (estructura y datos) |
| 4. Verificación previa | 0/60 y precondición OK |
| 5. Aplicar el SQL 002 v6 | 70 sentencias, **60/60** |
| 5b. Filas existentes | Ninguna modificada (huellas iguales) |
| 5c. Datos iniciales | 6 áreas, 5 extras, 3 filas de cálculo, reglas CLIENTE y TRABAJADOR 24 h / 100 %, 4 parámetros |
| 6. Introspección vs schema previsto | **34 modelos y 38 enums coinciden** |
| 7. Pruebas con el cliente Prisma previsto | Todas OK (ver lista abajo) |
| 8. Rollback | 65 sentencias; la BD queda **idéntica** a producción |
| 9. Limpieza | `queLimpiamos_proyecto` vacía otra vez |
| 10. Producción | **Intacta** (misma estructura y datos que al empezar) |

Pruebas del paso 7:
- snapshot de la solicitud y renombrado de áreas;
- columna generada oculta en Prisma;
- la BD impide dos aceptadas y reinvitar al mismo trabajador;
- dos aceptaciones simultáneas reales → solo una gana;
- idempotencia y AJUSTE en el libro;
- no se puede borrar un trabajador con historial;
- baja administrativa con historial;
- varias franjas el mismo día;
- método de pago EFECTIVO por defecto;
- descuentos: código único sin distinguir mayúsculas y un uso por solicitud;
- Prisma ve los cambios de otras conexiones, antes **y** después de la prueba de concurrencia;
- `updated_at` lo actualiza Prisma (`@updatedAt`) y también la BD (`ON UPDATE`);
- tipos nuevos de notificación.

**Hallazgos del ensayo, corregidos en el script (no en el SQL):**
1. La primera corrida marcó `inmuebles` como distinta. Producción tiene una restricción **`chk_inmueble_pisos CHECK (pisos >= 1)`** que Prisma no muestra, y TiDB la reescribe con paréntesis extra al recrearla. Es la misma regla, así que la comparación ahora normaliza esos paréntesis. Hay que tenerlo en cuenta: el backend debe validar `pisos >= 1` (la BD lo rechaza).
2. Una prueba de `updated_at` comparaba la hora puesta por Prisma (reloj del servidor de la app, con redondeo) contra la puesta por la BD (`ON UPDATE`, reloj de la BD, truncada). Pueden coincidir en el mismo segundo; la diferencia de reloj medida es de unos 150 ms. Se separó en dos pruebas que no dependen del reloj. **Consecuencia para el backend:** no usar `updated_at` para ordenar eventos con precisión; para eso están los historiales y los `id`.

### Resultado del ensayo del 2026-11-24 — SQL 002 **v10** (vigente)
**ENSAYO OK, 43/43 pasos**, en `queLimpiamos_proyecto` (modo B). Reporte en `backend/backups/2026-11-24T21-54-37-846Z-ensayo/reporte.json`.
- 002 v10: 97 sentencias, **84/84** objetos. Ninguna fila existente modificada.
- Introspección = schema previsto (37 modelos, 50 enums).
- Rollback: 92 sentencias; la BD queda idéntica a producción (estructura y datos).
- BD de ensayo vaciada; producción intacta.
- Respaldos: los 10 archivos de `backups/` (incluido el original `2026-11-24T14-32-57-296Z/`) tienen el mismo SHA-256 antes y después.
- Prueba nueva (D59), con la misma transacción que usará la tarea periódica:
  - la solicitud EN_PROCESO y sin reportes queda REALIZADO (AUTOMATICO), con el pago presumido (`SISTEMA`), **una** comisión y **un** aviso `PAGO_EFECTIVO_PRESUMIDO`, aunque la tarea corra **dos veces a la vez**;
  - no se tocan la solicitud CONFIRMADO (el trabajador no la inició) ni la que tiene un reporte abierto: no se confirman ni se genera comisión;
  - si el cliente ya había registrado el pago, no se duplica la comisión;
  - el trabajador reporta "no recibí el efectivo" y el admin resuelve NO_PAGADO: pago ANULADO + AJUSTE. El historial conserva la comisión y el ajuste, y el servicio sigue REALIZADO.

### Resultado del ensayo del 2026-11-24 — SQL 002 **v9**
**ENSAYO OK, 42/42 pasos, a la primera**, en `queLimpiamos_proyecto` (modo B). Reporte en `backend/backups/2026-11-24T21-45-23-918Z-ensayo/reporte.json`.
- Restauración idéntica a producción.
- 002 v9: 97 sentencias, **84/84** objetos. Ninguna fila existente modificada (se comparan las columnas originales).
- Introspección = schema previsto (**37 modelos, 50 enums**).
- Rollback: 92 sentencias; la BD queda idéntica a producción.
- BD de ensayo vaciada; producción intacta.
- Respaldos: los 9 archivos de `backups/`, incluido el respaldo original `2026-11-24T14-32-57-296Z/`, tienen el mismo SHA-256 antes y después del ensayo.
- Pruebas nuevas de la v9:
  - **Pago en efectivo:** cliente y trabajador registran el pago **a la vez** → solo uno cambia `estado_pago` y hay **una** comisión de $150, con el servicio todavía EN_PROCESO y sin marca de "terminado". Una segunda comisión con otra clave es rechazada por la BD (P2002);
  - **Reportes:** reportes de ambas partes con evidencia de cada una. La confirmación automática (`… AND NOT EXISTS`) no cambia la solicitud. La resolución del admin la deja REALIZADO (`RESOLUCION_ADMIN`) con el pago ANULADO y la comisión corregida con un AJUSTE ligado a la resolución. Un segundo AJUSTE del mismo movimiento es rechazado (P2002). El historial conserva los dos movimientos y la solicitud no se puede borrar (P2003);
  - `LIBERACION_SALDO` y `AJUSTE` sin origen son rechazados (`chk_mov_referencia_obligatoria`);
  - parámetros con `DIAS_ESPERA_PAGO_ADEUDO = 0` y compensación pagada por la PLATAFORMA en el flujo de adeudo.

### Resultado del ensayo del 2026-11-24 — SQL 002 **v8**
**ENSAYO OK, 40/40 pasos**, en `queLimpiamos_proyecto` (modo B). Reporte en `backend/backups/2026-11-24T20-47-33-034Z-ensayo/reporte.json`.
- Restauración idéntica a producción.
- 002 v8: 89 sentencias, **78/78** objetos. Ninguna fila existente modificada (se comparan las columnas que ya existían).
- Introspección = schema previsto (**35 modelos, 42 enums**).
- Rollback: 84 sentencias; la BD queda idéntica a producción.
- BD de ensayo vaciada; producción intacta.
- Pruebas nuevas de la v8:
  - la comisión de un servicio no se registra dos veces aunque cambie la clave (`uq_mov_una_vez_por_solicitud`);
  - una `LIBERACION_SALDO` sin origen es rechazada (`chk_mov_liberacion_con_origen`);
  - **compensación:** el cliente y la plataforma intentan liberarla **a la vez** → solo una gana, la otra recibe P2002; un intento tardío (el cliente paga después) también es rechazado. Quedan exactamente 2 filas (un par);
  - **identidad:** la misma huella no puede estar en dos clientes ni en dos trabajadores, pero sí en un cliente y un trabajador; la INE aprobada queda con `archivo_eliminado_en`;
  - **confirmación:** automática sin pago (`pago_liberado_en` vacío), evidencia después, y dos liberaciones simultáneas del pago → solo una cambia la fila.
- Corridas anteriores del mismo día (corregidas):
  1. El 002 falló en `CREATE TABLE trabajador_movimientos`: TiDB rechaza un CHECK sobre una columna con FK (error 3823, aunque sea RESTRICT). Se cambió el CHECK para usar la columna generada. La BD de ensayo se vació y producción quedó intacta.
  2. 39/40: el paso 5b marcó `usuarios` porque la huella incluía las columnas nuevas (en NULL). Se corrigió la comparación, no el SQL.

### Resultado del ensayo del 2026-11-24 — SQL 002 **v7**
**ENSAYO OK, 31/31 pasos**, en `queLimpiamos_proyecto` (modo B). Reporte en `backend/backups/2026-11-24T19-01-14-184Z-ensayo/reporte.json`.
- Restauración idéntica a producción.
- 002 v7: 76 sentencias, **66/66** objetos; ninguna fila existente modificada.
- Introspección = schema previsto (**35 modelos, 40 enums**).
- Rollback: 71 sentencias; la BD queda idéntica a producción.
- BD de ensayo vaciada; producción intacta.
- Pruebas nuevas de la v7:
  - la BD rechaza un CLIENTE sin teléfono (`chk_usuario_cliente_telefono`);
  - adeudo con origen único, cobro en el siguiente servicio con las tres marcas de "realizado" y `COBRO_ADEUDO_CLIENTE` en el libro del trabajador que cobra.
- TiDB acepta `ADD CONSTRAINT … CHECK` y `DROP CONSTRAINT` (verificado al aplicar y revertir).
