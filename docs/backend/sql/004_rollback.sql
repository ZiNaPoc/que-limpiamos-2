-- ════════════════════════════════════════════════════════════════════════════
-- 004 — ROLLBACK (solo BD locales). Revierte la columna del snapshot y el UNIQUE de resoluciones.
--
-- ⚠ Límite de TiDB: no permite QUITAR valores de un ENUM ("the number of enum column's elements is
--   less than the original"). Por eso 'SUPERVISAR_SOLICITUDES' y 'VENCIDA' se QUEDAN en la
--   definición. Para que el rollback no deje datos huérfanos, ANTES de ejecutarlo comprueba que
--   ninguna fila los usa (las dos consultas deben devolver 0); si alguna no es 0, NO lo ejecutes:
--     SELECT COUNT(*) FROM admin_permisos         WHERE permiso = 'SUPERVISAR_SOLICITUDES';
--     SELECT COUNT(*) FROM solicitud_trabajadores WHERE motivo_cierre = 'VENCIDA';
--   Quitar la columna inmueble_alias_aplicado borra los nombres copiados en las solicitudes
--   creadas después del 004: respalda antes.
-- ════════════════════════════════════════════════════════════════════════════

ALTER TABLE solicitud_resoluciones DROP INDEX uq_res_una_de_servicio;
ALTER TABLE solicitud_resoluciones DROP COLUMN servicio_resuelto_solicitud_id;
ALTER TABLE solicitudes DROP COLUMN inmueble_alias_aplicado;
