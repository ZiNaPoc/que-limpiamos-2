# 13 — SQL 003: notificaciones únicas por evento (D60), plazo de reporte (D61) y permiso financiero de admin (D62)

- **Fecha:** 2026-11-24 · **Estado:** PROPUESTO y ensayado (resultado en §6). **NO aplicado en producción.**
- **Archivos:**
  - SQL: `sql/003_notificaciones_unicas_permisos_admin.sql`
  - Reversión: `sql/003_rollback.sql`
  - Prisma previsto: `sql/003_schema_prisma_previsto.prisma` (= previsto del 002 + 003; `prisma validate` OK: 38 modelos, 51 enums)
  - Scripts: `npm run db:verificar-003` (solo lectura) y `npm run db:ensayo-003`
- **Requiere el SQL 002 v10 aplicado completo.** No modifica el 002 (su SQL, rollback, schema previsto y ensayo siguen igual; el ensayo 002 sigue en 43/43).

## 1. Revisión de los registros existentes (antes de diseñar)
| Dónde | Qué hay | Efecto en el 003 |
|---|---|---|
| Producción `queLimpiamos` (lectura, 2026-11-24) | `notificaciones` 0, `usuarios` 1 (el admin), `solicitudes` 0. Las tablas del 002 **no existen** | Hoy `db:verificar-003` dice "NO APLICADO, bloqueado: el 002 no está aplicado" (sale con código 3) |
| Notificaciones que existan al aplicar | Cualquier número | **Se conservan todas.** Reciben `clave_evento = 'LEGADO:<id>'`; las demás columnas no cambian |
| Resoluciones o movimientos AJUSTE previos | Hoy no pueden existir (no hay rutas de resolución hasta la Fase 5, y el 002 no está en producción) | Si existieran, no hay permiso al que atribuirlos y **no se inventa historial**: el verificador lo marca como bloqueo y las guardas del propio SQL lo detienen **antes de cambiar nada** |

Recomendación: aplicar el 003 justo después del 002, antes de exponer las Fases 3 a 5.

## 2. D60 — Una notificación por (destinatario, evento)
- Columna nueva **`clave_evento VARCHAR(120) NOT NULL`** en `notificaciones` y `notificaciones_trabajador`. UNIQUE `(usuario_id, clave_evento)` y `(trabajador_id, clave_evento)`.
- **Convención:** `<TIPO>:<entidad>:<id>`, p. ej. `PAGO_EFECTIVO_PRESUMIDO:sol:123` o `REPORTE_RESUELTO:rep:45`.
  - Si un evento puede repetirse sobre la misma entidad (p. ej. una invitación que se reabre), el id es el de la fila que registra esa ocurrencia (historial, participación, movimiento, reporte o resolución).
  - Notificaciones manuales: `MANUAL:<uuid>`. Las que ya existían: `LEGADO:<id>`.
- Así:
  - el mismo evento **no** se notifica dos veces a la misma persona, aunque el código lo intente (la BD responde P2002 y el backend lo trata como "ya avisado");
  - el mismo evento **sí** puede avisar a varios destinatarios;
  - eventos distintos tienen claves distintas y se permiten.
- `NOT NULL`: ninguna notificación puede crearse sin declarar su evento.

## 3. D61 — 24 horas para reportar que no se recibió el efectivo
- Parámetro **`HORAS_PLAZO_REPORTE_PAGO = 24`** en `parametros_negocio`; el admin lo puede cambiar.
- Columna **`solicitudes.reporte_pago_hasta`**: al **presumirse el pago** (confirmación automática, `pago_registrado_por = SISTEMA`) se guarda `ese momento + 24 h`.
  - Se **guarda** en vez de recalcularse, para que coincida con lo avisado aunque el parámetro cambie después (probado: se cambia a 48 y la fecha no se mueve).
- **Notificación al trabajador** `PAGO_EFECTIVO_PRESUMIDO`, en la misma transacción y con clave `PAGO_EFECTIVO_PRESUMIDO:sol:<id>`, por lo que es única. Texto propuesto (≤ 255 caracteres, probado):
  > *Se registró el pago en efectivo de tu servicio y una comisión del 15 %. Si no recibiste el efectivo, repórtalo antes del {fecha y hora en Cancún} (24 h) en el servicio → Reportar → «No recibí el efectivo».*
- Regla del backend (Fase 4):
  - dentro del plazo, el trabajador puede abrir un reporte `PAGO_EN_DISPUTA`; ese reporte detiene la liberación y queda para el admin;
  - **después del plazo**, el backend responde 409 `PLAZO_VENCIDO` y la comisión queda firme.
