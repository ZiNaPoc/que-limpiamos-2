# 21 — SQL 003 v2: reseñas, reportes, evidencias, moderación, auditoría y permisos

- **Fecha:** 2026-11-25 · **Estado (actualizado):** **aplicado y probado SOLO en la BD LOCAL** (TiDB v8.5.3 en Docker, doc `22`) dentro de la Fase 3a. Ver §10. **NO aplicado** en el clúster remoto (producción ni `queLimpiamos_proyecto`).
- **Archivos:**

  | Archivo | Qué es |
  |---|---|
  | `sql/003_v2_notificaciones_permisos_resenas_reportes.sql` | La migración |
  | `sql/003_v2_rollback.sql` | La reversión |
  | `sql/003_v2_plantilla_asignacion_inicial_propietario.sql` | La asignación inicial; **bloqueada**, no ejecutable tal cual |
- **Reemplaza** al 003 v1 (`sql/003_notificaciones_unicas_permisos_admin.sql`). El v1 se ensayó (23/23) pero nunca se aplicó; se conserva como antecedente. Sus secciones A (D60), B (D61), C2 y C3 (D62) pasan **sin cambios** al v2.
- Reglas de negocio: `20`. Base: SQL 002 v10, que **no se modifica**.

## 1. Inspección real (solo lectura, 2026-11-25)
| Comprobación | Resultado |
|---|---|
| Motor | `8.0.11-TiDB-v8.5.3-serverless` (Community, compatible con MySQL 8.0) |
| CHECK | **Se aplican** (`tidb_enable_check_constraint = 1`) |
| FK | Activas (`foreign_key_checks = 1`, `tidb_enable_foreign_key = 1`) |
| Triggers | `SHOW TRIGGERS` vacío. Según la documentación oficial, TiDB **no soporta triggers, procedimientos almacenados ni eventos** |
| Privilegios | `REVOKE` debe coincidir exactamente: **no hay revocación parcial**. Los privilegios por columna llegan en **v8.5.6** (este clúster es 8.5.3) |
| `sql_mode` | `ONLY_FULL_GROUP_BY, STRICT_TRANS_TABLES, NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO, NO_AUTO_CREATE_USER, NO_ENGINE_SUBSTITUTION` |
| Cuenta del backend | `ALL PRIVILEGES` por base de datos, **sin** `GRANT OPTION` ni privilegios globales: **no puede crear usuarios ni otorgar permisos** |
| Producción | 13 tablas (el 002 y el 003 no están aplicados) |
| `resenas` en producción | **0 filas**. Columnas `id, solicitud_id, puntuacion_servicio, puntuacion_trabajador, comentario TEXT NULL, created_at`; `UNIQUE uq_resena_solicitud(solicitud_id)`; FK `fk_resena_solicitud` → `solicitudes(id) ON DELETE CASCADE`; sin CHECK |
| Quién depende de `resenas` | **Nadie**: ninguna FK apunta a ella, ninguna vista la menciona, y ni el 002, ni el 003 v1, ni el código del backend la usan. Solo el modelo Prisma `resenas` en `prisma/schema.prisma` |
| `evidencias_solicitud` en producción | 0 filas; `id, solicitud_id, archivo_url VARCHAR(255), descripcion, created_at`; FK a `solicitudes` `ON DELETE CASCADE`. El 002 le agrega `aportada_por` y `reporte_id` |
| `solicitud_reportes`, `admin_permisos`, `moderacion_eventos` | **No existen todavía**. La primera la crea el 002 y las otras dos el 003 |
| Columnas usadas por el v2 | `solicitudes.id/cliente_id/trabajador_id(NULL)/estado` (incluye `REALIZADO`), `usuarios.id/rol('CLIENTE','ADMIN')/estado_cuenta('ACTIVA','SUSPENDIDA')/correo`, `trabajadores.id`; `solicitudes.realizado_en` (la crea el 002). Collation de todas: `utf8mb4_unicode_ci` |

