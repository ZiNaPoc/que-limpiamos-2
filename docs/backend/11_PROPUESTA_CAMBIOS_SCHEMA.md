# 11 — Propuesta definitiva de cambios de schema (SQL 002 v10)

- **Fecha:** 2026-11-24 · **Fase:** previa a Fase 3
- **Estado:** PROPUESTA. **No ejecutada en producción.** Ensayo completo en `queLimpiamos_proyecto`: ver `12_RESPALDO_Y_RECUPERACION.md` §6.
- **Archivos:**
  - SQL: `sql/002_detalle_solicitud_especialidades_invitaciones.sql`
  - Reversión: `sql/002_rollback.sql`
  - Prisma previsto: `sql/002_schema_prisma_previsto.prisma` (`prisma validate` OK: **37 modelos, 50 enums, 14 `@updatedAt`**)
  - Scripts: `db:verificar-002`, `db:respaldo`, `db:ensayo-002`
- **BD verificada (solo lectura):** `queLimpiamos` en **TiDB Cloud Serverless v8.5.3** (compatible MySQL 8.0.11).
  - FKs activas, transacciones pesimistas, modo estricto, `utf8mb4_unicode_ci`.
  - `NOW()` en UTC, y Prisma lee y escribe `DATETIME` como UTC.
  - Los `updated_at` existentes ya tienen `ON UPDATE CURRENT_TIMESTAMP`.
  - `db:verificar-002` → **0/84**.
  - Filas: usuarios 1 (admin), servicios 3, el resto 0.

> **Las secciones 0, 0.8, 0.9 y 0.10 (v6 a v9) prevalecen** sobre lo que diga el resto del documento (escrito para la v5) cuando haya diferencias; entre ellas, manda la más reciente.

## 0. Cambios v5 → v6 (decisiones del usuario, 2026-11-24)

| Tema | Decisión | Cambio en el schema |
|---|---|---|
| Duración y precio | Base del servicio + minutos y precio por cuarto, baño, medio baño y piso; **provisional**. El admin edita la base y cada incremento desde su dashboard, y con eso cambia el cálculo | Sin cambio: `servicios.precio_base` / `duracion_estimada_min` + `servicio_calculo` (+ multiplicador por tipo, neutro). Las pantallas del admin son de la Fase 5 |
| **Pago en efectivo** | El 15 % de la empresa queda como **deuda** del trabajador | Nueva `solicitudes.metodo_pago` (EFECTIVO / TARJETA, default EFECTIVO) y movimiento `COMISION_EFECTIVO` (DEUDA +). Solo se guarda el método elegido; no se procesa ningún pago |
| Cuentas | Se conservan las tres: **Por cobrar** = ya ganó pero todavía no puede retirar · **Disponible** = ya puede retirar · **Deuda** = lo que debe a la plataforma | `COBRO_CONFIRMADO` → **`LIBERACION_SALDO`** (POR_COBRAR → DISPONIBLE cuando ya puede retirarse) |
| Cancelación tardía del cliente | Se le cobra el **100 %** | Regla inicial `CLIENTE, 24 h, PORCENTAJE, 100` |
| Cancelación tardía del trabajador | Se le cobra el **100 % del precio** (queda como deuda) | Regla inicial `TRABAJADOR, 24 h, PORCENTAJE, 100` |
| **Varias franjas por día** | Permitidas | `trabajador_horarios`: se quita el índice único `uq_horario_dia` y se crea `idx_horario_trabajador_dia` (no único). Único cambio a una restricción existente; la tabla tiene 0 filas |
| Desactivar o baja voluntaria | No se puede si tiene trabajos **CONFIRMADO o EN_PROCESO**. La baja es al instante y sin aprobación | Regla del backend |
| Reactivación | Si la baja fue **voluntaria**, el trabajador puede reactivarse. Si fue **administrativa**, solo el admin | Nueva **`trabajador_estado_historial`** (cada activación, desactivación, baja y reactivación, con actor y admin). Se quitó `trabajadores.baja_admin_id` (queda en el historial) |
| **Baja administrativa** | Se le cancela **todo**: los CONFIRMADO vuelven a la bolsa y los **EN_PROCESO pasan a CANCELADO** | Nuevo tipo de notificación al cliente `SERVICIO_CANCELADO_POR_PLATAFORMA` |
| **Descuentos** | El admin crea descuentos (porcentaje o monto fijo, vigencia, código opcional, monto mínimo, servicios a los que aplica, límite de usos total y por cliente, activar o desactivar). **La plataforma absorbe la pérdida.** El uso se **consume** aunque la solicitud se cancele | Nuevas **`descuentos`**, **`descuento_servicios`**, **`descuento_usos`** (UNIQUE por solicitud) + `solicitudes.precio_descuento_aplicado` + movimiento `COMPENSACION_DESCUENTO` |

### 0.1 Tablas nuevas de la v6
| Tabla | Columnas | Notas |
|---|---|---|
| `descuentos` | id, nombre, descripcion, tipo (PORCENTAJE/MONTO_FIJO), valor, codigo (NULL = automático; UNIQUE, sin distinguir mayúsculas), fecha_inicio, fecha_fin, monto_minimo, todos_los_servicios, limite_usos, limite_usos_por_cliente, activo, creado_por (FK usuarios SET NULL), timestamps | Índice de vigencia (activo, fecha_inicio, fecha_fin) |
| `descuento_servicios` | (descuento_id, servicio_id) PK, CASCADE | Se usa si `todos_los_servicios = 0` |
| `descuento_usos` | id, descuento_id (RESTRICT), solicitud_id (**UNIQUE**: un descuento por solicitud), cliente_id, codigo_aplicado, monto_descontado, created_at | Los límites se cuentan aquí. El uso no se libera al cancelar |
| `trabajador_estado_historial` | id, trabajador_id (RESTRICT), estado_anterior, estado_nuevo (ACTIVO/INACTIVO/BAJA), tipo (ACTIVACION / DESACTIVACION / BAJA_VOLUNTARIA / BAJA_ADMINISTRATIVA / REACTIVACION), actor (TRABAJADOR/ADMIN/SISTEMA), admin_id (FK usuarios SET NULL), motivo, created_at | Conserva todas las bajas y reactivaciones |

### 0.2 Precio con descuento y reparto
```
subtotal (precio de lista) = precio_base + precio_tamano + ajuste_tipo + Σ extras
descuento                  = según descuentos (porcentaje del subtotal o monto fijo; nunca mayor que el subtotal)
precio_estimado            = subtotal − descuento                       ← lo que paga el cliente
ganancia_trabajador        = subtotal × PORCENTAJE_TRABAJADOR / 100     ← 85 % SIN descuento
comision_plataforma        = precio_estimado − ganancia_trabajador      ← puede ser NEGATIVA (la plataforma absorbe)
```
Al aplicar un descuento se bloquea su fila (`SELECT … FOR UPDATE`) y se cuentan sus usos (total y por cliente), para que dos solicitudes simultáneas no superen el límite. Se valida vigencia, `activo`, monto mínimo (sobre el subtotal) y servicio.

### 0.3 Libro al terminar un servicio (REALIZADO)
| Método | Movimientos |
|---|---|
| **EFECTIVO** (el trabajador recibió `precio_estimado` en mano) | Si `precio_estimado > ganancia`: `COMISION_EFECTIVO` → DEUDA + (precio_estimado − ganancia), que normalmente es el 15 %. Si `precio_estimado < ganancia` (descuento grande): `COMPENSACION_DESCUENTO` → DISPONIBLE + (ganancia − precio_estimado), lo que la plataforma le debe. Su 85 % ya lo tiene en mano: se ve en el historial de la solicitud (`ganancia_trabajador`), no en el libro |
| **TARJETA** (cuando haya pasarela) | `GANANCIA_SERVICIO` → POR_COBRAR + ganancia; `LIBERACION_SALDO` → DISPONIBLE cuando ya se puede retirar |
| Retención | Cada vez que entra dinero a DISPONIBLE y hay deuda: `RETENCION_DEUDA` = mín(deuda, ingreso × 10 %) |

