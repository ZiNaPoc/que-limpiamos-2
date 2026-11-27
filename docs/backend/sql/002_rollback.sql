-- ════════════════════════════════════════════════════════════════════════════
-- 002 — REVERSIÓN de 002_detalle_solicitud_especialidades_invitaciones.sql (v10)
-- ════════════════════════════════════════════════════════════════════════════
-- Úsese SOLO si hay que deshacer el 002. Antes:
--   1) Hacer un respaldo NUEVO (npm run db:respaldo): esto borra datos de las tablas
--      nuevas (libro de movimientos, descuentos, historiales…).
--   2) npm run db:verificar-002 → confirma qué objetos existen. Si el 002 quedó a
--      medias, borra de este archivo las líneas de objetos que NO existen (MySQL no
--      tiene DROP COLUMN / DROP FOREIGN KEY IF EXISTS).
--   3) Fallan A PROPÓSITO (para no perder datos sin decidirlo):
--        C4 si algún trabajador tiene dos franjas el mismo día;
--        G1 si hay trabajadores en BAJA; G2 si hay notificaciones de tipos nuevos.
-- El 002 NO modifica los updated_at existentes (ya tenían ON UPDATE): no revertir nada de eso.
-- Orden: primero lo que depende de otros objetos.
-- ════════════════════════════════════════════════════════════════════════════

-- E. Trabajadores: notificaciones, historial de estados y libro
DROP TABLE IF EXISTS notificaciones_trabajador;
DROP TABLE IF EXISTS trabajador_estado_historial;
DROP TABLE IF EXISTS trabajador_movimientos;

-- D10. evidencias_solicitud (tabla existente): primero la FK hacia solicitud_reportes.
ALTER TABLE evidencias_solicitud DROP FOREIGN KEY fk_evid_reporte;
ALTER TABLE evidencias_solicitud DROP INDEX idx_evid_reporte;
ALTER TABLE evidencias_solicitud DROP COLUMN reporte_id;
ALTER TABLE evidencias_solicitud DROP COLUMN aportada_por;

-- D. Detalle e historia de solicitud
DROP TABLE IF EXISTS solicitud_reportes;
DROP TABLE IF EXISTS solicitud_resoluciones;
DROP TABLE IF EXISTS cliente_adeudos;
DROP TABLE IF EXISTS descuento_usos;
DROP TABLE IF EXISTS solicitud_historial;
DROP TABLE IF EXISTS solicitud_trabajadores;
DROP TABLE IF EXISTS solicitud_especialidades;
DROP TABLE IF EXISTS solicitud_extras;
DROP TABLE IF EXISTS solicitud_areas;

-- B. Relaciones de especialidades
DROP TABLE IF EXISTS extra_especialidades;
DROP TABLE IF EXISTS servicio_especialidades;
DROP TABLE IF EXISTS trabajador_especialidades;

-- A. Catálogo, parámetros y descuentos
DROP TABLE IF EXISTS descuento_servicios;
DROP TABLE IF EXISTS descuentos;
DROP TABLE IF EXISTS parametros_negocio;
DROP TABLE IF EXISTS reglas_cargo_cancelacion;
DROP TABLE IF EXISTS servicio_calculo_tipo_inmueble;
DROP TABLE IF EXISTS servicio_calculo;
DROP TABLE IF EXISTS servicios_extra;
DROP TABLE IF EXISTS areas_limpieza;
DROP TABLE IF EXISTS especialidades;

-- C6. notificaciones (columna e índice; el enum va en G2)
ALTER TABLE notificaciones DROP INDEX idx_notif_usuario_leida;
ALTER TABLE notificaciones DROP COLUMN leida_en;

-- C5. documentos
ALTER TABLE documentos_trabajador DROP COLUMN archivo_eliminado_en;
ALTER TABLE documentos_trabajador DROP FOREIGN KEY fk_doc_trabajador_revisor;
ALTER TABLE documentos_trabajador DROP INDEX idx_doc_trabajador_revisor;
ALTER TABLE documentos_trabajador DROP COLUMN revisado_por;
ALTER TABLE documentos_trabajador DROP COLUMN revisado_en;
ALTER TABLE documentos_trabajador DROP COLUMN motivo_rechazo;
ALTER TABLE documentos_trabajador DROP COLUMN estado;

ALTER TABLE documentos_cliente DROP COLUMN archivo_eliminado_en;
ALTER TABLE documentos_cliente DROP FOREIGN KEY fk_doc_cliente_revisor;
ALTER TABLE documentos_cliente DROP INDEX idx_doc_cliente_revisor;
ALTER TABLE documentos_cliente DROP COLUMN revisado_por;
ALTER TABLE documentos_cliente DROP COLUMN revisado_en;
ALTER TABLE documentos_cliente DROP COLUMN motivo_rechazo;
ALTER TABLE documentos_cliente DROP COLUMN estado;

