-- ════════════════════════════════════════════════════════════════════════════
-- 003 v2 — Notificaciones únicas (D60), plazo de reporte del efectivo (D61), permisos de
--          admin con propietario (D62, D63, MODERAR_CONTENIDO), RESEÑAS bidireccionales,
--          REPORTES entre usuarios, evidencias de reportes, moderación y AUDITORÍA.
-- ════════════════════════════════════════════════════════════════════════════
-- ESTADO: APLICADO SOLO en la BD LOCAL (TiDB v8.5.3 en Docker, 127.0.0.1:4000; doc 22), donde
--         corren el backend de desarrollo, la demo y las 123 pruebas. NO aplicado en el clúster
--         remoto (producción ni queLimpiamos_proyecto). Reemplaza al 003 v1 (que nunca se aplicó). Explicación y riesgos:
--         docs/backend/21_SQL_003_V2_RESENAS_REPORTES_MODERACION.md · Reglas: docs/backend/20.
-- Reversión: docs/backend/sql/003_v2_rollback.sql
-- Motor verificado (solo lectura, 2026-11-25): 8.0.11-TiDB-v8.5.3-serverless, CHECK activados
--   (tidb_enable_check_constraint = 1), FK activadas, sin triggers (TiDB no los soporta).
-- REQUIERE el SQL 002 v10 aplicado COMPLETO (84/84): crea solicitud_reportes,
--   solicitud_resoluciones, trabajador_movimientos, parametros_negocio,
--   notificaciones_trabajador, solicitudes.realizado_en y amplía evidencias_solicitud.
-- Orden: 0 guardas → A (D60) → B (D61) → C (permisos) → D (reseñas) → E (reportes)
--        → F (evidencias) → G (auditoría de moderación). G depende de C, D y E.
-- Operaciones DESTRUCTIVAS: solo D1 (DROP TABLE resenas). Decidido por el usuario: no se
--   conservan las reseñas antiguas. En producción la tabla tenía 0 filas el 2026-11-25; si
--   para entonces tiene filas, se pierden (quedan en el respaldo previo obligatorio).
-- El DDL de TiDB NO es transaccional: si falla a la mitad, lo aplicado queda aplicado
--   (12_RESPALDO_Y_RECUPERACION.md §4). Por eso: respaldo antes, verificador antes y después.
-- Convención TiDB: un CHECK no puede usar una columna con FK (3823) ni la AUTO_INCREMENT
--   (3818); las reglas sobre columnas con FK se expresan con una columna GENERADA VIRTUAL
--   que vale 1 si se cumple, y el CHECK se pone sobre esa columna (patrón ya ensayado en el
--   002 v8 y en el 003 v1).
-- ════════════════════════════════════════════════════════════════════════════


-- ── 0. Guardas (igual que el 003 v1): se detiene ANTES de cambiar nada ──────
-- Fallan con violación de CHECK (3819) si hay resoluciones o AJUSTES previos, que no tendrían
-- un permiso al que atribuirse. Si no hay, se agregan y se quitan en seguida.
ALTER TABLE solicitud_resoluciones ADD CONSTRAINT chk_003_pre_sin_resoluciones CHECK (created_at < '1000-01-01');
ALTER TABLE solicitud_resoluciones DROP CONSTRAINT chk_003_pre_sin_resoluciones;
ALTER TABLE trabajador_movimientos ADD CONSTRAINT chk_003_pre_sin_ajustes CHECK (tipo <> 'AJUSTE');
ALTER TABLE trabajador_movimientos DROP CONSTRAINT chk_003_pre_sin_ajustes;
-- Nueva en v2: sin reportes previos. Los reportes nuevos exigen identificar al reportado
-- (E2); uno anterior no lo tiene y no se inventa.
ALTER TABLE solicitud_reportes ADD CONSTRAINT chk_003_pre_sin_reportes CHECK (created_at < '1000-01-01');
ALTER TABLE solicitud_reportes DROP CONSTRAINT chk_003_pre_sin_reportes;