Ejemplo en efectivo sin descuento: precio 700, ganancia 595 → el trabajador cobra 700 en mano → `COMISION_EFECTIVO` DEUDA +105.
Ejemplo en efectivo con 20 % de descuento: subtotal 700, paga 560, ganancia 595 → `COMPENSACION_DESCUENTO` DISPONIBLE +35 (y si tiene deuda, se retiene el 10 % de esos 35).

### 0.4 Cancelaciones, bajas y reactivación (sustituye §4.4 y §4.5)
- **Cliente cancela CONFIRMADO con menos de 24 h:**
  - `cargo_cancelacion` = 100 % de `precio_estimado`.
  - El trabajador recibe su `ganancia_trabajador` como `COMPENSACION_CANCELACION` en POR_COBRAR, que pasa a DISPONIBLE con `LIBERACION_SALDO` cuando el cargo se cobre.
- **Trabajador cancela CONFIRMADO con menos de 24 h:**
  - `CARGO_CANCELACION` = 100 % de `precio_estimado` en DEUDA.
  - Su fila queda CANCELADA (definitivo) y la solicitud vuelve a la bolsa.
- **Desactivarse** (`estado = INACTIVO`) o **baja voluntaria:** 409 si tiene CONFIRMADO o EN_PROCESO. Si no, es inmediato: se cierran sus invitaciones pendientes (`TRABAJADOR_DADO_DE_BAJA` en la baja) y se registra en el historial.
- **Baja administrativa** (admin, con motivo), inmediata:
  - Sus CONFIRMADO vuelven a la bolsa: `SOLICITUD_DEVUELTA_A_BOLSA` al cliente.
  - Sus EN_PROCESO pasan a **CANCELADO** (actor ADMIN): `SERVICIO_CANCELADO_POR_PLATAFORMA` al cliente, sin cargo al cliente.
  - Todas sus filas PENDIENTE o ACEPTADA pasan a CANCELADA. Se registra en el historial. **Sin cargo automático al trabajador** (ver D47).
- **Reactivación:**
  - Voluntaria → el propio trabajador.
  - Administrativa → solo el admin.
  - Al reactivarse: `estado = ACTIVO`, se limpian `baja_*` y se registra `REACTIVACION`. No recupera las participaciones canceladas.

### 0.5 Disponibilidad con varias franjas (sustituye §4.3)
- Un día puede tener **varias franjas**. "Dentro de disponibilidad" = el intervalo [inicio, fin estimado] cabe **completo dentro de alguna** franja de ese día.
- El backend impide franjas que se solapen entre sí en el mismo día.

### 0.6 Pendientes v6
| ID | Pregunta |
|---|---|
| D46 | Cobro del cargo de cancelación a un cliente que paga en **efectivo**: sin pasarela no hay forma de cobrarlo, así que la compensación del trabajador queda en POR_COBRAR. ¿Cómo se cobrará? |
| D47 | Baja administrativa: ¿se le cobra algo al trabajador por los trabajos que se le cancelan? (Supuesto actual: no.) |
| D48 | ¿Se puede combinar más de un descuento en una solicitud? (Supuesto actual: **uno** por solicitud, `UNIQUE` en `descuento_usos`.) |
| D49 | Descuentos automáticos (sin código): si hay varios vigentes, ¿se aplica el mayor? (Supuesto actual: el que dé el mayor descuento) |
| D50 | Mientras no haya pasarela, ¿se debe **bloquear** el pago con TARJETA en la app y en el backend? (Hoy la app lo simula; no se debe simular) |
| D51 | ¿En qué momento pasa POR_COBRAR → DISPONIBLE ("ya puede retirar")? ¿Al confirmarse el cobro o tras un plazo? |

### 0.7 Resultado del ensayo (2026-11-24)
**29/29 OK (v6), 31/31 OK (v7), 40/40 OK (v8), 42/42 OK (v9) y 43/43 OK (v10, vigente: 84/84 objetos)** en `queLimpiamos_proyecto`: restauración idéntica, 002 aplicado, introspección = schema previsto, pruebas funcionales y de concurrencia, rollback idéntico, producción intacta. Detalle en `12_RESPALDO_Y_RECUPERACION.md` §6.
Hallazgo: producción tiene `CONSTRAINT chk_inmueble_pisos CHECK (pisos >= 1)` en `inmuebles`, que Prisma no muestra. El backend debe validar `pisos >= 1` antes de guardar, para dar un error claro.

## 0.8 Cambios v6 → v7 (decisiones del usuario, 2026-11-24) — prevalecen sobre lo anterior

| Tema | Decisión | Cambio en el schema / regla |
|---|---|---|
| **D46 — Adeudo del cliente en efectivo** | Si cancela tarde, el cargo queda como adeudo. En su **próximo servicio** lo paga en efectivo junto con el precio. Al trabajador que recibe ese extra se le registra como deuda, con el motivo. Ese dinero se le da al trabajador cuyo servicio se canceló | Nueva **`cliente_adeudos`** (PENDIENTE → EN_COBRO → COBRADO; origen único por solicitud), `solicitudes.adeudo_cobrado`, movimiento **`COBRO_ADEUDO_CLIENTE`** (DEUDA + del que cobra), notificaciones `ADEUDO_REGISTRADO` (cliente), `COBRO_ADEUDO_REGISTRADO` y `COMPENSACION_LIBERADA` (trabajador) |
| Cliente que nunca vuelve | Se considera pérdida | El adeudo se queda PENDIENTE; la compensación del trabajador afectado se queda en POR_COBRAR (ver D52) |
| Evitar cuentas nuevas para no pagar | Los clientes se registran por número y entregan la INE | `uq_usuarios_telefono` (ya existe) + nueva **CHECK `chk_usuario_cliente_telefono`**: un CLIENTE debe tener teléfono. El admin revisa la INE |
| D47 | La baja administrativa no genera cargo al trabajador | Regla del backend |
| D48 / D49 | Un solo descuento por solicitud; si varios aplican (automáticos o con código), se aplica el **mayor** | `descuento_usos.solicitud_id` UNIQUE (ya estaba) + regla del backend |
| D50 | Pago con tarjeta **bloqueado** hasta que exista pasarela | El backend rechaza `metodo_pago = TARJETA`; la app debe ocultar la opción (hoy la simula) |
| **D51 — Servicio realizado** (**sustituida por D54, §0.9**) | Solo cuando se confirma que se recibió el efectivo **y** ambas partes marcan el servicio como realizado en sus apps | Nuevas `solicitudes.efectivo_recibido_en` (lo confirma el trabajador), `trabajador_marco_realizado_en`, `cliente_marco_realizado_en`. La solicitud pasa a **REALIZADO** cuando están las tres (o las dos marcas, si algún día se paga con tarjeta) |

### Flujo completo de un adeudo
1. **Servicio A** (cliente C, trabajador TA, en efectivo, CONFIRMADO). C cancela con menos de 24 h:
   - `solicitudes.cargo_cancelacion` = 100 %.
   - Se crea el `cliente_adeudos` PENDIENTE (monto = cargo) y C recibe `ADEUDO_REGISTRADO`.
   - TA recibe `COMPENSACION_CANCELACION` (su 85 %) en **POR_COBRAR**.
2. **C crea el servicio B:**
   - Sus adeudos PENDIENTE pasan a EN_COBRO con `solicitud_cobro_id` = B, y `B.adeudo_cobrado` = suma de esos adeudos.
   - La app muestra a C y al trabajador TB el total a pagar en efectivo = precio de B + adeudo, con el motivo.