- La app del trabajador debe mostrar la fecha límite y el botón «No recibí el efectivo» mientras `NOW() <= reporte_pago_hasta`.

## 4. D62 — Permiso específico para incidencias y movimientos financieros
| Objeto | Qué garantiza |
|---|---|
| **`admin_permisos`** (tabla nueva) | Permiso `GESTIONAR_INCIDENCIAS_FINANZAS` por admin, con **historial**: otorgar = fila nueva (`otorgado_por`, `otorgado_en`, `motivo`); revocar = llenar `revocado_por` y `revocado_en`. Nunca se borra. Solo puede haber **uno activo** por admin (columna generada `permiso_activo` + UNIQUE), y se puede volver a otorgar después de revocarlo |
| `solicitud_resoluciones.admin_id` **NOT NULL** + `ON DELETE RESTRICT` | Toda resolución tiene un admin y no se pierde quién fue (antes era opcional y `SET NULL`) |
| `solicitud_resoluciones.admin_permiso_id` **NOT NULL** + FK compuesta `(admin_permiso_id, admin_id) → admin_permisos (id, usuario_id)` | No se puede registrar una resolución **sin permiso** ni con el permiso de **otro** admin |
| CHECK `chk_mov_ajuste_con_resolucion` | Todo movimiento AJUSTE sale de una resolución, y por lo tanto de un admin con permiso |

**Lo que la BD no puede comprobar** (no hay CHECK entre tablas), y comprueba el backend en la **misma transacción** de la resolución:
```sql
SELECT p.id FROM admin_permisos p JOIN usuarios u ON u.id = p.usuario_id
 WHERE p.usuario_id = :admin_de_la_sesion AND p.permiso = 'GESTIONAR_INCIDENCIAS_FINANZAS'
   AND p.revocado_en IS NULL AND u.rol = 'ADMIN' AND u.estado_cuenta = 'ACTIVA'
   FOR UPDATE;   -- bloquea el permiso: una revocación simultánea espera
```
- Si no devuelve fila → **403 `PERMISO_REQUERIDO`**.
- `:admin_de_la_sesion` sale de `requireAdmin` (cookie verificada). **Nunca del body.**
- Se guarda `admin_permiso_id` = la fila encontrada.
- Probado en el ensayo: pasan el admin activo con permiso y otro admin con permiso; **no** pasan el admin sin permiso, el suspendido, el de permiso revocado ni un CLIENTE al que (por error) se le hubiera dado una fila de permiso.

**Quién otorga el permiso (pendiente D63):** el SQL no otorga permisos a nadie. Hasta decidirlo, **ningún admin** puede resolver incidencias financieras.

## 5. Reversión (`003_rollback.sql`)
- Empieza con una **guarda**: si hay resoluciones, se detiene antes de cambiar nada (deshacer el 003 borraría la prueba de con qué permiso se actuó).
- Quita en orden inverso: el CHECK y la columna generada de los movimientos; el permiso de las resoluciones (y `admin_id` vuelve a opcional con `SET NULL`); `admin_permisos`; el parámetro y `reporte_pago_hasta`; y las claves de evento. **Las notificaciones se conservan.**

> **2026-11-25 — Reemplazado por el SQL 003 v2** (`21_SQL_003_V2_RESENAS_REPORTES_MODERACION.md`). El v2 incluye A, B, C2 y C3 de este v1 sin cambios, y añade: D63 (propietario y no auto-otorgamiento), `MODERAR_CONTENIDO`, `REVISAR_DOCUMENTOS_IDENTIDAD`, las reseñas reconstruidas, los reportes con reportado, las evidencias y `moderacion_eventos`. **Quedan fuera del v2**, pendientes de decidir si entran: D64 (enum) y las tablas de documentos.