-- ── A. D60 — UNA notificación por (destinatario, evento) — SIN CAMBIOS desde v1 ──
ALTER TABLE notificaciones ADD COLUMN clave_evento VARCHAR(120) NULL AFTER tipo;
UPDATE notificaciones SET clave_evento = CONCAT('LEGADO:', id) WHERE clave_evento IS NULL;
ALTER TABLE notificaciones MODIFY COLUMN clave_evento VARCHAR(120) NOT NULL;
ALTER TABLE notificaciones ADD UNIQUE KEY uq_notif_evento (usuario_id, clave_evento);

ALTER TABLE notificaciones_trabajador ADD COLUMN clave_evento VARCHAR(120) NULL AFTER tipo;
UPDATE notificaciones_trabajador SET clave_evento = CONCAT('LEGADO:', id) WHERE clave_evento IS NULL;
ALTER TABLE notificaciones_trabajador MODIFY COLUMN clave_evento VARCHAR(120) NOT NULL;
ALTER TABLE notificaciones_trabajador ADD UNIQUE KEY uq_notif_trab_evento (trabajador_id, clave_evento);


-- ── B. D61 — plazo para reportar el efectivo no recibido — SIN CAMBIOS desde v1 ──
ALTER TABLE solicitudes ADD COLUMN reporte_pago_hasta DATETIME NULL AFTER pago_registrado_por;
INSERT INTO parametros_negocio (clave, valor, descripcion) VALUES
  ('HORAS_PLAZO_REPORTE_PAGO', 24.00,
   'Horas que tiene el trabajador para reportar que no recibió el efectivo de un pago presumido');