3. **Si B se cancela,** los adeudos vuelven a PENDIENTE (sin `solicitud_cobro_id`).
4. **B queda REALIZADO** (TB confirmó el efectivo y ambos marcaron):
   - TB: `COMISION_EFECTIVO` (15 % de B) y **`COBRO_ADEUDO_CLIENTE`** (monto del adeudo, con motivo "adeudo de la solicitud #A") en DEUDA, más la notificación `COBRO_ADEUDO_REGISTRADO`.
   - El adeudo pasa a COBRADO (`trabajador_cobro_id` = TB).
   - TA: `LIBERACION_SALDO` de su compensación (POR_COBRAR → DISPONIBLE) y la notificación `COMPENSACION_LIBERADA`. Si tiene deuda, se le retiene el 10 %.
5. **La plataforma** se queda con la diferencia entre el 100 % cobrado a C y el 85 % de TA.

### Pendientes v7 — RESUELTAS en v8 (ver §0.9)
| ID | Pregunta |
|---|---|
| D52 | Si el cliente nunca paga, ¿el trabajador afectado **pierde** su compensación (se queda para siempre en POR_COBRAR) o la plataforma se la paga igual? (Supuesto actual: la pierde, porque "se considera pérdida") |
| D53 | Para detectar una misma persona con otra cuenta, ¿guardamos algún identificador de la INE (p. ej. un *hash* de la clave de elector)? Hoy solo se revisa a mano; guardar ese dato implica tratar información personal sensible |
| D54 | Si una de las dos partes **no marca** el servicio como realizado, ¿se confirma solo tras cierto tiempo o queda en disputa para el admin? |

## 0.9 Cambios v7 → v8 (decisiones del usuario, 2026-11-24) — prevalecen sobre lo anterior

| Tema | Decisión del usuario | Cambio en el schema / regla |
|---|---|---|
| **D52 — Compensación si el cliente no paga** | Se aplica la compensación. Si el cliente pide otro servicio, se le cobra y ese dinero se le paga al trabajador; si no, la pérdida es de la empresa. **Cuidar que no haya pagos dobles** | `cliente_adeudos.compensacion_liberada_en` y `compensacion_pagada_por` (CLIENTE / PLATAFORMA). Parámetro `DIAS_ESPERA_PAGO_ADEUDO` (**30, provisional**, ver D55). Garantías en la BD contra pagos dobles (abajo) |
| **D53 — Identidad (INE)** | Se extrae el identificador de la INE, se normaliza y se guarda solo para cuestiones legales, **fuera de la BD**. La foto no se guarda para siempre | `usuarios.identidad_huella` y `trabajadores.identidad_huella` (CHAR(64), **UNIQUE**) + `identidad_registrada_en`. `documentos_cliente.archivo_eliminado_en` y `documentos_trabajador.archivo_eliminado_en` |
| **D54 — Confirmación del servicio** (sustituye D51 de §0.8) | Si el cliente confirma, se avanza y se paga al trabajador. Si solo confirma el trabajador, se usa su evidencia tras avisar al cliente. Si nadie confirma, se confirma solo, **pero sin pagar** hasta que haya evidencia o confirmación del cliente | `solicitudes.confirmacion_solicitada_en`, `aviso_evidencia_en`, `realizado_en`, `realizado_via` (CLIENTE / EVIDENCIA_TRABAJADOR / AUTOMATICO), `pago_liberado_en`. La evidencia usa la tabla existente `evidencias_solicitud`. Parámetros 30 / 15 / 30 min. Notificaciones nuevas (abajo) |

### Garantías contra pagos dobles (en la BD, no solo en el código)
| Garantía | Qué impide |
|---|---|
| `uq_mov_idempotencia` (ya estaba) | Registrar dos veces la misma operación con la misma clave |
| **`uq_mov_una_vez_por_solicitud`** (columna generada `clave_unica_solicitud`) | Un segundo `GANANCIA_SERVICIO`, `COMPENSACION_CANCELACION`, `COMISION_EFECTIVO`, `COMPENSACION_DESCUENTO` o `CARGO_CANCELACION` para la misma (solicitud, trabajador), **aunque el backend use otra clave** |
| **`uq_mov_una_liberacion`** (columna generada `clave_unica_liberacion`) | Liberar dos veces el mismo movimiento: cada mitad del par `LIBERACION_SALDO` apunta (`movimiento_relacionado_id`) al movimiento que libera, y solo puede haber una por cuenta |
| **`chk_mov_liberacion_con_origen`** | Una `LIBERACION_SALDO` sin movimiento de origen (que se saltaría la garantía anterior). Se define sobre la columna generada porque MySQL/TiDB no permiten un CHECK en una columna con FK (error 3823; lo detectó el primer ensayo v8) |
| `pago_liberado_en` / `compensacion_liberada_en` | El backend los escribe con `UPDATE … WHERE … IS NULL` dentro de la misma transacción que los movimientos: si dos procesos lo intentan a la vez, solo uno cambia la fila |

Las dos columnas generadas son VIRTUALES (como `aceptada_solicitud_id`) y llevan `@ignore` en Prisma: el backend nunca las escribe.

### Flujo de la compensación (sustituye los pasos 4–5 del flujo de §0.8)
1. **Cancelación tardía de A** (cliente C, trabajador TA): TA recibe `COMPENSACION_CANCELACION` (85 %) en POR_COBRAR — una sola vez por solicitud (BD). C queda con el adeudo PENDIENTE.
2. **Si C paga en su servicio B** (al liberarse el pago de B):
   - TB: `COBRO_ADEUDO_CLIENTE` en DEUDA, con el motivo. El adeudo pasa a COBRADO.
   - Si `compensacion_liberada_en` está vacío: `LIBERACION_SALDO` de la compensación de TA (POR_COBRAR → DISPONIBLE), `compensacion_pagada_por = CLIENTE` y notificación `COMPENSACION_LIBERADA`.
3. **Si pasan `DIAS_ESPERA_PAGO_ADEUDO` días sin pago:** la plataforma paga: `LIBERACION_SALDO` de TA y `compensacion_pagada_por = PLATAFORMA`. El adeudo **sigue PENDIENTE** (C todavía lo debe).
4. **Si C vuelve y paga después del paso 3:** el adeudo pasa a COBRADO y TB lo registra en DEUDA, pero **no se libera nada más** (la BD rechazaría una segunda liberación): ese dinero se queda en la plataforma y recupera la pérdida.
5. Si C nunca vuelve, la pérdida es de la empresa (TA ya cobró).

### Identidad con la INE
1. El cliente sube la INE (frente y reverso). El trabajador sube su identificación.
2. Al **aprobar**, el admin escribe el **CURP** que se lee en la INE (más adelante podría leerse automáticamente). El backend lo normaliza (mayúsculas, sin espacios ni guiones) y valida su formato de 18 caracteres.
3. Calcula la huella: **HMAC-SHA256** del CURP con una clave secreta `IDENTIDAD_HMAC_SECRETO` (variable de entorno; nunca en la BD). Si otra cuenta de la **misma audiencia** ya tiene esa huella, se rechaza (409): la persona debe usar su cuenta existente, con sus adeudos. Un cliente y un trabajador sí pueden ser la misma persona.
4. Guarda el CURP **cifrado fuera de la BD**, solo para cuestiones legales (dónde y por cuánto tiempo: D58).
5. **Borra las fotos** del almacenamiento y llena `archivo_eliminado_en` (también si se rechaza: se sube una nueva).
- Por qué el CURP: es único por persona, viene en la INE vigente y no cambia al renovarla (el CIC y el OCR sí cambian).
- La BD no puede revertir la huella sin la clave. Si algún día se cambia la clave, hay que recalcular las huellas con los CURP guardados fuera.
- El aviso de privacidad debe decir para qué se usa este dato.

