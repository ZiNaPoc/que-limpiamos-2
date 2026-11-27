-- ════════════════════════════════════════════════════════════════════════════
-- 003 — REVERSIÓN de 003_notificaciones_unicas_permisos_admin.sql (v1)
-- ════════════════════════════════════════════════════════════════════════════
-- Úsese SOLO si hay que deshacer el 003 (el 002 queda como estaba). Antes:
--   1) Respaldo NUEVO (npm run db:respaldo): esto borra la tabla admin_permisos (historial
--      de permisos) y las claves de evento de las notificaciones (las notificaciones se
--      conservan).
--   2) npm run db:verificar-003 → qué objetos existen. Si el 003 quedó a medias, quitar de
--      aquí las líneas de objetos que NO existen.
--   3) Falla A PROPÓSITO si hay resoluciones (admin_permiso_id las ata a admin_permisos):
--      deshacer el 003 con resoluciones registradas borraría la prueba de autorización.
-- Orden: lo contrario del 003.
-- ════════════════════════════════════════════════════════════════════════════

-- Precondición: sin resoluciones. Agregar este CHECK falla si la tabla tiene alguna fila
-- (ninguna fila tiene una fecha anterior al año 1000); si está vacía, se agrega y se quita en
-- seguida. Así el rollback se detiene ANTES de cambiar nada. (Ni id —AUTO_INCREMENT— ni
-- `created_at IS NULL` sirven en TiDB: ver la guarda del 003.)
ALTER TABLE solicitud_resoluciones ADD CONSTRAINT chk_rollback_003_sin_resoluciones CHECK (created_at < '1000-01-01');
ALTER TABLE solicitud_resoluciones DROP CONSTRAINT chk_rollback_003_sin_resoluciones;

-- C3. AJUSTE con resolución
ALTER TABLE trabajador_movimientos DROP CONSTRAINT chk_mov_ajuste_con_resolucion;
ALTER TABLE trabajador_movimientos DROP COLUMN resolucion_de_ajuste;

-- C2. resoluciones: quitar el permiso y volver a admin_id opcional con SET NULL
ALTER TABLE solicitud_resoluciones DROP FOREIGN KEY fk_res_permiso;
ALTER TABLE solicitud_resoluciones DROP INDEX idx_res_permiso;
ALTER TABLE solicitud_resoluciones DROP COLUMN admin_permiso_id;
ALTER TABLE solicitud_resoluciones DROP FOREIGN KEY fk_res_admin;
ALTER TABLE solicitud_resoluciones MODIFY COLUMN admin_id INT NULL;
ALTER TABLE solicitud_resoluciones
  ADD CONSTRAINT fk_res_admin FOREIGN KEY (admin_id) REFERENCES usuarios (id)
    ON DELETE SET NULL ON UPDATE NO ACTION;

-- C1. permisos
DROP TABLE IF EXISTS admin_permisos;

-- B. plazo de reporte
DELETE FROM parametros_negocio WHERE clave = 'HORAS_PLAZO_REPORTE_PAGO';
ALTER TABLE solicitudes DROP COLUMN reporte_pago_hasta;

-- A. claves de evento (las notificaciones se conservan)
ALTER TABLE notificaciones_trabajador DROP INDEX uq_notif_trab_evento;
ALTER TABLE notificaciones_trabajador DROP COLUMN clave_evento;
ALTER TABLE notificaciones DROP INDEX uq_notif_evento;
ALTER TABLE notificaciones DROP COLUMN clave_evento;