-- ── C. PERMISOS DE ADMIN (D62 + D63 + MODERAR_CONTENIDO) ────────────────────
-- C1. admin_permisos. Cada fila es un otorgamiento; las filas NUNCA se borran (FK RESTRICT):
--     la tabla es el historial auditado de permisos (quién, a quién, cuándo, por qué, y su
--     revocación). Cambios respecto a v1:
--       * permiso suma ADMINISTRAR_PERMISOS (propietario, D63), MODERAR_CONTENIDO (doc 20 §6)
--         y REVISAR_DOCUMENTOS_IDENTIDAD (D66, decidido; sus tablas de documentos siguen
--         pendientes, doc 21 §9);
--       * origen: ASIGNACION_INICIAL (solo por el script revisado de la plantilla, sin
--         otorgante, motivo obligatorio) u OTORGADO_POR_ADMIN (lo hace el backend; exige
--         otorgante y que no sea uno mismo);
--       * motivo_revocacion.
--     Que el otorgante tenga ADMINISTRAR_PERMISOS vigente, que ambas cuentas sean ADMIN y
--     estén ACTIVAS lo comprueba el backend en la misma transacción (SELECT … FOR UPDATE):
--     la BD no puede comparar con otras tablas (no hay CHECK entre tablas ni triggers).
CREATE TABLE admin_permisos (
  id                 INT          NOT NULL AUTO_INCREMENT,
  usuario_id         INT          NOT NULL,
  permiso            ENUM('GESTIONAR_INCIDENCIAS_FINANZAS','ADMINISTRAR_PERMISOS',
                          'MODERAR_CONTENIDO','REVISAR_DOCUMENTOS_IDENTIDAD') NOT NULL,
  origen             ENUM('ASIGNACION_INICIAL','OTORGADO_POR_ADMIN') NOT NULL,
  otorgado_por       INT          NULL,
  otorgado_en        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  motivo             VARCHAR(255) NULL,
  revocado_por       INT          NULL,
  revocado_en        DATETIME     NULL,
  motivo_revocacion  VARCHAR(255) NULL,
  -- "<usuario>:<permiso>" solo mientras no esté revocado: un permiso activo por persona.
  permiso_activo     VARCHAR(80) AS (IF(revocado_en IS NULL, CONCAT(usuario_id, ':', permiso), NULL)) VIRTUAL,
  -- 1 si el origen es coherente: inicial ⇒ sin otorgante; por admin ⇒ otorgante distinto
  -- de quien lo recibe (nadie se otorga un permiso a sí mismo).
  regla_otorgamiento TINYINT AS (CASE WHEN origen = 'ASIGNACION_INICIAL' THEN otorgado_por IS NULL
                                      ELSE (otorgado_por IS NOT NULL AND otorgado_por <> usuario_id) END) VIRTUAL,
  -- 1 si la revocación está completa: fecha y autor juntos.
  regla_revocacion   TINYINT AS ((revocado_en IS NULL) = (revocado_por IS NULL)) VIRTUAL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_permiso_activo (permiso_activo),
  UNIQUE KEY uq_permiso_id_usuario (id, usuario_id),
  KEY idx_permiso_usuario (usuario_id),
  KEY idx_permiso_otorgado_por (otorgado_por),
  KEY idx_permiso_revocado_por (revocado_por),
  CONSTRAINT chk_permiso_otorgamiento CHECK (regla_otorgamiento = 1),
  CONSTRAINT chk_permiso_revocacion   CHECK (regla_revocacion = 1),
  CONSTRAINT chk_permiso_motivo_inicial
    CHECK (origen <> 'ASIGNACION_INICIAL' OR (motivo IS NOT NULL AND CHAR_LENGTH(TRIM(motivo)) > 0)),
  CONSTRAINT chk_permiso_fechas CHECK (revocado_en IS NULL OR revocado_en >= otorgado_en),
  CONSTRAINT fk_permiso_usuario      FOREIGN KEY (usuario_id)   REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_permiso_otorgado_por FOREIGN KEY (otorgado_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_permiso_revocado_por FOREIGN KEY (revocado_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
-- NO se inserta ningún permiso aquí: la asignación inicial al propietario es un paso aparte
-- (003_v2_plantilla_asignacion_inicial_propietario.sql), pendiente de D63a.

-- C2. Resoluciones atribuidas a un admin y al permiso con el que actuó — SIN CAMBIOS desde v1.
ALTER TABLE solicitud_resoluciones DROP FOREIGN KEY fk_res_admin;
ALTER TABLE solicitud_resoluciones MODIFY COLUMN admin_id INT NOT NULL;
ALTER TABLE solicitud_resoluciones
  ADD CONSTRAINT fk_res_admin FOREIGN KEY (admin_id) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE solicitud_resoluciones ADD COLUMN admin_permiso_id INT NOT NULL AFTER admin_id;
ALTER TABLE solicitud_resoluciones ADD KEY idx_res_permiso (admin_permiso_id, admin_id);
ALTER TABLE solicitud_resoluciones
  ADD CONSTRAINT fk_res_permiso FOREIGN KEY (admin_permiso_id, admin_id) REFERENCES admin_permisos (id, usuario_id)
    ON DELETE RESTRICT ON UPDATE NO ACTION;

-- C3. Todo AJUSTE sale de una resolución — SIN CAMBIOS desde v1.
ALTER TABLE trabajador_movimientos
  ADD COLUMN resolucion_de_ajuste INT AS (IF(tipo = 'AJUSTE', resolucion_id, NULL)) VIRTUAL;
ALTER TABLE trabajador_movimientos
  ADD CONSTRAINT chk_mov_ajuste_con_resolucion CHECK (tipo <> 'AJUSTE' OR resolucion_de_ajuste IS NOT NULL);


-- ── D. RESEÑAS BIDIRECCIONALES (reconstrucción de resenas) ──────────────────
-- D1. DESTRUCTIVO Y DECIDIDO: se borra la tabla antigua (una reseña por solicitud, solo
--     cliente → trabajador, con puntuacion_servicio y puntuacion_trabajador). Ninguna FK,
--     vista ni código del backend depende de ella (comprobado el 2026-11-25); solo el modelo
--     Prisma `resenas`, que se reemplaza en la Fase 3a.
DROP TABLE resenas;

-- D2. Claves para las FK compuestas de D3: garantizan que el cliente y el trabajador de la
--     reseña son EXACTAMENTE los de la solicitud. (id es único, así que estos pares también.)
--     Efecto: mientras exista una reseña, solicitudes.trabajador_id no se puede cambiar
--     (ON UPDATE NO ACTION); las reseñas solo existen después de REALIZADO.
ALTER TABLE solicitudes ADD UNIQUE KEY uq_sol_id_cliente (id, cliente_id);
ALTER TABLE solicitudes ADD UNIQUE KEY uq_sol_id_trabajador (id, trabajador_id);

-- D3. Una reseña por (solicitud, autor_rol): como máximo dos por solicitud.
--     autor_rol = CLIENTE  → el cliente califica al trabajador.
--     autor_rol = TRABAJADOR → el trabajador califica al cliente.
--     Siempre se guardan las dos partes; el autor y el calificado se deducen de autor_rol.
--     Que la solicitud esté REALIZADO y dentro de los 7 días desde solicitudes.realizado_en
--     lo comprueba el backend al insertar (la BD no compara con otras tablas).
--     comentario es TEXT SIN límite propio: el límite de 500 NO está confirmado (doc 20 §10).
--     Eliminación SOLO lógica (eliminada_en/eliminada_por) y solo por moderación; editada_en
--     marca la última corrección de un admin. El original queda en moderacion_eventos.
CREATE TABLE resenas (
  id                INT              NOT NULL AUTO_INCREMENT,
  solicitud_id      INT              NOT NULL,
  autor_rol         ENUM('CLIENTE','TRABAJADOR') NOT NULL,
  cliente_id        INT              NOT NULL,
  trabajador_id     INT              NOT NULL,
  puntuacion        TINYINT UNSIGNED NOT NULL,
  comentario        TEXT             NULL,
  created_at        DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  editada_en        DATETIME         NULL,
  eliminada_en      DATETIME         NULL,
  eliminada_por     INT              NULL,
  regla_eliminacion TINYINT AS ((eliminada_en IS NULL) = (eliminada_por IS NULL)) VIRTUAL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_resena_solicitud_autor (solicitud_id, autor_rol),
  KEY idx_resena_sol_cliente (solicitud_id, cliente_id),
  KEY idx_resena_sol_trabajador (solicitud_id, trabajador_id),
  -- Promedios: reseñas válidas (eliminada_en IS NULL) recibidas por cada parte.
  KEY idx_resena_trabajador (trabajador_id, autor_rol, eliminada_en),
  KEY idx_resena_cliente (cliente_id, autor_rol, eliminada_en),
  KEY idx_resena_eliminada_por (eliminada_por),
  CONSTRAINT chk_resena_puntuacion  CHECK (puntuacion BETWEEN 1 AND 5),
  CONSTRAINT chk_resena_eliminacion CHECK (regla_eliminacion = 1),
  CONSTRAINT chk_resena_editada     CHECK (editada_en IS NULL OR editada_en >= created_at),
  CONSTRAINT chk_resena_eliminada   CHECK (eliminada_en IS NULL OR eliminada_en >= created_at),
  CONSTRAINT fk_resena_sol_cliente FOREIGN KEY (solicitud_id, cliente_id)
    REFERENCES solicitudes (id, cliente_id) ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_resena_sol_trabajador FOREIGN KEY (solicitud_id, trabajador_id)
    REFERENCES solicitudes (id, trabajador_id) ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_resena_eliminada_por FOREIGN KEY (eliminada_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ── E. REPORTES ENTRE USUARIOS (se extiende solicitud_reportes del 002) ─────
-- Ya cumple: solicitud concreta, quién reporta (reportado_por + cliente_id/trabajador_id),
-- tipo, descripción OPCIONAL, estado ABIERTO → EN_REVISION → RESUELTO y resolución.
-- Falta y se agrega: a QUIÉN se reporta, edición y eliminación lógica por moderación.
-- E1. Usuario reportado explícito (no se deduce de la solicitud: el trabajador asignado puede
--     cambiar antes de terminar, y el reporte se permite antes de finalizar).
ALTER TABLE solicitud_reportes ADD COLUMN reportado_cliente_id INT NULL AFTER trabajador_id;
ALTER TABLE solicitud_reportes ADD COLUMN reportado_trabajador_id INT NULL AFTER reportado_cliente_id;
ALTER TABLE solicitud_reportes ADD COLUMN editado_en DATETIME NULL AFTER resolucion_id;
ALTER TABLE solicitud_reportes ADD COLUMN eliminado_en DATETIME NULL AFTER editado_en;
ALTER TABLE solicitud_reportes ADD COLUMN eliminado_por INT NULL AFTER eliminado_en;
ALTER TABLE solicitud_reportes ADD KEY idx_rep_reportado_cliente (reportado_cliente_id);
ALTER TABLE solicitud_reportes ADD KEY idx_rep_reportado_trabajador (reportado_trabajador_id);
ALTER TABLE solicitud_reportes ADD KEY idx_rep_eliminado_por (eliminado_por);
ALTER TABLE solicitud_reportes
  ADD CONSTRAINT fk_rep_reportado_cliente FOREIGN KEY (reportado_cliente_id) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE solicitud_reportes
  ADD CONSTRAINT fk_rep_reportado_trabajador FOREIGN KEY (reportado_trabajador_id) REFERENCES trabajadores (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE solicitud_reportes
  ADD CONSTRAINT fk_rep_eliminado_por FOREIGN KEY (eliminado_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION;

-- E2. Partes coherentes. "<quién reporta>:<cliente><trabajador><rep_cliente><rep_trabajador>"
--     con 1 = columna llena. Solo dos combinaciones válidas:
--       CLIENTE:1001    el cliente (cliente_id) reporta al trabajador (reportado_trabajador_id)
--       TRABAJADOR:0110 el trabajador (trabajador_id) reporta al cliente (reportado_cliente_id)
--     Que esas personas sean las de la solicitud lo comprueba el backend al crear el reporte.
ALTER TABLE solicitud_reportes
  ADD COLUMN partes_del_reporte VARCHAR(20) AS (CONCAT(reportado_por, ':',
    cliente_id IS NOT NULL, trabajador_id IS NOT NULL,
    reportado_cliente_id IS NOT NULL, reportado_trabajador_id IS NOT NULL)) VIRTUAL;
ALTER TABLE solicitud_reportes
  ADD CONSTRAINT chk_rep_partes CHECK (partes_del_reporte IN ('CLIENTE:1001', 'TRABAJADOR:0110'));

-- E3. Eliminación lógica completa (fecha y admin juntos) y fechas coherentes.
ALTER TABLE solicitud_reportes
  ADD COLUMN regla_eliminacion TINYINT AS ((eliminado_en IS NULL) = (eliminado_por IS NULL)) VIRTUAL;
ALTER TABLE solicitud_reportes ADD CONSTRAINT chk_rep_eliminacion CHECK (regla_eliminacion = 1);
ALTER TABLE solicitud_reportes
  ADD CONSTRAINT chk_rep_fechas CHECK ((editado_en IS NULL OR editado_en >= created_at)
                                   AND (eliminado_en IS NULL OR eliminado_en >= created_at));


-- ── F. EVIDENCIAS DE LOS REPORTES (se extiende evidencias_solicitud) ────────
-- La tabla ya enlaza la foto con la solicitud y, desde el 002, con el reporte (reporte_id) y
-- quien la aporta (aportada_por). archivo_url guarda la CLAVE PRIVADA del almacenamiento
-- local (doc 16), nunca una URL pública. Se agregan los metadatos que entrega el
-- almacenamiento (ObjetoGuardado: mime, bytes, sha256) para poder aplicar y auditar los
-- límites, y la eliminación lógica por moderación.
-- Límites CONFIRMADOS (5 fotos, 8 MB cada una, 16 MB por reporte): los aplica el backend en
-- una transacción que bloquea el reporte (FOR UPDATE) y suma lo ya guardado. La BD no puede
-- contar ni sumar filas en un CHECK y TiDB no tiene triggers. Los TIPOS permitidos y si
-- "MB" es 10^6 o 2^20 bytes NO están confirmados (doc 20 §10): por eso aquí no hay CHECK de
-- tipo ni de tamaño máximo.
ALTER TABLE evidencias_solicitud ADD COLUMN tipo_mime VARCHAR(50) NULL AFTER archivo_url;
ALTER TABLE evidencias_solicitud ADD COLUMN tamano_bytes INT UNSIGNED NULL AFTER tipo_mime;
ALTER TABLE evidencias_solicitud ADD COLUMN sha256 CHAR(64) NULL AFTER tamano_bytes;
ALTER TABLE evidencias_solicitud ADD COLUMN eliminada_en DATETIME NULL AFTER created_at;
ALTER TABLE evidencias_solicitud ADD COLUMN eliminada_por INT NULL AFTER eliminada_en;
ALTER TABLE evidencias_solicitud ADD KEY idx_evid_eliminada_por (eliminada_por);
ALTER TABLE evidencias_solicitud
  ADD CONSTRAINT fk_evid_eliminada_por FOREIGN KEY (eliminada_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE evidencias_solicitud
  ADD COLUMN regla_eliminacion TINYINT AS ((eliminada_en IS NULL) = (eliminada_por IS NULL)) VIRTUAL;
ALTER TABLE evidencias_solicitud ADD CONSTRAINT chk_evid_eliminacion CHECK (regla_eliminacion = 1);
ALTER TABLE evidencias_solicitud ADD CONSTRAINT chk_evid_tamano CHECK (tamano_bytes IS NULL OR tamano_bytes > 0);


-- ── G. AUDITORÍA DE MODERACIÓN Y DE PERMISOS (solo se agrega; nunca se edita ni se borra) ──
-- Un evento por cada modificación administrativa de una reseña, un reporte o un permiso,
-- escrito en la MISMA transacción que el cambio. Guarda: admin, permiso con el que actuó,
-- fecha (UTC), operación, datos anteriores, datos nuevos y motivo obligatorio. El PRIMER
-- evento de cada entidad conserva su versión original completa en datos_anteriores.
--   * entidad / objetivo: exactamente una de resena_id, reporte_id o permiso_id.
--   * Operaciones por entidad (CHECK): RESENA → EDITAR, ELIMINAR; REPORTE → EDITAR,
--     ELIMINAR, CAMBIAR_ESTADO, RESOLVER, NOTA; PERMISO → OTORGAR, REVOCAR,
--     ASIGNACION_INICIAL.
--   * Actor: (admin_permiso_id, admin_id) → admin_permisos (id, usuario_id): el admin actuó
--     con UN permiso SUYO (MODERAR_CONTENIDO para el contenido; ADMINISTRAR_PERMISOS para
--     otorgar o revocar). Que sea el permiso correcto y esté vigente lo comprueba el backend.
--     ÚNICA excepción: ASIGNACION_INICIAL (la carga el script revisado, no un admin): sin
--     actor (admin_id y admin_permiso_id NULL). Con NULL la FK compuesta no se evalúa.
--   * FK RESTRICT en todo: no se puede borrar físicamente una reseña, reporte, permiso o
--     admin que tenga historial.
--   * Inmutabilidad: TiDB no tiene triggers; ver doc 21 §6 (el código solo hace INSERT y
--     SELECT sobre esta tabla, más una prueba estática que lo vigila).
CREATE TABLE moderacion_eventos (
  id                INT          NOT NULL AUTO_INCREMENT,
  admin_id          INT          NULL,
  admin_permiso_id  INT          NULL,
  entidad           ENUM('RESENA','REPORTE','PERMISO') NOT NULL,
  resena_id         INT          NULL,
  reporte_id        INT          NULL,
  permiso_id        INT          NULL,
  operacion         ENUM('EDITAR','ELIMINAR','CAMBIAR_ESTADO','RESOLVER','NOTA',
                         'OTORGAR','REVOCAR','ASIGNACION_INICIAL') NOT NULL,
  datos_anteriores  JSON         NOT NULL,
  datos_nuevos      JSON         NOT NULL,
  motivo            VARCHAR(500) NOT NULL,
  created_at        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- 1 si apunta exactamente a una entidad del tipo declarado.
  regla_objetivo    TINYINT AS (CASE
                                  WHEN entidad = 'RESENA'  THEN (resena_id IS NOT NULL AND reporte_id IS NULL AND permiso_id IS NULL)
                                  WHEN entidad = 'REPORTE' THEN (reporte_id IS NOT NULL AND resena_id IS NULL AND permiso_id IS NULL)
                                  ELSE (permiso_id IS NOT NULL AND resena_id IS NULL AND reporte_id IS NULL) END) VIRTUAL,
  -- 1 si el actor es coherente: asignación inicial sin actor; todo lo demás con admin y permiso.
  regla_actor       TINYINT AS (CASE WHEN operacion = 'ASIGNACION_INICIAL'
                                     THEN (admin_id IS NULL AND admin_permiso_id IS NULL)
                                     ELSE (admin_id IS NOT NULL AND admin_permiso_id IS NOT NULL) END) VIRTUAL,
  PRIMARY KEY (id),
  KEY idx_mod_resena (resena_id, created_at),
  KEY idx_mod_reporte (reporte_id, created_at),
  KEY idx_mod_permiso_objetivo (permiso_id, created_at),
  KEY idx_mod_admin (admin_id, created_at),
  KEY idx_mod_permiso (admin_permiso_id, admin_id),
  CONSTRAINT chk_mod_objetivo  CHECK (regla_objetivo = 1),
  CONSTRAINT chk_mod_actor     CHECK (regla_actor = 1),
  CONSTRAINT chk_mod_operacion CHECK (
    (entidad = 'RESENA'  AND operacion IN ('EDITAR','ELIMINAR')) OR
    (entidad = 'REPORTE' AND operacion IN ('EDITAR','ELIMINAR','CAMBIAR_ESTADO','RESOLVER','NOTA')) OR
    (entidad = 'PERMISO' AND operacion IN ('OTORGAR','REVOCAR','ASIGNACION_INICIAL'))),
  CONSTRAINT chk_mod_motivo    CHECK (CHAR_LENGTH(TRIM(motivo)) > 0),
  CONSTRAINT chk_mod_datos     CHECK (JSON_TYPE(datos_anteriores) = 'OBJECT' AND JSON_TYPE(datos_nuevos) = 'OBJECT'),
  CONSTRAINT fk_mod_admin   FOREIGN KEY (admin_id) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_mod_permiso FOREIGN KEY (admin_permiso_id, admin_id) REFERENCES admin_permisos (id, usuario_id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_mod_resena  FOREIGN KEY (resena_id) REFERENCES resenas (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_mod_reporte FOREIGN KEY (reporte_id) REFERENCES solicitud_reportes (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_mod_permiso_objetivo FOREIGN KEY (permiso_id) REFERENCES admin_permisos (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
-- Fin del 003 v2. Objetos nuevos o cambiados: ver el inventario en doc 21 §3.