### Confirmación del servicio (T = `fecha_hora_fin_estimada`)
| Situación | Qué pasa |
|---|---|
| **El cliente confirma** (en cualquier momento) | REALIZADO (`realizado_via = CLIENTE`) y se **libera el pago** |
| **Solo el trabajador confirmó** (marca + evidencia + efectivo recibido) | En T + 30 min (o al confirmar, si fue después) se avisa al cliente: `AVISO_CONFIRMACION_CON_EVIDENCIA` (`aviso_evidencia_en`). Si en **15 min** no confirma: REALIZADO (`EVIDENCIA_TRABAJADOR`) y se libera el pago |
| **Nadie confirmó en T + 30 min** | Se pide a ambos: `CONFIRMAR_SERVICIO_REALIZADO` al cliente y `SUBIR_EVIDENCIA_SERVICIO` al trabajador (`confirmacion_solicitada_en`). Si uno responde, se sigue el caso correspondiente |
| **Nadie responde en 30 min más** | REALIZADO (`AUTOMATICO`) y `SERVICIO_CONFIRMADO_AUTOMATICAMENTE` a ambos, **sin liberar el pago**. Se libera cuando el trabajador sube evidencia o el cliente confirma (`PAGO_SERVICIO_LIBERADO`) |

- **Liberar el pago** (una transacción): `UPDATE solicitudes SET pago_liberado_en = NOW() WHERE id = ? AND pago_liberado_en IS NULL`; si cambió 1 fila, se registran los movimientos del servicio (cada uno una sola vez, por la BD), se cobra el adeudo de B y se libera la compensación de TA (flujo de arriba).
- El backend necesita una **tarea periódica** (cada minuto) que revise los plazos. En Render: un intervalo dentro del servicio o un Cron Job. Fase 4.
- **Supuesto:** solo se confirma automáticamente un servicio **EN_PROCESO** (el trabajador lo inició). Un CONFIRMADO que nunca empezó no se confirma solo (ver D57).

### Pendientes v8 — RESUELTAS en v9 (ver §0.10)
| ID | Pregunta |
|---|---|
| D55 | ¿Cuántos días se espera el pago del cliente antes de que la plataforma pague la compensación? (Provisional: **30**; 0 = la plataforma paga al momento. El admin lo puede cambiar) |
| D56 | En la confirmación **automática** (nadie confirmó), ¿se registra ya la deuda del 15 % del efectivo al trabajador o también espera a la evidencia? (Recomendación: registrarla al confirmarse, para que no confirmar no sea una forma de evitar la comisión. El adeudo del cliente, en cambio, solo se da por cobrado al liberarse el pago) |
| D57 | ¿Qué pasa si el cliente dice que el servicio **no se hizo**, o si el trabajador nunca llega (un CONFIRMADO que no empieza)? |
| D58 | Dónde se guarda el CURP fuera de la BD (p. ej. un almacenamiento cifrado aparte) y por cuánto tiempo. Es infraestructura de la Fase 2; no cambia el SQL |

## 0.10 Cambios v8 → v9 y v10 (decisiones del usuario, 2026-11-24) — prevalecen sobre lo anterior

| Tema | Decisión del usuario | Cambio en el schema / regla |
|---|---|---|
| **D55 — Compensación** | Plazo **0 días**: la plataforma paga la compensación de inmediato y absorbe el costo. El adeudo del cliente sigue pendiente y se intenta recuperar cuando vuelva a contratar; si nunca vuelve, la pérdida es de la plataforma. La recuperación **no** genera un segundo pago al trabajador | `DIAS_ESPERA_PAGO_ADEUDO = 0`. `compensacion_pagada_por` queda en PLATAFORMA (CLIENTE sigue como valor posible si el admin sube el plazo) |
| **D56 — Comisión del 15 % en efectivo** | El cliente entrega el total al trabajador, que lo conserva. La deuda del 15 % se registra **en cuanto el pago queda registrado**, aunque nadie marque "terminado", y **una sola vez**. Se avisa al trabajador. Estado del servicio y estado del pago son **independientes**. Una disputa la revisa el admin; si no hubo cobro, se corrige con un movimiento, sin borrar historial | `solicitudes.estado_pago` (PENDIENTE / PAGADO / ANULADO), `pago_registrado_en`, `pago_registrado_por` (CLIENTE / TRABAJADOR / SISTEMA / ADMIN). Se quita `efectivo_recibido_en` (v8). `pago_liberado_en` se renombra **`ganancia_liberada_en`**. `COBRO_ADEUDO_CLIENTE` pasa a ser una vez por solicitud. Cada `AJUSTE` debe apuntar a su movimiento y solo puede haber uno por movimiento |
| **D57 — Reportes** | Aprovechar el apartado de reportes que ya existe. Se habilita desde la hora programada; ambas partes reportan (no se pudo completar, inasistencia, ubicación con problemas o falsa, otras). Al terminar el horario se indica si quedó terminado o no y se califica. Con reporte o desacuerdo se conserva la evidencia de ambas partes y **decide el admin**. Los movimientos definitivos respetan su resolución. Con un reporte pendiente **no** se confirma automáticamente | Nuevas **`solicitud_reportes`** y **`solicitud_resoluciones`**. `evidencias_solicitud` (existente) gana `aportada_por` y `reporte_id`. `trabajador_movimientos.resolucion_id`. `realizado_via` gana `RESOLUCION_ADMIN`. Notificaciones `REPORTE_REGISTRADO` y `REPORTE_RESUELTO` (cliente y trabajador) y `AJUSTE_REGISTRADO` (trabajador). La calificación usa `resenas` (ya existe, una por solicitud) |
| **D58 — CURP** | El CURP se guarda fuera de la BD principal, el tiempo que fije la política de privacidad. El HMAC-SHA-256 se calcula fuera de la BD; la BD guarda solo la huella, con UNIQUE; la clave queda protegida fuera | Sin cambio de schema (ya era así). Se aclara en el SQL que el CURP nunca se envía a la BD ni se calcula con una función SQL |

### Qué existía del "apartado de reportes"
- App del cliente: botón **Reportar** en `historial_screen.dart`, que hoy solo muestra "Esta opción estará disponible pronto". No hay tabla, endpoint ni modelo de datos. La app del trabajador no tiene apartado de reportes.
- Por eso **no** hay un mecanismo paralelo: ese botón se conecta a `solicitud_reportes` (Fases 3–4 y apps), y la app del trabajador necesita el suyo.
- La evidencia reutiliza `evidencias_solicitud` y la calificación reutiliza `resenas` (y la pantalla `rate_screen.dart` de la app del cliente).

### Cuatro estados independientes
| Eje | Dónde | Valores | Quién lo cambia |
|---|---|---|---|
| **Servicio** | `solicitudes.estado` + marcas de cada parte + `realizado_via` | PENDIENTE … EN_PROCESO → REALIZADO / CANCELADO | Las partes, la tarea periódica o una resolución |
| **Pago** | `solicitudes.estado_pago` | PENDIENTE → PAGADO (→ ANULADO) | Quien registra el pago, o una resolución |
| **Reporte** | `solicitud_reportes.estado` | ABIERTO → EN_REVISION → RESUELTO | Las partes lo abren; el admin lo revisa y resuelve |
| **Resolución** | `solicitud_resoluciones` | `resultado_servicio`, `resultado_pago` (NULL = no cambia ese eje) | Solo el admin |

Ninguno se deduce de otro: un servicio puede seguir EN_PROCESO con el pago ya PAGADO (y la comisión registrada), o quedar REALIZADO con el pago ANULADO.

### Registro del pago en efectivo (una transacción)
1. `UPDATE solicitudes SET estado_pago = 'PAGADO', pago_registrado_en = NOW(), pago_registrado_por = ? WHERE id = ? AND estado_pago = 'PENDIENTE'`.
2. Si cambió **1** fila:
   - `COMISION_EFECTIVO` en DEUDA = `precio_estimado − ganancia_trabajador` (el 15 % si no hay descuento; con descuento grande se aplica §0.3);
   - si `adeudo_cobrado > 0`: **un** `COBRO_ADEUDO_CLIENTE` con el total y el motivo, y esos adeudos pasan a COBRADO;
   - notificación `COMISION_EFECTIVO_REGISTRADA` al trabajador.