## 2. Diferencias entre la propuesta anterior y la estructura real
| Propuesta (`20` v1) | Realidad | Cómo queda en el v2 |
|---|---|---|
| `resenas` con `autor_rol`, `puntuacion` y `comentario` opcional | La tabla real tiene `puntuacion_servicio` y `puntuacion_trabajador`, con UNIQUE por solicitud | Se **reconstruye** (decidido): se validaron tipos y nombres contra `solicitudes`, `usuarios` y `trabajadores` |
| `comentario VARCHAR(500)` | El límite no está confirmado | `TEXT NULL`, como la tabla real; **sin límite** |
| Reportado "deducible" | `solicitud_reportes` (002) solo guarda **quién reporta** | Se agregan `reportado_cliente_id` y `reportado_trabajador_id`, con CHECK de coherencia |
| Fotos de reportes: tabla propia | `evidencias_solicitud` ya existe y el 002 le da `reporte_id` | Se **reutiliza** y se le agregan metadatos y borrado lógico |
| Límite de 8 MB por foto | El almacenamiento acepta hoy **5 MiB** por defecto (configurable de 1 a 20) y no limita por propósito | No va en el SQL. **La Fase 3a debe** agregar un límite por propósito (8 MB para los reportes) y el control de 5 fotos y 16 MB |
| `moderacion_eventos` protegido "por la BD" | Sin triggers, y la cuenta del backend tiene `ALL` | Protección por la aplicación más permisos por tabla (§6) |
| D63 "propietario" | `admin_permisos` del v1 no lo distinguía | Nuevos `ADMINISTRAR_PERMISOS` y `origen`, más CHECK de no auto-otorgamiento |

## 3. Inventario del v2 (lo que cambia respecto al 002 v10)
| Sección | Tabla | Objetos |
|---|---|---|
| 0 | `solicitud_resoluciones`, `trabajador_movimientos`, `solicitud_reportes` | 3 guardas (CHECK temporal: se agrega y se quita) |
| A (= v1) | `notificaciones`, `notificaciones_trabajador` | `clave_evento` NOT NULL + UNIQUE por destinatario |
| B (= v1) | `solicitudes`, `parametros_negocio` | `reporte_pago_hasta`; parámetro `HORAS_PLAZO_REPORTE_PAGO = 24` |
| C1 (cambia) | **`admin_permisos`** (nueva) | Enum de 4 permisos, `origen`, `motivo_revocacion`, 3 columnas generadas, 4 CHECK, 3 FK, UNIQUE de permiso activo y `(id, usuario_id)` |
| C2–C3 (= v1) | `solicitud_resoluciones`, `trabajador_movimientos` | `admin_id NOT NULL`, permiso usado (FK compuesta); AJUSTE exige resolución |
| D (nuevo) | **`resenas`** (reconstruida), `solicitudes` | `DROP TABLE resenas`; en `solicitudes`: `UNIQUE (id, cliente_id)` y `(id, trabajador_id)`; tabla nueva con 4 CHECK, 3 FK y 6 índices |
| E (nuevo) | `solicitud_reportes` | 5 columnas, 2 generadas, 3 índices, 3 FK, 3 CHECK |
| F (nuevo) | `evidencias_solicitud` | 5 columnas, 1 generada, 1 índice, 1 FK, 2 CHECK |
| G (nuevo) | **`moderacion_eventos`** (nueva) | 1 generada, 3 CHECK, 4 FK, 4 índices |

## 4. Orden de ejecución y dependencias
1. **002 v10 completo (84/84)**: crea `solicitud_reportes`, `solicitud_resoluciones`, `trabajador_movimientos`, `parametros_negocio`, `notificaciones_trabajador`, `solicitudes.realizado_en`, y `reporte_id`/`aportada_por` en las evidencias.
2. **003 v2**, en el orden del archivo: 0 → A → B → C → D → E → F → G.
   - C1 va **antes** de C2 y de G, porque las FK compuestas apuntan a `admin_permisos (id, usuario_id)`.
   - D2 (claves en `solicitudes`) va **antes** de D3, porque las FK compuestas de `resenas` las necesitan.
   - G va al final: apunta a `admin_permisos`, `resenas` y `solicitud_reportes`.