## 7. Cambios PROPUESTOS para una v2 del 003 (D63, D64 y D5): NO aplicados al SQL todavía
Como el 003 no está aplicado en ningún lado, conviene **reunir aquí** estos cambios (y los de documentos de `16` §5) en una sola versión y ensayarla una vez, en vez de abrir un SQL 004 después.
| Decisión | Cambio propuesto | Garantía en la BD |
|---|---|---|
| D63: solo el propietario otorga o revoca | `admin_permisos.permiso` suma **`ADMINISTRAR_PERMISOS`** (propietario). Se asigna **solo por script revisado** (`otorgado_por` NULL y `motivo` obligatorio). El backend exige que quien otorga o revoca tenga ese permiso vigente (con `FOR UPDATE`) | CHECK con columna generada: `otorgado_por` es obligatorio salvo en `ADMINISTRAR_PERMISOS`, y `revocado_en` exige `revocado_por` |
| D63: nadie se otorga un permiso a sí mismo | — | CHECK con columna generada: `otorgado_por <> usuario_id` (no se puede escribir directo: son columnas con FK, error 3823) |
| D63: auditoría | Las filas de `admin_permisos` ya son el historial (nunca se borran). La revocación se escribe una sola vez (`UPDATE … WHERE revocado_en IS NULL`) | FK RESTRICT; la revocación no se borra |
| D64: aviso cuando el cliente registra el pago | `notificaciones_trabajador.tipo` suma **`PAGO_EFECTIVO_REGISTRADO`** (al final del enum; el rollback lo revierte). Clave `PAGO_EFECTIVO_REGISTRADO:sol:<id>` | UNIQUE por evento (D60) |
| D64: plazo al registrarse | Sin columna nueva: `reporte_pago_hasta` también se llena cuando lo registra el CLIENTE. Se actualiza el comentario del SQL | Escritura única en el backend |
| D5 / D66 (D66 decidido) | Permiso **`REVISAR_DOCUMENTOS_IDENTIDAD`** (solo con él se ven los documentos de identidad; lo otorga el propietario) y tablas de eventos y accesos a documentos (`16` §5) | FK compuesta al permiso del mismo admin, igual que las resoluciones |

Texto propuesto del aviso D64 (≤ 255 caracteres):
> *El cliente registró que te pagó $1,000 en efectivo. Se registró una comisión de $150 (15 %). Si no lo recibiste, repórtalo antes del {fecha} (24 h) en el servicio → Reportar → «No recibí el efectivo».*

## 6. Resultado del ensayo (2026-11-24)
**ENSAYO 003 OK, 23/23 pasos**, en `queLimpiamos_proyecto`. Reporte en `backend/backups/2026-11-24T23-28-09-578Z-ensayo-003/reporte.json`.
1. Respaldo de producción, restauración idéntica y 002 v10 aplicado (84/84).
2. Verificación previa del 003: 0/14 y sin bloqueos.
3. **Datos heredados** (2 + 2 notificaciones y 1 comisión), como si el 002 ya estuviera en uso.
4. **Guardas:** con una resolución previa, o con un AJUSTE previo, el verificador lo bloquea y la primera sentencia del 003 falla por **violación del CHECK** (3819), antes de cambiar nada.
5. 003 aplicado: 23 sentencias, **14/14**, y el 002 sigue en 84/84.
6. **Ningún dato existente cambió.** Las 4 notificaciones heredadas conservan todo y reciben `LEGADO:<id>`; `HORAS_PLAZO_REPORTE_PAGO = 24`.
7. La introspección coincide con el schema previsto 003.
8. Pruebas con el cliente Prisma previsto:
   - **D60:** mismo evento y mismo destinatario → P2002; otro destinatario u otro evento → OK; sin clave → rechazado; dos inserciones **simultáneas** → solo una; una invitación reabierta usa otra clave y sí se notifica.
   - **D61:** al presumir el pago, plazo de exactamente 24 h guardado y aviso único con la fecha, menos de 255 caracteres y con "No recibí el efectivo". Un segundo aviso del mismo evento → P2002. Cambiar el parámetro a 48 no mueve la fecha ya avisada.
   - **D62:**
     - un solo permiso activo por admin; revocar y volver a otorgar conserva el historial (2 filas, 1 activa);
     - la comprobación del backend deja pasar solo al admin ACTIVO con permiso VIGENTE (rechaza: sin permiso, suspendido, revocado y CLIENTE con fila de permiso);
     - una resolución sin permiso o sin admin → error; con el permiso de **otro** admin → P2003; no se puede borrar ni el admin ni el permiso usado (P2003);
     - un AJUSTE sin resolución → CHECK; con resolución → OK.
   - Las garantías del 002 siguen activas.
9. **Rollback:**
   - su guarda lo detiene si hay resoluciones (3819);
   - limpias las pruebas, el rollback del 003 (17 sentencias) deja la BD **idéntica** al estado "002 + datos heredados" (notificaciones intactas);
   - el rollback del 002 la deja **idéntica a producción**.
10. BD de ensayo vaciada; producción intacta.

**Hallazgos de TiDB** (corregidos en las guardas; las dos primeras corridas fallaron sin tocar producción):
- un CHECK no puede usar la columna AUTO_INCREMENT (error 3818);
- `created_at IS NULL` sobre una columna NOT NULL se simplifica a una constante y se rechaza (3812).

Por eso las guardas usan `created_at < '1000-01-01'`, y el ensayo exige que fallen por violación (3819), no por otro error.