3. Si cambió **0** filas, ya estaba registrado: no se hace nada.
- **No espera** a que nadie marque "terminado". Si las dos partes lo registran a la vez, solo una cambia la fila; y si el backend lo intentara dos veces, la BD rechaza la segunda comisión. Las dos cosas están probadas en el ensayo.
- Ejemplo: el cliente paga $1,000 → el trabajador conserva $1,000 y su DEUDA sube $150 (−$150 hasta que la liquide).
- Advertencia para la app del trabajador (texto sugerido): *"El pago de este servicio ya quedó registrado. Aunque no marques el servicio como terminado, tu cuenta tendrá un adeudo de $150 (15 %) con QueLimpiamos."*

### Reportes y resolución del admin
- El backend acepta reportes desde `fecha_hora_programada` (antes responde 409).
- Tipos: `NO_SE_PUDO_COMPLETAR`, `INASISTENCIA`, `PROBLEMA_UBICACION`, `UBICACION_FALSA` (p. ej. el trabajador reporta la del cliente), `PAGO_EN_DISPUTA` y `OTRO`.
- Al terminar el horario: "terminado" es la marca de cada parte (`*_marco_realizado_en`); "no terminado" es un reporte `NO_SE_PUDO_COMPLETAR`. La calificación va en `resenas`.
- Al crear un reporte, el backend bloquea la fila de la solicitud (`SELECT … FOR UPDATE`), para no cruzarse con la tarea periódica. Mientras haya un reporte sin RESOLVER, no se confirma por evidencia ni automáticamente (`… AND NOT EXISTS (reporte sin resolver)`, probado) y no se libera la ganancia.
- **Resolución** (una transacción): se crea la fila en `solicitud_resoluciones`, los reportes pasan a RESUELTO con su `resolucion_id` y se aplica cada eje:
  - `resultado_servicio = REALIZADO` → REALIZADO (`RESOLUCION_ADMIN`) y se libera la ganancia. `NO_REALIZADO` → CANCELADO, sin ganancia.
  - `resultado_pago = NO_PAGADO` → `estado_pago = ANULADO`, un `AJUSTE` que corrige la comisión (y el `COBRO_ADEUDO_CLIENTE`, si lo hubo; esos adeudos vuelven a PENDIENTE). `PAGADO` → si estaba PENDIENTE, se registra el pago (`pago_registrado_por = ADMIN`) con su comisión.
  - Todos esos movimientos llevan `resolucion_id`. Otros cargos (p. ej. por inasistencia) no son automáticos: los decide el admin en la resolución.
- Si el admin cambia de criterio, registra **otra** resolución, y lo ya aplicado se corrige con un AJUSTE del AJUSTE. Nada se borra.
- Esto acota la regla anterior "el admin no interviene entre cliente y trabajador": sí resuelve reportes y disputas.

### D59 — Quién registra el pago en efectivo (RESUELTA, v10, 2026-11-24)
- **Cualquiera de las dos partes**, y con que una lo haga basta:
  - app del cliente: «Ya pagué en efectivo» → `pago_registrado_por = CLIENTE`;
  - app del trabajador: «Ya recibí el efectivo» → `TRABAJADOR`.
  - El backend cambia `estado_pago` y registra la deuda del 15 % **una sola vez**, aunque ambas lo marquen a la vez (probado en v9).
- **Si nadie lo registra:** al confirmar el servicio **automáticamente** se presume pagado (`pago_registrado_por = SISTEMA`) y se registra la comisión una sola vez, en la misma transacción. Solo aplica si:
  - el trabajador **inició** el servicio (`estado = EN_PROCESO`);
  - **no hay** reportes ni disputas sin resolver;
  - no hay cancelación ni incidencia que impida confirmar (cualquier estado distinto de EN_PROCESO queda fuera).
  - El trabajador recibe `PAGO_EFECTIVO_PRESUMIDO` (nuevo tipo de notificación), que le dice que lo reporte si no recibió el efectivo.
- **Protección:** si no recibió el efectivo, el trabajador lo reporta (`PAGO_EN_DISPUTA`), también después de la confirmación automática. El admin revisa las pruebas y mantiene la comisión o la anula: `resultado_pago = NO_PAGADO` → `estado_pago = ANULADO` + un `AJUSTE` que corrige la comisión. El movimiento original no se borra.
- Así, dejar de confirmar no evita la comisión, y tampoco se cobra por efectivo que no se recibió.

Tarea periódica, por cada solicitud vencida (una transacción; probado en el ensayo v10):
```sql
UPDATE solicitudes SET estado = 'REALIZADO', realizado_via = 'AUTOMATICO', realizado_en = NOW()
 WHERE id = ? AND estado = 'EN_PROCESO'
   AND NOT EXISTS (SELECT 1 FROM solicitud_reportes r
                    WHERE r.solicitud_id = solicitudes.id AND r.estado <> 'RESUELTO');
-- solo si cambió 1 fila:
UPDATE solicitudes SET estado_pago = 'PAGADO', pago_registrado_en = NOW(), pago_registrado_por = 'SISTEMA'
 WHERE id = ? AND estado_pago = 'PENDIENTE' AND metodo_pago = 'EFECTIVO';
-- solo si cambió 1 fila: COMISION_EFECTIVO + notificación PAGO_EFECTIVO_PRESUMIDO
```
Si dos instancias de la tarea procesan la misma solicitud a la vez, solo una la confirma; la otra no hace nada.

### Pendiente v9 (resuelta arriba)
| ID | Pregunta |
|---|---|
| D59 | ¿**Quién** puede registrar el pago en efectivo: el cliente ("ya pagué"), el trabajador ("recibí el efectivo") o cualquiera de los dos? Y si **nadie** lo registra y el servicio se confirma automáticamente, ¿se presume pagado (`pago_registrado_por = SISTEMA`, con comisión, disputable con un reporte) o queda pendiente? Supuesto actual: cualquiera de los dos; sin registro no hay comisión. Riesgo: si nadie lo registra, el trabajador se queda el efectivo sin comisión. El schema admite cualquiera de las opciones |

## 1. Decisiones incorporadas en v5

| Tema | Decisión del usuario | Cómo queda |
|---|---|---|
| **Duración** | Según el tipo de limpieza y el tamaño y características del inmueble; nada de 300 min universales; configurable | `servicios.duracion_estimada_min` = base de cada servicio + `servicio_calculo.minutos_por_*` + multiplicador por tipo de inmueble (`servicio_calculo_tipo_inmueble`) + minutos de cada extra. Se congela en `solicitudes.duracion_estimada_min` |
| **Traslado** | 60 min entre servicios, considerados al validar traslapes y aceptar | `parametros_negocio.MARGEN_TRASLADO_MIN = 60` |
| **Reparto** | Trabajador 85 %, plataforma 15 % | `PORCENTAJE_TRABAJADOR = 85`; se congela por solicitud (`porcentaje_trabajador_aplicado`, `ganancia_trabajador`, `comision_plataforma`) |
| **Deuda** | Retener el 10 % de las ganancias futuras, configurable; el trabajador elige cuánto de su saldo usar para pagarla; nunca descontar todo automáticamente | `PORCENTAJE_RETENCION_DEUDA = 10`; movimientos `RETENCION_DEUDA` y `ABONO_DEUDA_CON_SALDO` |
| **Libro** | Auditable, inmutable, correcciones con ajustes; el dinero queda como saldo en la plataforma | `trabajador_movimientos` (3 cuentas, solo INSERT, saldo resultante, idempotencia) |
| **Retiros** | Preparar la arquitectura (tarjeta vinculada, cheque, OXXO) sin implementar ni simular | Movimiento `RETIRO` + `referencia_externa`; diseño de tablas futuras en §7 |
| **Cancelación tardía del cliente** | El trabajador recibe su 85 % completo; se registra en el libro y en el historial; sin dinero ficticio | `COMPENSACION_CANCELACION` en la cuenta **POR_COBRAR** (§3.4) |
| **Disponibilidad** | Días y horarios configurables por el trabajador; por defecto se filtra lo que queda fuera; una preferencia permite verlo con advertencia; los traslapes (con 60 min) siempre se bloquean | `trabajador_horarios` (ya existe) + `trabajadores.mostrar_fuera_de_horario` |
| **Cancelación del trabajador** | La solicitud no vuelve a aparecerle ni se le puede reinvitar a esa misma; sí a futuras | `solicitud_trabajadores`: una fila por par, con `UNIQUE`; RECHAZADA y CANCELADA son definitivas (§3.3) |
| **Baja** | Voluntaria (la pide el trabajador) o administrativa (admin); no con trabajos EN_PROCESO; se conserva todo | `estado = BAJA`, `baja_en`, `baja_tipo`, `baja_motivo`, `baja_admin_id` |
| **Inmuebles** | Varios por cliente (casas, Airbnb), administrables en el perfil; sin duplicar en cada solicitud; cada solicitud conserva un snapshot | Snapshot en `solicitudes.*_aplicado` + `direccion_servicio`; `inmuebles.archivado_en` para "eliminar". **Se quitó `inmuebles.guardado`** |
| Ya decididas antes | Zona America/Cancun · máximo 5 invitaciones pendientes · admin sin intervención entre cliente y trabajador · registro y verificación del trabajador · especialidades declaradas · INE requerida · cargo con menos de 24 h · nombres históricos · `updated_at` | Sin cambios |

