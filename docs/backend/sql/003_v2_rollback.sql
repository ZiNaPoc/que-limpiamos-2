-- ════════════════════════════════════════════════════════════════════════════
-- 003 v2 — REVERSIÓN de 003_v2_notificaciones_permisos_resenas_reportes.sql
-- ════════════════════════════════════════════════════════════════════════════
-- ESTADO: PROPUESTO. No ejecutado en ninguna BD. Deja la BD como "002 v10 aplicado".
-- Antes de usarla:
--   1) Respaldo NUEVO de la BD (12_RESPALDO_Y_RECUPERACION.md). Esta reversión BORRA:
--      admin_permisos (historial de permisos), moderacion_eventos (auditoría), las reseñas
--      nuevas, los datos de "reportado"/eliminación de los reportes y los metadatos de las
--      evidencias. Las notificaciones se conservan (solo pierden clave_evento).
--   2) Si el 003 v2 quedó a medias (el DDL de TiDB no es transaccional), quitar de aquí las
--      líneas de objetos que NO existen (el verificador lista cuáles existen).
--   3) GUARDAS: falla A PROPÓSITO (violación de CHECK, 3819) si ya hay resoluciones,
--      permisos, eventos de moderación, reseñas o reportes. Deshacer con esos datos
--      destruiría historial auditado: se decide caso por caso y, solo con autorización
--      explícita, se quita la guarda correspondiente.
-- Orden: el inverso del 003 v2 (G → F → E → D → C → B → A).
-- El paso D4 recrea la tabla resenas ANTIGUA con su DDL exacto de producción (leído con
-- SHOW CREATE TABLE el 2026-11-25), VACÍA: las reseñas antiguas no se recuperan aquí (si
-- hubiera, están en el respaldo previo a aplicar el 003 v2).
-- ════════════════════════════════════════════════════════════════════════════

-- ── Guardas (no dejan rastro si las tablas están vacías) ────────────────────
ALTER TABLE solicitud_resoluciones ADD CONSTRAINT chk_rb003v2_sin_resoluciones CHECK (created_at < '1000-01-01');
ALTER TABLE solicitud_resoluciones DROP CONSTRAINT chk_rb003v2_sin_resoluciones;
ALTER TABLE admin_permisos ADD CONSTRAINT chk_rb003v2_sin_permisos CHECK (otorgado_en < '1000-01-01');
ALTER TABLE admin_permisos DROP CONSTRAINT chk_rb003v2_sin_permisos;
ALTER TABLE moderacion_eventos ADD CONSTRAINT chk_rb003v2_sin_eventos CHECK (created_at < '1000-01-01');
ALTER TABLE moderacion_eventos DROP CONSTRAINT chk_rb003v2_sin_eventos;
ALTER TABLE resenas ADD CONSTRAINT chk_rb003v2_sin_resenas CHECK (created_at < '1000-01-01');
ALTER TABLE resenas DROP CONSTRAINT chk_rb003v2_sin_resenas;
ALTER TABLE solicitud_reportes ADD CONSTRAINT chk_rb003v2_sin_reportes CHECK (created_at < '1000-01-01');
ALTER TABLE solicitud_reportes DROP CONSTRAINT chk_rb003v2_sin_reportes;

-- ── G. Auditoría de moderación ──────────────────────────────────────────────
DROP TABLE moderacion_eventos;

-- ── F. Evidencias: metadatos y eliminación lógica ───────────────────────────
ALTER TABLE evidencias_solicitud DROP CONSTRAINT chk_evid_tamano;
ALTER TABLE evidencias_solicitud DROP CONSTRAINT chk_evid_eliminacion;
ALTER TABLE evidencias_solicitud DROP COLUMN regla_eliminacion;
ALTER TABLE evidencias_solicitud DROP FOREIGN KEY fk_evid_eliminada_por;
ALTER TABLE evidencias_solicitud DROP INDEX idx_evid_eliminada_por;
ALTER TABLE evidencias_solicitud DROP COLUMN eliminada_por;
ALTER TABLE evidencias_solicitud DROP COLUMN eliminada_en;
ALTER TABLE evidencias_solicitud DROP COLUMN sha256;
ALTER TABLE evidencias_solicitud DROP COLUMN tamano_bytes;
ALTER TABLE evidencias_solicitud DROP COLUMN tipo_mime;

