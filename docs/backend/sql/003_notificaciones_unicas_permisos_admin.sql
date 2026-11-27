-- ════════════════════════════════════════════════════════════════════════════
-- 003 — Notificaciones únicas por evento (D60), plazo para reportar el efectivo
--       no recibido (D61) y permiso específico de admin para incidencias y
--       movimientos financieros (D62)   (VERSIÓN v1)
-- ════════════════════════════════════════════════════════════════════════════
-- ESTADO: PROPUESTO. NO ejecutado en producción. Se ensaya con: npm run db:ensayo-003
-- REQUIERE el SQL 002 v10 aplicado COMPLETO (84/84). No modifica el 002: lo extiende.
-- Explicación: docs/backend/13_SQL_003_NOTIFICACIONES_Y_PERMISOS.md
-- Reversión:   docs/backend/sql/003_rollback.sql
-- Precondiciones (npm run db:verificar-003 las comprueba ANTES de aplicar):
--   * 002 completo.
--   * solicitud_resoluciones VACÍA y ningún movimiento AJUSTE. Las resoluciones y ajustes
--     anteriores no tienen un permiso al que atribuirlos y no se inventa historial: si
--     existieran, se detiene y se decide caso por caso. Hoy no existen (las rutas de
--     resolución son de la Fase 5 y el 002 todavía no está en producción).
--   * Las notificaciones que ya existan SÍ se conservan: reciben la clave 'LEGADO:<id>'.
-- Reglas del script:
--   * No borra tablas, columnas ni filas. La única actualización de datos llena la columna
--     NUEVA clave_evento de las notificaciones existentes (sus demás columnas no cambian).
--   * Inserta un parámetro nuevo en parametros_negocio (tabla del 002).
--   * El DDL de MySQL/TiDB no es transaccional (ver 12_RESPALDO_Y_RECUPERACION.md §4).
-- ════════════════════════════════════════════════════════════════════════════


-- ── 0. Guardas: se detiene ANTES de cambiar nada si no se cumplen las precondiciones ──
-- Agregar un CHECK valida las filas existentes: estos fallan si hay alguna resolución o algún
-- AJUSTE. Si no hay, se agregan y se quitan en seguida (no dejan rastro). Se compara created_at
-- con una fecha imposible porque TiDB no permite un CHECK sobre la columna AUTO_INCREMENT
-- (error 3818) ni sobre una columna con FK (error 3823), y simplifica `created_at IS NULL`
-- (columna NOT NULL) a una constante, que rechaza (error 3812).
ALTER TABLE solicitud_resoluciones ADD CONSTRAINT chk_003_pre_sin_resoluciones CHECK (created_at < '1000-01-01');
ALTER TABLE solicitud_resoluciones DROP CONSTRAINT chk_003_pre_sin_resoluciones;
ALTER TABLE trabajador_movimientos ADD CONSTRAINT chk_003_pre_sin_ajustes CHECK (tipo <> 'AJUSTE');
ALTER TABLE trabajador_movimientos DROP CONSTRAINT chk_003_pre_sin_ajustes;


-- ── A. D60 — UNA notificación por (destinatario, evento) ────────────────────
-- clave_evento identifica el EVENTO que originó la notificación. Convención:
--   <TIPO>:<entidad>:<id>   p. ej. PAGO_EFECTIVO_PRESUMIDO:sol:123, REPORTE_RESUELTO:rep:45
--   Para eventos que pueden repetirse sobre la misma entidad (p. ej. una invitación que se
--   reabre), el id es el de la fila que registra ESA ocurrencia (historial, participación,
--   movimiento, reporte o resolución), así cada ocurrencia legítima tiene su propia clave.
--   Notificaciones manuales: MANUAL:<uuid>. Las que ya existían: LEGADO:<id>.
-- El UNIQUE es por destinatario: el mismo evento puede avisar a varias personas, pero a
-- cada una solo una vez. Eventos distintos → claves distintas → se permiten.
ALTER TABLE notificaciones ADD COLUMN clave_evento VARCHAR(120) NULL AFTER tipo;
UPDATE notificaciones SET clave_evento = CONCAT('LEGADO:', id) WHERE clave_evento IS NULL;
ALTER TABLE notificaciones MODIFY COLUMN clave_evento VARCHAR(120) NOT NULL;
ALTER TABLE notificaciones ADD UNIQUE KEY uq_notif_evento (usuario_id, clave_evento);