-- C4. trabajador_horarios: volver a UNA franja por día (falla si hay días con 2+ franjas).
--     Primero el único (para que la FK siga teniendo índice) y después se quita el nuevo.
ALTER TABLE trabajador_horarios ADD UNIQUE KEY uq_horario_dia (trabajador_id, dia_semana);
ALTER TABLE trabajador_horarios DROP INDEX idx_horario_trabajador_dia;

-- C3. trabajadores (el enum va en G1). Primero el índice de identidad y luego sus columnas.
ALTER TABLE trabajadores DROP INDEX uq_trabajadores_identidad;
ALTER TABLE trabajadores DROP COLUMN identidad_registrada_en;
ALTER TABLE trabajadores DROP COLUMN identidad_huella;
ALTER TABLE trabajadores DROP COLUMN baja_motivo;
ALTER TABLE trabajadores DROP COLUMN baja_tipo;
ALTER TABLE trabajadores DROP COLUMN baja_en;
ALTER TABLE trabajadores DROP COLUMN mostrar_fuera_de_horario;
ALTER TABLE trabajadores DROP COLUMN estado_verificacion;

-- C2. inmuebles
ALTER TABLE inmuebles DROP COLUMN archivado_en;

-- C1c. usuarios: identidad (primero el índice y luego sus columnas)
ALTER TABLE usuarios DROP INDEX uq_usuarios_identidad;
ALTER TABLE usuarios DROP COLUMN identidad_registrada_en;
ALTER TABLE usuarios DROP COLUMN identidad_huella;

-- C1b. usuarios
ALTER TABLE usuarios DROP CONSTRAINT chk_usuario_cliente_telefono;

-- C1. solicitudes
ALTER TABLE solicitudes DROP COLUMN ganancia_liberada_en;
ALTER TABLE solicitudes DROP COLUMN realizado_via;
ALTER TABLE solicitudes DROP COLUMN realizado_en;
ALTER TABLE solicitudes DROP COLUMN aviso_evidencia_en;
ALTER TABLE solicitudes DROP COLUMN confirmacion_solicitada_en;
ALTER TABLE solicitudes DROP COLUMN cliente_marco_realizado_en;
ALTER TABLE solicitudes DROP COLUMN trabajador_marco_realizado_en;
ALTER TABLE solicitudes DROP COLUMN pago_registrado_por;
ALTER TABLE solicitudes DROP COLUMN pago_registrado_en;
ALTER TABLE solicitudes DROP COLUMN estado_pago;
ALTER TABLE solicitudes DROP COLUMN adeudo_cobrado;
ALTER TABLE solicitudes DROP COLUMN modo_eleccion;
ALTER TABLE solicitudes DROP COLUMN metodo_pago;
ALTER TABLE solicitudes DROP COLUMN cargo_cancelacion;
ALTER TABLE solicitudes DROP COLUMN comision_plataforma;
ALTER TABLE solicitudes DROP COLUMN ganancia_trabajador;
ALTER TABLE solicitudes DROP COLUMN porcentaje_trabajador_aplicado;
ALTER TABLE solicitudes DROP COLUMN precio_descuento_aplicado;
ALTER TABLE solicitudes DROP COLUMN precio_extras_aplicado;
ALTER TABLE solicitudes DROP COLUMN precio_ajuste_tipo_aplicado;
ALTER TABLE solicitudes DROP COLUMN precio_tamano_aplicado;
ALTER TABLE solicitudes DROP COLUMN precio_base_aplicado;
ALTER TABLE solicitudes DROP COLUMN notas;
ALTER TABLE solicitudes DROP COLUMN fecha_hora_fin_estimada;
ALTER TABLE solicitudes DROP COLUMN duracion_estimada_min;
ALTER TABLE solicitudes DROP COLUMN pisos_aplicado;
ALTER TABLE solicitudes DROP COLUMN medios_banos_aplicado;
ALTER TABLE solicitudes DROP COLUMN banos_aplicado;
ALTER TABLE solicitudes DROP COLUMN habitaciones_aplicado;
ALTER TABLE solicitudes DROP COLUMN inmueble_tipo_aplicado;
ALTER TABLE solicitudes DROP COLUMN servicio_nombre_aplicado;

-- G1. Enum original de trabajadores.estado (falla si hay trabajadores en BAJA).
ALTER TABLE trabajadores
  MODIFY COLUMN estado ENUM('ACTIVO','INACTIVO') NOT NULL DEFAULT 'ACTIVO';

-- G2. Enum original de notificaciones.tipo (falla si hay filas con tipos nuevos).
ALTER TABLE notificaciones
  MODIFY COLUMN tipo ENUM('SERVICIO_CONFIRMADO','CALIFICAR_SERVICIO') NOT NULL;