## 2. Cambios v4 → v5

| # | Cambio | Motivo |
|---|---|---|
| 1 | `servicio_tarifas` → **`servicio_calculo`** (precio **y** minutos por unidad) + nueva **`servicio_calculo_tipo_inmueble`** (multiplicadores de precio y duración por Casa, Oficina o Departamento) | La duración depende del servicio y del inmueble y es configurable |
| 2 | `servicios_extra.duracion_estimada_min`, `solicitud_extras.duracion_aplicada_min` | Los extras también suman tiempo |
| 3 | `solicitudes`: `duracion_estimada_min`, snapshot del inmueble (`inmueble_tipo_aplicado`, `habitaciones_aplicado`, `banos_aplicado`, `medios_banos_aplicado`, `pisos_aplicado`), `precio_ajuste_tipo_aplicado`, `porcentaje_trabajador_aplicado`, `ganancia_trabajador`, `comision_plataforma` | Historial y cotización conservados aunque se edite el inmueble o el catálogo; reparto 85/15 congelado |
| 4 | Nueva **`parametros_negocio`** (85, 10, 60, 5) | Valores configurables por el admin sin desplegar código |
| 5 | `solicitud_invitaciones` → **`solicitud_trabajadores`** con `origen` (INVITACION / BOLSA) y `updated_at` | Tomar una solicitud de la bolsa también deja una fila. Así la restricción "no reinvitar ni volver a mostrar tras rechazar o cancelar" queda **en la BD** (UNIQUE por par), y "una sola aceptada" cubre también la bolsa |
| 6 | Libro: cuentas `GANANCIAS / DEUDA` → **`POR_COBRAR / DISPONIBLE / DEUDA`**; tipos nuevos `COMPENSACION_CANCELACION`, `COBRO_CONFIRMADO`, `ABONO_DEUDA_CON_SALDO`, `PAGO_DEUDA_EXTERNO`, `RETIRO` (reemplaza `LIQUIDACION`); `porcentaje_aplicado` | Sin pasarela no hay cobros reales: lo ganado queda **por cobrar** (no es dinero ficticio disponible); abono elegido por el trabajador; retiros futuros |
| 7 | `trabajadores`: estado `ARCHIVADO` → **`BAJA`**, `archivado_en` → `baja_en`, nuevos `baja_tipo`, `baja_motivo`, `baja_admin_id`, `mostrar_fuera_de_horario` | Baja voluntaria o administrativa; preferencia de horario |
| 8 | `inmuebles.guardado` → **quitado**; nuevo `inmuebles.archivado_en` | Con el snapshot en la solicitud ya no hace falta crear inmuebles "no guardados"; borrar un inmueble usado lo bloquearía la FK existente (RESTRICT), así que "eliminar" = archivar |
| 9 | `solicitud_historial.actor` + `ADMIN` | Las bajas administrativas devuelven solicitudes a la bolsa |
| 10 | `notificaciones_trabajador.tipo` + `COMPENSACION_REGISTRADA`, `BAJA_REGISTRADA` | Avisos de la compensación y de la baja |

## 3. Explicación de cada objeto

### 3.1 Catálogo y parámetros (los administra el admin)
| Tabla | Columnas | Notas |
|---|---|---|
| `especialidades` | id, nombre UNIQUE, descripcion, estado, created_at, updated_at | Equipo o habilidad |
| `areas_limpieza` | id, nombre UNIQUE, orden, estado | Renombrable; 6 áreas iniciales |
| `servicios_extra` | id, nombre UNIQUE, descripcion, precio, **duracion_estimada_min**, estado, timestamps | 5 extras iniciales con su precio; minutos en 0 hasta definirlos |
| **`servicio_calculo`** | servicio_id PK/FK (CASCADE), precio_por_habitacion, precio_por_bano, precio_por_medio_bano, precio_por_piso, minutos_por_habitacion, minutos_por_bano, minutos_por_medio_bano, minutos_por_piso, updated_at | 1:1 con `servicios`; una fila en 0 por cada servicio existente |
| **`servicio_calculo_tipo_inmueble`** | (servicio_id, tipo_inmueble) PK, multiplicador_precio, multiplicador_duracion (default 1.00), updated_at | Sin fila = 1.00 |
| `reglas_cargo_cancelacion` | id, aplica_a, horas_antes, tipo, valor, estado, timestamps; UNIQUE (aplica_a, horas_antes) | 24 h para cliente y trabajador, valor 0 (monto pendiente) |
| **`parametros_negocio`** | clave PK, valor DECIMAL(10,2), descripcion, updated_at | `PORCENTAJE_TRABAJADOR` 85 · `PORCENTAJE_RETENCION_DEUDA` 10 · `MARGEN_TRASLADO_MIN` 60 · `MAX_INVITACIONES_PENDIENTES` 5 |

**Fórmulas** (en el backend, Fase 3; archivos `src/modules/cliente/solicitudes/precio.ts` y `duracion.ts`, marcados `// TODO` donde falten montos):
```
unidades_precio   = hab·precio_por_habitacion + baños·precio_por_bano + medios·precio_por_medio_bano + pisos·precio_por_piso
precio_tamano     = unidades_precio
ajuste_tipo       = (precio_base + precio_tamano) · (multiplicador_precio − 1)
precio_final      = precio_base + precio_tamano + ajuste_tipo + Σ extras.precio
ganancia_trabaj.  = precio_final · PORCENTAJE_TRABAJADOR / 100        comision = precio_final − ganancia
duracion_min      = round((servicios.duracion_estimada_min + Σ unidades·minutos_por_*) · multiplicador_duracion) + Σ extras.duracion_estimada_min
fin_estimado      = inicio + duracion_min
```
Todo se redondea a 2 decimales y el desglose se guarda en la solicitud. **Mientras el admin no configure los minutos por unidad, la duración sigue siendo la base de `servicios.duracion_estimada_min` (hoy 300 en los 3 servicios).** Hace falta cargar esos valores (§8, D34).

### 3.2 Relaciones de especialidades
`trabajador_especialidades` (las declara el trabajador; FKs RESTRICT) · `servicio_especialidades` · `extra_especialidades` (N:M; CASCADE hacia el servicio o el extra, RESTRICT hacia la especialidad).

### 3.3 Detalle e historia de cada solicitud
| Tabla | Columnas clave | Significado |
|---|---|---|
| `solicitud_areas` | PK (solicitud, área), nombre_aplicado | Áreas con su nombre de ese momento |
| `solicitud_extras` | PK (solicitud, extra), nombre_aplicado, precio_aplicado, duracion_aplicada_min | Extras congelados |
| `solicitud_especialidades` | PK (solicitud, especialidad), nombre_aplicado | Requisitos congelados |
| **`solicitud_trabajadores`** | id, solicitud_id, trabajador_id, **origen**, estado, motivo_cierre, created_at, respondida_en, updated_at, aceptada_solicitud_id (generada) | Participación de cada trabajador en cada solicitud |
| `solicitud_historial` | id, solicitud_id, estado_anterior, estado_nuevo, actor (CLIENTE/TRABAJADOR/ADMIN/SISTEMA), actor_id, motivo, created_at | Cada cambio de estado |