3. **Después, y por separado**, la plantilla de asignación inicial, solo cuando D63a esté resuelta (§5).
4. **Fase 3a:**
   - actualizar `prisma/schema.prisma` con el schema previsto del v2 (falta escribirlo) y regenerar el cliente con la CLI. Nunca se edita `generated/` a mano;
   - después, el código.

## 5. Permiso `MODERAR_CONTENIDO` y propietario (D63)
- **Propietario** = quien tiene `ADMINISTRAR_PERMISOS` vigente.
- **Solo el propietario** otorga y revoca `MODERAR_CONTENIDO`. Las comprobaciones de la BD y del backend son:

  | Comprobación | Dónde |
  |---|---|
  | Quien otorga tiene `ADMINISTRAR_PERMISOS` vigente, ambas cuentas son `ADMIN` y están `ACTIVA` (`SELECT … FOR UPDATE` en la misma transacción) | Backend |
  | Nadie se otorga un permiso a sí mismo (`regla_otorgamiento`) | **BD** (CHECK) |
  | Un solo permiso activo igual por persona (`uq_permiso_activo`) | **BD** (UNIQUE) |
  | Revocar exige fecha y autor (`regla_revocacion`) | **BD** (CHECK) |
  | Las filas no se borran: son el historial (FK RESTRICT desde las resoluciones y desde `moderacion_eventos`) | **BD** (FK) |
- **Asignación inicial auditada:** `origen = 'ASIGNACION_INICIAL'`, `otorgado_por = NULL`, motivo obligatorio (CHECK) y fecha automática. La plantilla:
  - exige el **id y el correo** confirmados, rol `ADMIN`, cuenta `ACTIVA`, correo que no sea de dominio `.demo`/`.test`, y que no haya otro propietario vigente;
  - comprueba que cada inserción afecte **exactamente 1 fila** antes del `COMMIT`.
- **Qué falta para ejecutarla:**
  1. que el usuario identifique por escrito la cuenta real (D63a); **no** se asume el ID 1;
  2. el 003 v2 aplicado;
  3. un respaldo nuevo;
  4. reemplazar los marcadores, revisar y ejecutar en una sola sesión.

  **No se asignó el permiso a ninguna cuenta.**

## 6. Protección del historial de moderación (sin triggers)
| Capa | Qué la protege | Estado |
|---|---|---|
| 1. Aplicación | El repositorio de moderación solo expone `create` y lecturas de `moderacion_eventos` (sin `update`, `delete` ni `upsert`). No hay rutas para editarlo. Una prueba estática (como `importaciones.test.ts`) falla si aparece una escritura distinta de `create` sobre ese modelo. Cambio y evento van en la **misma transacción** | Diseño, Fase 3a |
| 2. Base de datos | Las FK RESTRICT impiden borrar el admin, el permiso, la reseña o el reporte con historial. Los CHECK exigen motivo, objeto y JSON válidos | En el SQL v2 |
| 3. Permisos de BD | Hoy la cuenta del backend tiene `ALL` sobre la BD, así que **podría** hacer `UPDATE`/`DELETE` en la auditoría. Sin revocación parcial, la única forma de impedirlo es una **cuenta nueva para la aplicación** con permisos **por tabla**:<br>• `SELECT, INSERT, UPDATE, DELETE` en las tablas normales;<br>• solo `SELECT, INSERT` en `moderacion_eventos`;<br>• `SELECT, INSERT, UPDATE` en `admin_permisos` (la revocación es un UPDATE; sin privilegios por columna hasta 8.5.6).<br>La crea el **usuario raíz del clúster** desde la consola de TiDB Cloud, porque la cuenta actual no puede. Las migraciones siguen con la cuenta actual. Cada tabla nueva exige su `GRANT` | **Propuesta: requiere tu autorización y acceso a la consola. No se hizo** |
| 4. Detección (opcional) | Una columna `huella` = SHA-256 de la huella anterior + el contenido del evento, que delata alteraciones hechas por fuera. No se incluyó en el SQL para no complicarlo sin decisión | Opcional |

