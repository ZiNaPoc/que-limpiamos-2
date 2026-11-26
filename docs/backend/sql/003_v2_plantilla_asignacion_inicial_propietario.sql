-- ════════════════════════════════════════════════════════════════════════════
-- PLANTILLA — Asignación inicial AUDITADA de permisos al PROPIETARIO (D63)
-- ════════════════════════════════════════════════════════════════════════════
-- ESTADO: PREPARADA, NO EJECUTADA en ninguna BD. D63a decidida (2026-11-25): el propietario es
--   la cuenta con el correo indicado por el usuario (doc 20 §6). NO es el admin con id 1 (correo
--   de demostración). La cuenta debe existir como ADMIN: no se crea ni se cambia de rol aquí.
-- A PROPÓSITO no se puede ejecutar tal cual: :ID_PROPIETARIO, :CORREO_PROPIETARIO y
--   :MOTIVO son marcadores que dan error de sintaxis hasta reemplazarlos a mano.
-- Requisitos: 003 v2 aplicado; respaldo nuevo; ejecutar en UNA sesión, revisando cada
--   resultado antes de seguir.
-- Equivalente automatizado y probado: npm run permisos:asignar-propietario (doc 21 §5); en
--   producción se usa esta plantilla, revisada, cuando se autorice.
-- Auditoría: las filas de admin_permisos SON el historial, y además cada asignación crea un
--   evento en moderacion_eventos (operacion = ASIGNACION_INICIAL). Esta asignación queda con
--   origen = 'ASIGNACION_INICIAL', otorgado_por = NULL (nadie se lo otorga: la carga el
--   script revisado), fecha automática y motivo OBLIGATORIO (CHECK chk_permiso_motivo_inicial).
--   Después, el propietario otorga MODERAR_CONTENIDO a otros admins desde el backend
--   (origen = 'OTORGADO_POR_ADMIN', otorgado_por = propietario, nunca a sí mismo).
-- Qué permisos recibe aquí: ADMINISTRAR_PERMISOS (ser propietario) y MODERAR_CONTENIDO
--   (decidido). Los demás (GESTIONAR_INCIDENCIAS_FINANZAS, REVISAR_DOCUMENTOS_IDENTIDAD)
--   NO se incluyen: D63b sigue abierta.
-- ════════════════════════════════════════════════════════════════════════════

START TRANSACTION;

-- 1. Revisar a mano la cuenta (debe salir UNA fila: rol ADMIN, ACTIVA y el correo confirmado).
SELECT id, correo, rol, estado_cuenta FROM usuarios WHERE id = :ID_PROPIETARIO FOR UPDATE;

-- 2. Revisar que todavía no hay propietario vigente (debe salir 0).
SELECT COUNT(*) AS propietarios_vigentes FROM admin_permisos
 WHERE permiso = 'ADMINISTRAR_PERMISOS' AND revocado_en IS NULL;

-- 3. Propietario. Solo inserta si TODO coincide; si no, inserta 0 filas.
--    El filtro de dominios de demostración evita asignarlo por error a una cuenta demo;
--    si de verdad el propietario usa uno de esos dominios, se quita conscientemente.
INSERT INTO admin_permisos (usuario_id, permiso, origen, otorgado_por, motivo)
SELECT u.id, 'ADMINISTRAR_PERMISOS', 'ASIGNACION_INICIAL', NULL, :MOTIVO
  FROM usuarios u
 WHERE u.id = :ID_PROPIETARIO
   AND u.correo = :CORREO_PROPIETARIO
   AND u.rol = 'ADMIN'
   AND u.estado_cuenta = 'ACTIVA'
   AND u.correo NOT LIKE '%.demo' AND u.correo NOT LIKE '%.test'
   AND NOT EXISTS (SELECT 1 FROM admin_permisos p
                    WHERE p.permiso = 'ADMINISTRAR_PERMISOS' AND p.revocado_en IS NULL);
SELECT ROW_COUNT() AS filas_propietario;   -- DEBE ser 1. Si es 0 → ROLLBACK y revisar.
-- Evento de auditoría de esa asignación (sin actor: la hace el script, no un admin).
INSERT INTO moderacion_eventos (admin_id, admin_permiso_id, entidad, permiso_id, operacion, datos_anteriores, datos_nuevos, motivo)
VALUES (NULL, NULL, 'PERMISO', LAST_INSERT_ID(), 'ASIGNACION_INICIAL', JSON_OBJECT(),
        JSON_OBJECT('usuario_id', :ID_PROPIETARIO, 'permiso', 'ADMINISTRAR_PERMISOS', 'origen', 'ASIGNACION_INICIAL'), :MOTIVO);

-- 4. MODERAR_CONTENIDO para el mismo propietario (asignación inicial, auditada igual).
INSERT INTO admin_permisos (usuario_id, permiso, origen, otorgado_por, motivo)
SELECT p.usuario_id, 'MODERAR_CONTENIDO', 'ASIGNACION_INICIAL', NULL, :MOTIVO
  FROM admin_permisos p
 WHERE p.usuario_id = :ID_PROPIETARIO
   AND p.permiso = 'ADMINISTRAR_PERMISOS' AND p.revocado_en IS NULL;
SELECT ROW_COUNT() AS filas_moderacion;    -- DEBE ser 1. Si es 0 → ROLLBACK y revisar.
INSERT INTO moderacion_eventos (admin_id, admin_permiso_id, entidad, permiso_id, operacion, datos_anteriores, datos_nuevos, motivo)
VALUES (NULL, NULL, 'PERMISO', LAST_INSERT_ID(), 'ASIGNACION_INICIAL', JSON_OBJECT(),
        JSON_OBJECT('usuario_id', :ID_PROPIETARIO, 'permiso', 'MODERAR_CONTENIDO', 'origen', 'ASIGNACION_INICIAL'), :MOTIVO);

-- 5. Revisar el resultado (2 permisos con origen ASIGNACION_INICIAL y 2 eventos ASIGNACION_INICIAL).
SELECT id, entidad, permiso_id, operacion, motivo, created_at FROM moderacion_eventos WHERE entidad = 'PERMISO' ORDER BY id;
SELECT id, usuario_id, permiso, origen, otorgado_por, otorgado_en, motivo
  FROM admin_permisos WHERE usuario_id = :ID_PROPIETARIO ORDER BY id;

-- 6. Solo si todo lo anterior es correcto:
COMMIT;
-- Si algo no coincide:  ROLLBACK;