**`solicitud_trabajadores` — una fila por par (solicitud, trabajador)**, reutilizada:
| estado | origen | Se llega por | ¿Reutilizable para ese par? |
|---|---|---|---|
| PENDIENTE | INVITACION | El cliente lo invitó | — |
| ACEPTADA | INVITACION o BOLSA | Aceptó (máximo **una** por solicitud, garantizado por la BD) | — |
| RECHAZADA | INVITACION | Rechazó la invitación | **No** (definitivo) |
| CANCELADA | cualquiera | Canceló después de aceptar, o fue dado de baja | **No** (definitivo) |
| CERRADA | cualquiera | Otro aceptó, el cliente canceló, se pasó a automática o estaba ocupado (`motivo_cierre`) | Sí: si la solicitud vuelve a estar disponible, puede reabrirse (otra invitación o tomarla de la bolsa) |

`UNIQUE (solicitud_id, trabajador_id)` hace que, tras RECHAZADA o CANCELADA, la BD no admita otra fila para ese par. La regla "esa solicitud ya no aparece en su dashboard" se resuelve con esta misma tabla (§4.1).

### 3.4 `trabajador_movimientos` — libro de movimientos (inmutable)
Tres cuentas por trabajador:
| Cuenta | Significado | Hoy (sin pasarela) |
|---|---|---|
| **POR_COBRAR** | Lo ganado (servicios realizados y compensaciones) cuyo cobro al cliente **aún no está confirmado** | Aquí queda todo: se registra la obligación sin inventar dinero disponible |
| **DISPONIBLE** | Dinero real a su favor dentro de la plataforma; se podrá retirar | Se queda en 0 hasta que exista pasarela (`COBRO_CONFIRMADO`) |
| **DEUDA** | Lo que el trabajador debe (cargos por cancelar tarde) | Crece con `CARGO_CANCELACION` |

| tipo | Efecto | Cuándo |
|---|---|---|
| GANANCIA_SERVICIO | POR_COBRAR + 85 % (`porcentaje_aplicado` = 85) | La solicitud pasa a REALIZADO |
| COMPENSACION_CANCELACION | POR_COBRAR + 85 % | El cliente cancela una CONFIRMADO fuera de plazo |
| COBRO_CONFIRMADO | POR_COBRAR − y DISPONIBLE + (2 filas enlazadas) | **Futuro:** la pasarela confirma el cobro al cliente |
| RETENCION_DEUDA | DISPONIBLE − y DEUDA − (par; `porcentaje_aplicado` = 10) | Al pasar dinero a DISPONIBLE, si hay deuda: mín(deuda, monto × 10 %) |
| ABONO_DEUDA_CON_SALDO | DISPONIBLE − y DEUDA − (par) | El trabajador **elige** cuánto de su disponible usar (≤ disponible y ≤ deuda) |
| CARGO_CANCELACION | DEUDA + | El trabajador cancela fuera de plazo |
| PAGO_DEUDA_EXTERNO | DEUDA − (`referencia_externa`) | **Futuro:** paga con tarjeta u otro medio |
| RETIRO | DISPONIBLE − (`referencia_externa`) | **Futuro:** tarjeta vinculada, cheque, OXXO |
| AJUSTE | ± en cualquier cuenta, enlazado al movimiento corregido | Corrección autorizada |

Reglas:
- Toda escritura se hace con la fila del trabajador bloqueada (`SELECT … FOR UPDATE`).
- `saldo_resultante` es el saldo de esa cuenta después del movimiento.
- `clave_idempotencia` es UNIQUE, por ejemplo `GANANCIA:sol:123` o `COMPENSACION:sol:123`.
- Los saldos nunca quedan negativos (lo valida el backend).
- Nunca se hace UPDATE ni DELETE (TiDB no tiene triggers, así que lo garantiza el backend y se revisa en QA).

**Ejemplo con pasarela futura** (retención del 10 %): deuda 100 → servicio de $700 → POR_COBRAR +595 → cobro confirmado (POR_COBRAR −595, DISPONIBLE +595) → retención 59.50 (DISPONIBLE 535.50, DEUDA 40.50) → si el trabajador decide abonar 40.50 más de su disponible: DISPONIBLE 495, DEUDA 0.

### 3.5 Notificaciones
- **Cliente** (`notificaciones` + `leida_en`): SERVICIO_CONFIRMADO, CALIFICAR_SERVICIO, INVITACION_RECHAZADA, INVITACIONES_RECHAZADAS, SOLICITUD_DEVUELTA_A_BOLSA, DOCUMENTOS_APROBADOS, DOCUMENTOS_RECHAZADOS.
- **Trabajador** (`notificaciones_trabajador`): INVITACION_NUEVA, SOLICITUD_CANCELADA_POR_CLIENTE, COMPENSACION_REGISTRADA, CARGO_CANCELACION, GANANCIA_REGISTRADA, DOCUMENTOS_APROBADOS, DOCUMENTOS_RECHAZADOS, BAJA_REGISTRADA.

### 3.6 Columnas nuevas en tablas existentes (todas NULL o con DEFAULT)
| Tabla | Columnas |
|---|---|
| solicitudes (18) | servicio_nombre_aplicado · inmueble_tipo_aplicado, habitaciones_aplicado, banos_aplicado, medios_banos_aplicado, pisos_aplicado · duracion_estimada_min, fecha_hora_fin_estimada · notas · precio_base_aplicado, precio_tamano_aplicado, precio_ajuste_tipo_aplicado, precio_extras_aplicado · porcentaje_trabajador_aplicado, ganancia_trabajador, comision_plataforma · cargo_cancelacion · modo_eleccion (default AUTOMATICA) |
| inmuebles (1) | archivado_en |
| trabajadores (6 + enum) | estado_verificacion (default PENDIENTE), mostrar_fuera_de_horario (default 0), baja_en, baja_tipo, baja_motivo, baja_admin_id (FK usuarios SET NULL) · `estado` + `BAJA` |
| documentos_cliente / documentos_trabajador (4 c/u) | estado (default PENDIENTE), motivo_rechazo, revisado_en, revisado_por (FK usuarios SET NULL) |
| notificaciones (1 + enum) | leida_en (+ índice) · `tipo` + 5 valores |

## 4. Reglas de negocio para el backend

### 4.1 Qué ve cada trabajador en su dashboard
Una solicitud `PENDIENTE` sin trabajador aparece si se cumple todo esto:
1. El trabajador está ACTIVO y VERIFICADO.
2. Tiene todas las especialidades requeridas.
3. **No** tiene fila RECHAZADA ni CANCELADA para esa solicitud en `solicitud_trabajadores`.
4. **No** se cruza con sus trabajos CONFIRMADO o EN_PROCESO considerando 60 min de traslado (§4.2).
5. Está **dentro de su disponibilidad** (§4.3). Si `mostrar_fuera_de_horario = 1`, también se muestran las que quedan fuera, marcadas con `fueraDeHorario: true` y una advertencia. El punto 4 **siempre** aplica.

Para la lista de trabajadores elegibles que ve el cliente al elegir a mano, se aplican las mismas reglas desde el lado de la solicitud.

### 4.2 Traslapes (bloqueo obligatorio)
- Hay traslape si `inicio_nuevo < fin_existente + 60 min` **y** `fin_nuevo + 60 min > inicio_existente`. Ejemplos: 10–12 bloquea 11–13 y también 12:30–14; permite 13–15.
- Al aceptar (bolsa o invitación), en una transacción pesimista:
  1. `SELECT … FROM trabajadores WHERE id=:t FOR UPDATE` (serializa sus aceptaciones).
  2. Comprobar que no hay traslape.
  3. `UPDATE solicitudes … WHERE estado='PENDIENTE' AND trabajador_id IS NULL`.
  4. Upsert de su fila en `solicitud_trabajadores` a ACEPTADA. La BD impide una segunda aceptada.
  5. Cerrar las demás filas pendientes (`OTRO_TRABAJADOR_ACEPTO`) y las otras invitaciones pendientes de **ese trabajador** que ahora se traslapan (`TRABAJADOR_OCUPADO`).