## 7. Operaciones destructivas y riesgos
| Operación o riesgo | Impacto | Mitigación |
|---|---|---|
| **`DROP TABLE resenas`** (D1) | Se pierden **todas** las reseñas antiguas. El 2026-11-25 eran **0** | Decidido por el usuario. Respaldo nuevo antes; el verificador previo debe informar `COUNT(*)` |
| Rollback | Borra `admin_permisos` (con la asignación del propietario), `moderacion_eventos`, las reseñas nuevas y los datos de reportado y evidencias | Guardas que lo detienen si hay datos; respaldo antes |
| DDL no transaccional | Un fallo a mitad deja el v2 parcial | Respaldo, verificador antes y después, rollback recortado a lo que existe |
| `resenas` pasa de `ON DELETE CASCADE` a `RESTRICT` | No se puede borrar físicamente una solicitud que tenga reseñas | Coherente con el 002 (reportes y resoluciones ya son RESTRICT) |
| FK compuesta `(solicitud_id, trabajador_id)` | Con una reseña existente, `solicitudes.trabajador_id` **no se puede cambiar** | Las reseñas solo existen tras `REALIZADO`; confirmar que ningún flujo (p. ej. una resolución) cambie al trabajador después |
| `JSON_TYPE` dentro de un CHECK | **No ensayado en TiDB** | Primer punto del ensayo local; si TiDB lo rechaza, se quita ese CHECK (el tipo `JSON` ya valida el formato) |
| Guarda de reportes del v2 | Si hay reportes antes de aplicar, se detiene | Intencional: no se inventa el "reportado" |
| Scripts del 003 v1 (`verificar-003`, `ensayo-003`, `objetos-003`, schema Prisma previsto) | Describen el **v1** y no sirven para el v2 (p. ej. `origen` NOT NULL) | **Pendiente:** actualizarlos antes de cualquier ensayo |
| Cambios del `13` §7 que **no** están en el v2 | D64 (`PAGO_EFECTIVO_REGISTRADO` en el enum de `notificaciones_trabajador`) y las tablas de documentos de identidad (`16` §5) | **Decisión:** sumarlos a este v2 antes de aplicar (una sola migración) o dejarlos para otro SQL |

## 8. Cómo probarlo de forma segura en un entorno local aislado (no se hizo)
1. **TiDB local de la misma versión**, gratis y oficial, sin tocar el clúster compartido: `tiup playground v8.5.3`, o la imagen Docker `pingcap/tidb:v8.5.3`. Descargarlo requiere tu permiso.
2. Ajustar los scripts de ensayo para ese host. Hoy `db-directa.ts` **exige TLS**, que el TiDB local no tiene, y usa el host del `.env`. Hacen falta variables **separadas** (p. ej. `ENSAYO_HOST`/`ENSAYO_PORT`/`ENSAYO_TLS=false`), **sin tocar `DATABASE_URL`** ni la conexión del backend.
3. Cargar en local **solo la estructura** de producción (`respaldo.ts`/`ddlDeTabla` ya la leen en modo solo lectura), sin datos reales.
4. Aplicar el 002 v10 y verificar 84/84. Aplicar el 003 v2 con el verificador antes y después.
5. Pruebas mínimas del SQL:
   - **CHECK:** puntuación 0/6 → 3819; reseña del mismo lado dos veces → 1062; reseña con un cliente que no es el de la solicitud → 1452; reporte `CLIENTE:1010` → 3819; eliminación sin admin → 3819; auto-otorgamiento → 3819; asignación inicial sin motivo → 3819; evento sin motivo, con objeto doble o con JSON que no sea objeto → 3819;
   - **FK:** borrar una reseña o un reporte con eventos → 1451; evento con el permiso de otro admin → 1452;
   - **Guardas:** con reportes previos, el v2 se detiene en el paso 0;
   - **Plantilla:** con un admin `.demo` inserta 0 filas; con un propietario ya vigente, 0 filas.
6. Rollback: con datos → se detiene; vacío → deja la BD **idéntica** a "002 aplicado" (comparando la estructura). Después, el rollback del 002 la deja idéntica a producción.
7. Destruir el contenedor o el playground. Nada toca la nube.

