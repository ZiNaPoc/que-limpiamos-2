-- ════════════════════════════════════════════════════════════════════════════
-- 000 — ESTRUCTURA de producción (queLimpiamos), SOLO DDL, sin ninguna fila.
-- Origen: respaldo lógico del 2026-11-24T14:32:57Z (backend/backups, generado con npm run db:respaldo),
--         motor 8.0.11-TiDB-v8.5.3-serverless. Se extrajeron únicamente las 13 sentencias CREATE TABLE.
-- Coincide con la inspección de solo lectura del 2026-11-25 (13 tablas; resenas y evidencias idénticas).
-- Uso: base de la BD LOCAL (TiDB en Docker) para desarrollo y pruebas; después se aplican 002 v10 y 003 v2.
-- NO contiene datos (ni usuarios, ni hashes, ni el catálogo).
-- ════════════════════════════════════════════════════════════════════════════
SET FOREIGN_KEY_CHECKS = 0;
CREATE TABLE `documentos_cliente` (
  `id` int NOT NULL AUTO_INCREMENT,
  `usuario_id` int NOT NULL,
  `tipo` enum('INE_FRENTE','INE_REVERSO') COLLATE utf8mb4_unicode_ci NOT NULL,
  `archivo_url` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY `uq_doc_cliente_tipo` (`usuario_id`,`tipo`),
  CONSTRAINT `fk_doc_cliente_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `documentos_trabajador` (
  `id` int NOT NULL AUTO_INCREMENT,
  `trabajador_id` int NOT NULL,
  `tipo` enum('IDENTIFICACION','COMPROBANTE_DOMICILIO') COLLATE utf8mb4_unicode_ci NOT NULL,
  `archivo_url` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY `uq_doc_trabajador_tipo` (`trabajador_id`,`tipo`),
  CONSTRAINT `fk_doc_trabajador` FOREIGN KEY (`trabajador_id`) REFERENCES `trabajadores` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `evidencias_solicitud` (
  `id` int NOT NULL AUTO_INCREMENT,
  `solicitud_id` int NOT NULL,
  `archivo_url` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `descripcion` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  KEY `fk_evid_solicitud` (`solicitud_id`),
  CONSTRAINT `fk_evid_solicitud` FOREIGN KEY (`solicitud_id`) REFERENCES `solicitudes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `inmuebles` (
  `id` int NOT NULL AUTO_INCREMENT,
  `usuario_id` int NOT NULL,
  `alias` varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `tipo` enum('CASA','OFICINA','DEPARTAMENTO') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'CASA',
  `direccion` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `habitaciones` tinyint unsigned NOT NULL DEFAULT '0',
  `banos` tinyint unsigned NOT NULL DEFAULT '0',
  `medios_banos` tinyint unsigned NOT NULL DEFAULT '0',
  `pisos` tinyint unsigned NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  KEY `idx_inmueble_usuario` (`usuario_id`),
  CONSTRAINT `fk_inmueble_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chk_inmueble_pisos` CHECK ((`pisos` >= 1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `notificaciones` (
  `id` int NOT NULL AUTO_INCREMENT,
  `usuario_id` int NOT NULL,
  `solicitud_id` int DEFAULT NULL,
  `tipo` enum('SERVICIO_CONFIRMADO','CALIFICAR_SERVICIO') COLLATE utf8mb4_unicode_ci NOT NULL,
  `titulo` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `mensaje` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  KEY `fk_notif_usuario` (`usuario_id`),
  KEY `fk_notif_solicitud` (`solicitud_id`),
  CONSTRAINT `fk_notif_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_notif_solicitud` FOREIGN KEY (`solicitud_id`) REFERENCES `solicitudes` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `password_reset_tokens` (
  `id` int NOT NULL AUTO_INCREMENT,
  `usuario_id` int NOT NULL,
  `token_hash` char(64) COLLATE utf8mb4_unicode_ci NOT NULL,
  `expira_en` datetime NOT NULL,
  `usado` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY `uq_reset_token` (`token_hash`),
  KEY `fk_reset_usuario` (`usuario_id`),
  CONSTRAINT `fk_reset_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `resenas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `solicitud_id` int NOT NULL,
  `puntuacion_servicio` tinyint NOT NULL,
  `puntuacion_trabajador` tinyint NOT NULL,
  `comentario` text COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY `uq_resena_solicitud` (`solicitud_id`),
  CONSTRAINT `fk_resena_solicitud` FOREIGN KEY (`solicitud_id`) REFERENCES `solicitudes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `servicios` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `descripcion` text COLLATE utf8mb4_unicode_ci NOT NULL,
  `precio_base` decimal(10,2) NOT NULL,
  `duracion_estimada_min` smallint unsigned NOT NULL DEFAULT '300',
  `imagen_url` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `estado` enum('ACTIVO','INACTIVO') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ACTIVO',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY `uq_servicios_nombre` (`nombre`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci AUTO_INCREMENT=30001;

CREATE TABLE `solicitudes` (
  `id` int NOT NULL AUTO_INCREMENT,
  `cliente_id` int NOT NULL,
  `servicio_id` int NOT NULL,
  `inmueble_id` int DEFAULT NULL,
  `trabajador_id` int DEFAULT NULL,
  `fecha_hora_programada` datetime NOT NULL,
  `direccion_servicio` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `precio_estimado` decimal(10,2) NOT NULL,
  `estado` enum('PENDIENTE','CONFIRMADO','EN_PROCESO','REALIZADO','CANCELADO','RECHAZADO') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'PENDIENTE',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  KEY `idx_sol_cliente_estado` (`cliente_id`,`estado`),
  KEY `idx_sol_estado_fecha` (`estado`,`fecha_hora_programada`),
  KEY `idx_sol_trabajador_fecha` (`trabajador_id`,`fecha_hora_programada`),
  KEY `fk_sol_servicio` (`servicio_id`),
  KEY `idx_sol_inmueble` (`inmueble_id`),
  CONSTRAINT `fk_sol_cliente` FOREIGN KEY (`cliente_id`) REFERENCES `usuarios` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_sol_servicio` FOREIGN KEY (`servicio_id`) REFERENCES `servicios` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_sol_trabajador` FOREIGN KEY (`trabajador_id`) REFERENCES `trabajadores` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_sol_inmueble` FOREIGN KEY (`inmueble_id`) REFERENCES `inmuebles` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `trabajador_horarios` (
  `id` int NOT NULL AUTO_INCREMENT,
  `trabajador_id` int NOT NULL,
  `dia_semana` tinyint NOT NULL,
  `hora_inicio` time NOT NULL,
  `hora_fin` time NOT NULL,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY `uq_horario_dia` (`trabajador_id`,`dia_semana`),
  CONSTRAINT `fk_horario_trabajador` FOREIGN KEY (`trabajador_id`) REFERENCES `trabajadores` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `trabajador_servicios` (
  `trabajador_id` int NOT NULL,
  `servicio_id` int NOT NULL,
  PRIMARY KEY (`trabajador_id`,`servicio_id`) /*T![clustered_index] CLUSTERED */,
  KEY `fk_ts_servicio` (`servicio_id`),
  CONSTRAINT `fk_ts_trabajador` FOREIGN KEY (`trabajador_id`) REFERENCES `trabajadores` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ts_servicio` FOREIGN KEY (`servicio_id`) REFERENCES `servicios` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `trabajadores` (
  `id` int NOT NULL AUTO_INCREMENT,
  `nombre_completo` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL,
  `telefono` char(10) COLLATE utf8mb4_unicode_ci NOT NULL,
  `correo` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `direccion` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `foto_url` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `estado` enum('ACTIVO','INACTIVO') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ACTIVO',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY `uq_trabajadores_telefono` (`telefono`),
  UNIQUE KEY `uq_trabajadores_correo` (`correo`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `usuarios` (
  `id` int NOT NULL AUTO_INCREMENT,
  `rol` enum('CLIENTE','ADMIN') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'CLIENTE',
  `nombre_completo` varchar(120) COLLATE utf8mb4_unicode_ci NOT NULL,
  `correo` varchar(150) COLLATE utf8mb4_unicode_ci NOT NULL,
  `telefono` char(10) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `password_hash` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `foto_url` varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  `estado_cuenta` enum('ACTIVA','SUSPENDIDA') COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'ACTIVA',
  `estado_verificacion` enum('PENDIENTE','VERIFICADO','RECHAZADO') COLLATE utf8mb4_unicode_ci DEFAULT 'PENDIENTE',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) /*T![clustered_index] CLUSTERED */,
  UNIQUE KEY `uq_usuarios_correo` (`correo`),
  UNIQUE KEY `uq_usuarios_telefono` (`telefono`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci AUTO_INCREMENT=30001;

SET FOREIGN_KEY_CHECKS = 1;