### 4.3 Disponibilidad
- `trabajador_horarios` (ya existe): una franja por día de la semana (`dia_semana` 0 = domingo … 6 = sábado, como el panel) con `hora_inicio` y `hora_fin` en hora local de America/Cancun. Un día sin fila significa que no trabaja.
- **Dentro de disponibilidad:** el intervalo completo [inicio, fin estimado] del servicio cabe en la franja de ese día. El margen de traslado no cuenta aquí, solo en los traslapes.
- La preferencia `mostrar_fuera_de_horario` solo cambia lo que se **muestra**. Si acepta una solicitud fuera de horario, la app debe advertírselo, pero los traslapes se siguen bloqueando.

### 4.4 Cancelaciones
- **Cliente** (PENDIENTE o CONFIRMADO):
  - Si estaba CONFIRMADO y faltan menos de 24 h:
    - `cargo_cancelacion` según las reglas de cliente.
    - **Compensación al trabajador** = su `ganancia_trabajador` (85 %): movimiento `COMPENSACION_CANCELACION` en POR_COBRAR, notificación `COMPENSACION_REGISTRADA` e historial.
  - El trabajador recibe `SOLICITUD_CANCELADA_POR_CLIENTE` y las filas pendientes pasan a CERRADA (`CLIENTE_CANCELO`).
- **Trabajador** (CONFIRMADO):
  - Su fila pasa a **CANCELADA** (definitivo para ese par).
  - La solicitud vuelve a PENDIENTE sin trabajador, en modo AUTOMATICA, y se registra en el historial.
  - Si faltan menos de 24 h: `CARGO_CANCELACION` en DEUDA y notificación.
  - El cliente recibe `SOLICITUD_DEVUELTA_A_BOLSA`. La devolución de su dinero queda para cuando haya pagos (§7).

### 4.5 Baja del trabajador
- **Voluntaria** (la pide el trabajador desde su app) o **administrativa** (el admin, con motivo, queda en `baja_admin_id`).
- Si tiene trabajos EN_PROCESO, 409.
- En una transacción:
  1. `estado = BAJA`, más `baja_en`, `baja_tipo` y `baja_motivo`.
  2. Todas sus filas PENDIENTE o ACEPTADA en `solicitud_trabajadores` pasan a CANCELADA (`TRABAJADOR_DADO_DE_BAJA`).
  3. Sus solicitudes CONFIRMADO vuelven a la bolsa (actor `TRABAJADOR` si es voluntaria, `ADMIN` si es administrativa) **sin cargo**, y cada cliente recibe aviso.
  4. Notificación `BAJA_REGISTRADA`.
- Se conservan su historial, su libro y su deuda. No puede iniciar sesión.

### 4.6 Inmuebles del cliente
- **Perfil:** CRUD de inmuebles propios (alias, tipo, dirección, habitaciones, baños, medios baños, pisos). "Eliminar" = `archivado_en` (no se borra).
- **Primera solicitud:** captura el inmueble con opción "guardar" (crea la fila en `inmuebles`) o solo para esta solicitud (no crea fila: `inmueble_id = NULL`).
- **Siguientes:** elegir uno guardado (`inmueble_id`) u otro (guardarlo o no, igual que arriba).
- **Siempre:** se copian a la solicitud el tipo, las medidas y la dirección (`*_aplicado`, `direccion_servicio`). Editar o archivar después el inmueble no cambia solicitudes pasadas. Nunca se crea un inmueble por cada solicitud.

### 4.7 Sin cambios
Asignación por bolsa e invitaciones (máximo 5 pendientes), cliente con INE aprobada, documentos revisados por el admin, el admin no interviene entre cliente y trabajador, `updated_at` automático.

## 5. Compatibilidad con lo existente
- **BD:** solo agrega objetos; las filas existentes no cambian (lo comprueba el ensayo).
- **Backend actual:** hoy expone solo `/health` y `/health/db`, y los scripts de BD. El schema Prisma **activo** no se toca hasta aplicar el SQL. Ejecutar el SQL antes de actualizar Prisma no rompe nada:
  - Prisma solo lee las columnas que conoce.
  - Los valores nuevos de enum (`BAJA`, tipos de notificación) solo aparecerán cuando el código nuevo los escriba.
- **Panel web / apps Flutter:** no usan todavía el backend nuevo; sus contratos se definen en las Fases 2–5.

## 6. Precio y duración — dónde se configuran
- **Montos y minutos:** `servicios.precio_base` y `servicios.duracion_estimada_min` (base), `servicio_calculo` (por unidad), `servicio_calculo_tipo_inmueble` (por tipo), `servicios_extra.precio` y `duracion_estimada_min`, todo desde el catálogo del admin.
- **Porcentajes y margen:** `parametros_negocio`.

## 7. Fuera del 002 (preparado, sin implementar ni simular)
- **Cobros a clientes y devoluciones:** cuando haya pasarela. `COBRO_CONFIRMADO` pasará POR_COBRAR → DISPONIBLE; se cobrará el `cargo_cancelacion`.
- **Retiros** (tarjeta vinculada, cheque, OXXO). Diseño propuesto para entonces:
  - `trabajador_metodos_retiro`: solo tokens del proveedor, **nunca** números de tarjeta.
  - `retiros`: monto, método, estado SOLICITADO / EN_PROCESO / COMPLETADO / RECHAZADO, `referencia_externa` y el movimiento `RETIRO`.
- **Descuentos (D26):** diseño pendiente; se agregará `precio_descuento_aplicado`.

## 8. Por confirmar (v5) — RESUELTAS en v6, ver §0
| ID | Pregunta |
|---|---|
| ~~D34~~ ✅ provisional; el admin edita los valores | Los **minutos** reales (base por servicio, por habitación, baño, medio baño y piso, por extra, y el multiplicador por tipo de inmueble). Hasta configurarlos, la duración = base del servicio (hoy 300 min) |
| ~~D36~~ ✅ se conservan las 3 cuentas | Confirmar el diseño **POR_COBRAR**: las ganancias y compensaciones se registran pero no pasan a DISPONIBLE (retirables y utilizables para la deuda) hasta que exista pasarela y el cobro se confirme. Hoy, por tanto, ni la retención del 10 % ni el abono se ejecutan |
| ~~D37~~ ✅ el 15 % en efectivo queda como deuda | Pago **en efectivo** al trabajador (la app lo ofrece): ¿cómo se registra la comisión del 15 % que el trabajador cobró en mano? (¿deuda?) — para la fase de pagos |
| ~~D38~~ ✅ al cliente se le cobra el 100 % | Si la regla de cargo al cliente cobra menos que el 85 % que se compensa al trabajador, la diferencia la absorbe la plataforma. ¿Correcto? (el monto de la regla sigue pendiente) |
| ~~D39~~ ✅ varias franjas por día | ¿Un solo horario por día basta o hacen falta turnos partidos (p. ej. 8–12 y 15–19)? La tabla existente admite **una** franja por día |
| ~~D40~~ ✅ inmediata; reactivación según el tipo | Baja voluntaria: ¿surte efecto de inmediato al pedirla (supuesto actual) o la aprueba el admin? ¿Puede reactivarse una cuenta dada de baja? |
| ~~D26~~ ✅ descuentos diseñados (§0) | Diseño de descuentos |

## 9. Cómo ejecutar en producción (solo con autorización explícita)
Seguir `12_RESPALDO_Y_RECUPERACION.md` §3: verificar (0/66) → respaldo → ejecutar → verificar (66/66) → copiar el schema previsto a `prisma/schema.prisma` → `prisma generate` → `typecheck`.
