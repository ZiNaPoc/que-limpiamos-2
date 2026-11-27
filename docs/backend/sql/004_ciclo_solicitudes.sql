-- ════════════════════════════════════════════════════════════════════════════
-- 004 — Ciclo de las solicitudes sin dinero (doc 25 v2, autorizado el 2026-11-25)
--   Requiere: 000 + 002 v10 + 003 v2.
--   Se aplica SOLO a las BD LOCALES (quelimpiamos_pruebas y quelimpiamos_dev). En producción iría
--   después del 002 y del 003 v2, y solo con otra autorización explícita.
--
--   Solo AÑADE: no borra ni modifica ninguna fila, y no cambia ningún valor existente de los ENUM
--   (los nuevos van al final, así que los ya guardados no cambian).
--
--   1. admin_permisos.permiso + 'SUPERVISAR_SOLICITUDES': ver las solicitudes en el panel. El
--      propietario lo tiene de forma implícita (lo resuelve el backend); a los demás se lo otorga él.
--   2. solicitud_trabajadores.motivo_cierre + 'VENCIDA': invitación cerrada porque la solicitud
--      venció (nadie la aceptó antes de su hora programada).
--   3. solicitudes.inmueble_alias_aplicado: el nombre del inmueble guardado, copiado al crear
--      (snapshot inmutable junto con tipo, medidas y dirección). Las filas existentes quedan NULL.
--   4. solicitud_resoluciones: UNA sola resolución DE SERVICIO por solicitud (inmutable). Columna
--      generada + UNIQUE. Una resolución solo de pago (fase de dinero) no ocupa ese lugar.
-- ════════════════════════════════════════════════════════════════════════════

-- 1. Permiso de supervisión de solicitudes.
--    TiDB no permite cambiar una columna de la que depende una columna generada (error 3108:
--    permiso_activo = "<usuario>:<permiso>"). Se quita la columna generada con su UNIQUE, se
--    amplía el ENUM y se vuelven a crear EXACTAMENTE igual que en el 003 v2. Es virtual: no guarda
--    datos, así que no se pierde nada. Mientras dura (unos segundos, sin otras escrituras en la BD
--    local) el UNIQUE "un permiso activo por persona" no existe; al recrearlo, TiDB lo vuelve a
--    comprobar sobre todas las filas.
ALTER TABLE admin_permisos DROP INDEX uq_permiso_activo;
ALTER TABLE admin_permisos DROP COLUMN permiso_activo;
ALTER TABLE admin_permisos
  MODIFY COLUMN permiso ENUM('GESTIONAR_INCIDENCIAS_FINANZAS','ADMINISTRAR_PERMISOS',
                             'MODERAR_CONTENIDO','REVISAR_DOCUMENTOS_IDENTIDAD',
                             'SUPERVISAR_SOLICITUDES') NOT NULL;
ALTER TABLE admin_permisos
  ADD COLUMN permiso_activo VARCHAR(80) AS (IF(revocado_en IS NULL, CONCAT(usuario_id, ':', permiso), NULL)) VIRTUAL AFTER motivo_revocacion;
ALTER TABLE admin_permisos ADD UNIQUE KEY uq_permiso_activo (permiso_activo);

-- 2. Motivo de cierre por vencimiento.
ALTER TABLE solicitud_trabajadores
  MODIFY COLUMN motivo_cierre ENUM('OTRO_TRABAJADOR_ACEPTO','CLIENTE_CANCELO','CAMBIO_A_AUTOMATICA',
                                   'TRABAJADOR_OCUPADO','TRABAJADOR_CANCELO','TRABAJADOR_DADO_DE_BAJA',
                                   'VENCIDA') NULL;

-- 3. Nombre del inmueble en el snapshot de la solicitud.
ALTER TABLE solicitudes ADD COLUMN inmueble_alias_aplicado VARCHAR(100) NULL AFTER inmueble_id;

-- 4. Una sola resolución de servicio por solicitud (la primera gana; la segunda choca con el UNIQUE).
ALTER TABLE solicitud_resoluciones
  ADD COLUMN servicio_resuelto_solicitud_id INT AS (IF(resultado_servicio IS NOT NULL, solicitud_id, NULL)) VIRTUAL;
ALTER TABLE solicitud_resoluciones ADD UNIQUE KEY uq_res_una_de_servicio (servicio_resuelto_solicitud_id);