-- ── E. Reportes: reportado, edición y eliminación lógica ────────────────────
ALTER TABLE solicitud_reportes DROP CONSTRAINT chk_rep_fechas;
ALTER TABLE solicitud_reportes DROP CONSTRAINT chk_rep_eliminacion;
ALTER TABLE solicitud_reportes DROP COLUMN regla_eliminacion;
ALTER TABLE solicitud_reportes DROP CONSTRAINT chk_rep_partes;
ALTER TABLE solicitud_reportes DROP COLUMN partes_del_reporte;
ALTER TABLE solicitud_reportes DROP FOREIGN KEY fk_rep_eliminado_por;
ALTER TABLE solicitud_reportes DROP FOREIGN KEY fk_rep_reportado_trabajador;
ALTER TABLE solicitud_reportes DROP FOREIGN KEY fk_rep_reportado_cliente;
ALTER TABLE solicitud_reportes DROP INDEX idx_rep_eliminado_por;
ALTER TABLE solicitud_reportes DROP INDEX idx_rep_reportado_trabajador;
ALTER TABLE solicitud_reportes DROP INDEX idx_rep_reportado_cliente;
ALTER TABLE solicitud_reportes DROP COLUMN eliminado_por;
ALTER TABLE solicitud_reportes DROP COLUMN eliminado_en;
ALTER TABLE solicitud_reportes DROP COLUMN editado_en;
ALTER TABLE solicitud_reportes DROP COLUMN reportado_trabajador_id;
ALTER TABLE solicitud_reportes DROP COLUMN reportado_cliente_id;

-- ── D. Reseñas: quitar la tabla nueva y volver a la antigua (vacía) ─────────
DROP TABLE resenas;
ALTER TABLE solicitudes DROP INDEX uq_sol_id_trabajador;
ALTER TABLE solicitudes DROP INDEX uq_sol_id_cliente;
-- D4. DDL exacto de producción (2026-11-25).
CREATE TABLE resenas (
  id                    INT      NOT NULL AUTO_INCREMENT,
  solicitud_id          INT      NOT NULL,
  puntuacion_servicio   TINYINT  NOT NULL,
  puntuacion_trabajador TINYINT  NOT NULL,
  comentario            TEXT     COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY uq_resena_solicitud (solicitud_id),
  CONSTRAINT fk_resena_solicitud FOREIGN KEY (solicitud_id) REFERENCES solicitudes (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── C. Permisos (igual que el rollback del 003 v1) ──────────────────────────
ALTER TABLE trabajador_movimientos DROP CONSTRAINT chk_mov_ajuste_con_resolucion;
ALTER TABLE trabajador_movimientos DROP COLUMN resolucion_de_ajuste;

ALTER TABLE solicitud_resoluciones DROP FOREIGN KEY fk_res_permiso;
ALTER TABLE solicitud_resoluciones DROP INDEX idx_res_permiso;
ALTER TABLE solicitud_resoluciones DROP COLUMN admin_permiso_id;
ALTER TABLE solicitud_resoluciones DROP FOREIGN KEY fk_res_admin;
ALTER TABLE solicitud_resoluciones MODIFY COLUMN admin_id INT NULL;
ALTER TABLE solicitud_resoluciones
  ADD CONSTRAINT fk_res_admin FOREIGN KEY (admin_id) REFERENCES usuarios (id)
    ON DELETE SET NULL ON UPDATE NO ACTION;

DROP TABLE admin_permisos;

-- ── B. Plazo de reporte ─────────────────────────────────────────────────────
DELETE FROM parametros_negocio WHERE clave = 'HORAS_PLAZO_REPORTE_PAGO';
ALTER TABLE solicitudes DROP COLUMN reporte_pago_hasta;

-- ── A. Claves de evento (las notificaciones se conservan) ───────────────────
ALTER TABLE notificaciones_trabajador DROP INDEX uq_notif_trab_evento;
ALTER TABLE notificaciones_trabajador DROP COLUMN clave_evento;
ALTER TABLE notificaciones DROP INDEX uq_notif_evento;
ALTER TABLE notificaciones DROP COLUMN clave_evento;