## 9. Pendientes antes de aplicar
- Tu revisión de este SQL y de las decisiones X1–X8 de `20` §10. **X0 está resuelta** (el admin con `MODERAR_CONTENIDO` ve al autor): no cambia el SQL, porque `resenas` ya guarda `autor_rol` y las dos partes, y la restricción la aplica la API.
- Decidir si D64 y las tablas de documentos (`16` §5) entran en este v2.
- Actualizar `objetos-003`, `verificar-003`, `ensayo-003` y el schema Prisma previsto al v2, y ensayarlo en local (§8).
- La cuenta de BD por tabla (§6, capa 3): decisión y acción en la consola.
- D63a: identificar al propietario. Hasta entonces, la plantilla no se ejecuta.
- **Autorización explícita** para aplicar el 002 y el 003 v2 en producción.

## 10. Ejecución en la BD LOCAL y cambios de la Fase 3a (2026-11-25)
- **Dónde:** contenedor `quelimpiamos-tidb` (`pingcap/tidb:v8.5.3`, solo en `127.0.0.1:4000`). El esquema se arma **solo con archivos del repositorio**: `000_estructura_produccion.sql` (las 13 sentencias `CREATE TABLE` de producción, extraídas del respaldo lógico del 2026-11-24 **sin ninguna fila**) → 002 v10 → 003 v2. **168 sentencias, sin errores.**
- **Cambio respecto a la versión revisada:** `moderacion_eventos` también audita **permisos** (`entidad = PERMISO`, `permiso_id`; operaciones `OTORGAR`, `REVOCAR`, `ASIGNACION_INICIAL`).
  - La asignación inicial no tiene actor (`admin_id NULL`), y eso solo se admite para esa operación (CHECK `chk_mod_actor`).
  - Hay un CHECK de operación válida por entidad (`chk_mod_operacion`).
  - La plantilla del propietario inserta también sus eventos.
- **Hallazgos de TiDB** (verificados en el TiDB local):
  - `tidb_enable_check_constraint` es **solo GLOBAL** y cada conexión la lee al abrirse. Un CHECK creado en una conexión que la tiene apagada **se descarta en silencio**: la primera construcción quedó sin ningún CHECK. Ahora `construirBdLocal` exige que la conexión ya la tenga activa. En producción está activa (=1).
  - Los CHECK se listan en `information_schema.TIDB_CHECK_CONSTRAINTS`, no en `TABLE_CONSTRAINTS`. Resultado: `admin_permisos` 4, `moderacion_eventos` 5, `resenas` 4, `solicitud_reportes` 3, `evidencias_solicitud` 2.
  - El CHECK con `JSON_TYPE` funciona: un JSON que no es objeto se rechaza.
- **La BD rechaza** (probado contra el TiDB local):
  - puntuación fuera de rango;
  - reseña duplicada, también si estaba eliminada;
  - auto-otorgamiento y asignación inicial sin motivo;
  - eventos sin motivo, sin objetivo, sin actor, con una operación de otra entidad o con el permiso de otro admin (FK compuesta);
  - el borrado físico de una reseña, un permiso o un admin con historial (FK RESTRICT).
- **Bug encontrado por las pruebas y corregido:** las fechas de otorgamiento y revocación salían de relojes distintos (BD y aplicación), y el CHECK `chk_permiso_fechas` falló. Ahora las dos salen del reloj del dominio (UTC).
- **Prisma:** `prisma/schema.prisma` se genera con `npm run prisma:local` (`db pull` contra la BD local; 39 modelos; las 13 columnas generadas con `@ignore`) y el cliente se regenera con la CLI. **Este schema ya no coincide con producción** hasta que allí se apliquen el 002 y el 003 v2.
- **Pendiente para producción:**
  - autorización explícita;
  - respaldo nuevo;
  - un verificador del v2: `verificar-003`, `ensayo-003` y `objetos-003` describen el v1 y apuntan al clúster, así que no se usan para el v2;
  - la cuenta de BD por tabla (§6, capa 3);
  - decidir si D64 y las tablas de documentos entran en este v2.