ALTER TABLE notificaciones_trabajador ADD COLUMN clave_evento VARCHAR(120) NULL AFTER tipo;
UPDATE notificaciones_trabajador SET clave_evento = CONCAT('LEGADO:', id) WHERE clave_evento IS NULL;
ALTER TABLE notificaciones_trabajador MODIFY COLUMN clave_evento VARCHAR(120) NOT NULL;
ALTER TABLE notificaciones_trabajador ADD UNIQUE KEY uq_notif_trab_evento (trabajador_id, clave_evento);


-- ── B. D61 — plazo para reportar que no se recibió el efectivo ──────────────
-- Al presumirse el pago (pago_registrado_por = SISTEMA, al confirmarse automáticamente el
-- servicio) el backend fija reporte_pago_hasta = ese momento + HORAS_PLAZO_REPORTE_PAGO.
-- Se guarda (no se recalcula) para que coincida con lo que se le avisó al trabajador aunque
-- el admin cambie el parámetro después. Dentro del plazo el trabajador puede abrir un
-- reporte PAGO_EN_DISPUTA; después el backend lo rechaza y la comisión queda firme.
ALTER TABLE solicitudes ADD COLUMN reporte_pago_hasta DATETIME NULL AFTER pago_registrado_por;
INSERT INTO parametros_negocio (clave, valor, descripcion) VALUES
  ('HORAS_PLAZO_REPORTE_PAGO', 24.00,
   'Horas que tiene el trabajador para reportar que no recibió el efectivo de un pago presumido');


-- ── C. D62 — permiso específico de admin para incidencias y movimientos financieros ──
-- C1. Permisos de admin con historial: otorgar = INSERT; revocar = llenar revocado_*.
--     Nunca se borran (FK RESTRICT). permiso_activo (columna GENERADA VIRTUAL) vale
--     "<usuario>:<permiso>" solo mientras no esté revocado: su UNIQUE impide dos permisos
--     activos iguales y permite volver a otorgarlo después de revocarlo.
--     uq_permiso_id_usuario existe para la FK compuesta de C2.
--     La BD no puede comprobar que usuario_id sea un ADMIN (no hay CHECK entre tablas): lo
--     comprueba el backend, igual que el estado ACTIVA de la cuenta.
CREATE TABLE admin_permisos (
  id             INT          NOT NULL AUTO_INCREMENT,
  usuario_id     INT          NOT NULL,
  permiso        ENUM('GESTIONAR_INCIDENCIAS_FINANZAS') NOT NULL,
  otorgado_por   INT          NULL,
  otorgado_en    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revocado_por   INT          NULL,
  revocado_en    DATETIME     NULL,
  motivo         VARCHAR(255) NULL,
  permiso_activo VARCHAR(80) AS (IF(revocado_en IS NULL, CONCAT(usuario_id, ':', permiso), NULL)) VIRTUAL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_permiso_activo (permiso_activo),
  UNIQUE KEY uq_permiso_id_usuario (id, usuario_id),
  KEY idx_permiso_usuario (usuario_id),
  KEY idx_permiso_otorgado_por (otorgado_por),
  KEY idx_permiso_revocado_por (revocado_por),
  CONSTRAINT fk_permiso_usuario      FOREIGN KEY (usuario_id)   REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_permiso_otorgado_por FOREIGN KEY (otorgado_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_permiso_revocado_por FOREIGN KEY (revocado_por) REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- C2. Toda resolución queda atribuida a un admin (NOT NULL, RESTRICT: los admins no se
--     borran, se suspenden) Y al permiso con el que actuó: la FK compuesta
--     (admin_permiso_id, admin_id) → admin_permisos (id, usuario_id) impide registrar una
--     resolución con el permiso de OTRO admin o sin permiso. Que el permiso esté vigente y
--     la cuenta ACTIVA lo comprueba el backend en la misma transacción (bloqueando la fila
--     del permiso con SELECT … FOR UPDATE para que una revocación simultánea no se cruce).
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

-- C3. Todo AJUSTE (movimiento correctivo) sale de una resolución, y por lo tanto de un admin
--     con permiso. Columna generada porque MySQL/TiDB no permiten un CHECK sobre una columna
--     con FK (error 3823): resolucion_de_ajuste es NULL solo si un AJUSTE no tiene resolución.
ALTER TABLE trabajador_movimientos
  ADD COLUMN resolucion_de_ajuste INT AS (IF(tipo = 'AJUSTE', resolucion_id, NULL)) VIRTUAL;
ALTER TABLE trabajador_movimientos
  ADD CONSTRAINT chk_mov_ajuste_con_resolucion CHECK (tipo <> 'AJUSTE' OR resolucion_de_ajuste IS NOT NULL);
