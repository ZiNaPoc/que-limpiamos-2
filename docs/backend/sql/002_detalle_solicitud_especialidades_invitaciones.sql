-- ════════════════════════════════════════════════════════════════════════════
-- 002 — Catálogo y cálculo (precio y duración), descuentos, detalle e historia de
--       solicitudes, participación de trabajadores, cancelaciones, libro de
--       movimientos, disponibilidad (varias franjas), bajas y reactivaciones,
--       documentos, inmuebles, adeudos de clientes, identidad (huella de la INE),
--       confirmación del servicio, estado del pago, reportes, resoluciones del admin
--       y notificaciones (VERSIÓN v10)
-- ════════════════════════════════════════════════════════════════════════════
-- ESTADO: PROPUESTO. NO ejecutado en producción. Se prueba primero completo en
--         una BD de ensayo: npm run db:ensayo-002 (ver 12_RESPALDO_Y_RECUPERACION.md §6).
-- Motor verificado: TiDB Cloud Serverless v8.5.3 (compatible MySQL 8.0),
--         foreign_key_checks=1, transacciones pesimistas, time_zone UTC
--         (NOW() = UTC y Prisma lee/escribe DATETIME como UTC), utf8mb4_unicode_ci.
-- Sintaxis: subconjunto estándar MySQL 8.0 (también válido en MariaDB ≥ 10.5).
-- Explicación de cada objeto: docs/backend/11_PROPUESTA_CAMBIOS_SCHEMA.md
-- Reversión: docs/backend/sql/002_rollback.sql
--
-- Reglas del script:
--   * En usuarios se AGREGA una restricción CHECK: un CLIENTE debe tener teléfono (los
--     clientes se registran por número; el único admin existente no se ve afectado).
--   * En usuarios y trabajadores se AGREGA un índice UNIQUE sobre una columna NUEVA
--     (identidad_huella, NULL en todas las filas existentes): una cuenta por persona.
--   * Solo AGREGA, con UNA excepción autorizada: en trabajador_horarios se cambia el
--     índice único (trabajador_id, dia_semana) por uno NO único, para permitir varias
--     franjas por día (la tabla tiene 0 filas). No se borran tablas ni columnas.
--   * Columnas nuevas en tablas existentes: NULL o con DEFAULT (no rompen filas).
--     evidencias_solicitud (existente, 0 filas) gana aportada_por y reporte_id (v9).
--   * Cambios a columnas existentes: agregar valores al FINAL de dos enums
--     (notificaciones.tipo, trabajadores.estado). Sin pérdida.
--   * Los updated_at existentes YA tienen ON UPDATE CURRENT_TIMESTAMP: no se tocan.
--   * Ninguna fila existente se modifica. Solo se insertan filas en tablas NUEVAS.
--   * Las FKs nuevas hacia `trabajadores` son RESTRICT: se dan de BAJA, no se borran.
--   * El DDL de MySQL/TiDB no es transaccional (ver 12_RESPALDO_Y_RECUPERACION.md §4).
-- ════════════════════════════════════════════════════════════════════════════


-- ── A. CATÁLOGO Y PARÁMETROS (los administra el admin desde su dashboard) ───

-- A1. Especialidades: equipo o habilidad (p. ej. "Máquina de vapor").
CREATE TABLE especialidades (
  id          INT          NOT NULL AUTO_INCREMENT,
  nombre      VARCHAR(100) NOT NULL,
  descripcion VARCHAR(255) NULL,
  estado      ENUM('ACTIVO','INACTIVO') NOT NULL DEFAULT 'ACTIVO',
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_especialidades_nombre (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A2. Áreas de la casa que el cliente marca. Renombrables (la solicitud guarda el nombre usado).
CREATE TABLE areas_limpieza (
  id     INT              NOT NULL AUTO_INCREMENT,
  nombre VARCHAR(60)      NOT NULL,
  orden  TINYINT UNSIGNED NOT NULL DEFAULT 0,
  estado ENUM('ACTIVO','INACTIVO') NOT NULL DEFAULT 'ACTIVO',
  PRIMARY KEY (id),
  UNIQUE KEY uq_areas_limpieza_nombre (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A3. Servicios extra: precio vigente y minutos que AGREGAN a la duración.
CREATE TABLE servicios_extra (
  id                    INT               NOT NULL AUTO_INCREMENT,
  nombre                VARCHAR(100)      NOT NULL,
  descripcion           VARCHAR(255)      NULL,
  precio                DECIMAL(10,2)     NOT NULL,
  duracion_estimada_min SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  estado                ENUM('ACTIVO','INACTIVO') NOT NULL DEFAULT 'ACTIVO',
  created_at            DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_servicios_extra_nombre (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A4. Cálculo por servicio (1:1): precio y minutos por cada habitación, baño, medio baño
--     y piso. La base sigue en servicios.precio_base y servicios.duracion_estimada_min.
CREATE TABLE servicio_calculo (
  servicio_id            INT               NOT NULL,
  precio_por_habitacion  DECIMAL(10,2)     NOT NULL DEFAULT 0.00,
  precio_por_bano        DECIMAL(10,2)     NOT NULL DEFAULT 0.00,
  precio_por_medio_bano  DECIMAL(10,2)     NOT NULL DEFAULT 0.00,
  precio_por_piso        DECIMAL(10,2)     NOT NULL DEFAULT 0.00,
  minutos_por_habitacion SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  minutos_por_bano       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  minutos_por_medio_bano SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  minutos_por_piso       SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  updated_at             DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (servicio_id),
  CONSTRAINT fk_calculo_servicio FOREIGN KEY (servicio_id) REFERENCES servicios (id)
    ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A5. Ajuste por tipo de inmueble, por servicio. Sin fila = multiplicadores 1.00.
CREATE TABLE servicio_calculo_tipo_inmueble (
  servicio_id            INT          NOT NULL,
  tipo_inmueble          ENUM('CASA','OFICINA','DEPARTAMENTO') NOT NULL,
  multiplicador_precio   DECIMAL(5,2) NOT NULL DEFAULT 1.00,
  multiplicador_duracion DECIMAL(5,2) NOT NULL DEFAULT 1.00,
  updated_at             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (servicio_id, tipo_inmueble),
  CONSTRAINT fk_calculo_tipo_servicio FOREIGN KEY (servicio_id) REFERENCES servicios (id)
    ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A6. Reglas de cargo por cancelar una solicitud CONFIRMADA según las horas que FALTAN.
--     Se aplica la regla ACTIVA con el menor `horas_antes` MAYOR que las horas restantes.
--     PORCENTAJE se calcula sobre solicitudes.precio_estimado (lo que paga el cliente).
CREATE TABLE reglas_cargo_cancelacion (
  id          INT               NOT NULL AUTO_INCREMENT,
  aplica_a    ENUM('CLIENTE','TRABAJADOR') NOT NULL,
  horas_antes SMALLINT UNSIGNED NOT NULL,
  tipo        ENUM('PORCENTAJE','MONTO_FIJO') NOT NULL DEFAULT 'PORCENTAJE',
  valor       DECIMAL(10,2)     NOT NULL DEFAULT 0.00,
  estado      ENUM('ACTIVO','INACTIVO') NOT NULL DEFAULT 'ACTIVO',
  created_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_regla_cargo (aplica_a, horas_antes)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A7. Parámetros numéricos del negocio, editables por el admin sin desplegar código.
CREATE TABLE parametros_negocio (
  clave       VARCHAR(60)   NOT NULL,
  valor       DECIMAL(10,2) NOT NULL,
  descripcion VARCHAR(255)  NOT NULL,
  updated_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (clave)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A8. Descuentos que crea el admin. La plataforma absorbe la pérdida: el trabajador
--     gana su porcentaje sobre el precio SIN descuento.
--     codigo NULL = descuento automático (sin código); el UNIQUE permite varios NULL.
CREATE TABLE descuentos (
  id                      INT              NOT NULL AUTO_INCREMENT,
  nombre                  VARCHAR(100)     NOT NULL,
  descripcion             VARCHAR(255)     NULL,
  tipo                    ENUM('PORCENTAJE','MONTO_FIJO') NOT NULL,
  valor                   DECIMAL(10,2)    NOT NULL,
  codigo                  VARCHAR(40)      NULL,
  fecha_inicio            DATETIME         NOT NULL,
  fecha_fin               DATETIME         NOT NULL,
  monto_minimo            DECIMAL(10,2)    NULL,
  todos_los_servicios     TINYINT(1)       NOT NULL DEFAULT 0,
  limite_usos             INT UNSIGNED     NULL,
  limite_usos_por_cliente INT UNSIGNED     NULL,
  activo                  TINYINT(1)       NOT NULL DEFAULT 1,
  creado_por              INT              NULL,
  created_at              DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              DATETIME         NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_descuentos_codigo (codigo),
  KEY idx_descuentos_vigencia (activo, fecha_inicio, fecha_fin),
  KEY idx_descuentos_creado_por (creado_por),
  CONSTRAINT fk_descuento_creado_por FOREIGN KEY (creado_por) REFERENCES usuarios (id)
    ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A9. Servicios a los que aplica un descuento (si todos_los_servicios = 0).
CREATE TABLE descuento_servicios (
  descuento_id INT NOT NULL,
  servicio_id  INT NOT NULL,
  PRIMARY KEY (descuento_id, servicio_id),
  KEY idx_ds_servicio (servicio_id),
  CONSTRAINT fk_ds_descuento FOREIGN KEY (descuento_id) REFERENCES descuentos (id)
    ON DELETE CASCADE ON UPDATE NO ACTION,
  CONSTRAINT fk_ds_servicio  FOREIGN KEY (servicio_id)  REFERENCES servicios (id)
    ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ── B. RELACIONES DE ESPECIALIDADES ─────────────────────────────────────────

-- B1. Especialidades que declara el trabajador (cuentan de inmediato).
CREATE TABLE trabajador_especialidades (
  trabajador_id   INT      NOT NULL,
  especialidad_id INT      NOT NULL,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (trabajador_id, especialidad_id),
  KEY idx_te_especialidad (especialidad_id),
  CONSTRAINT fk_te_trabajador   FOREIGN KEY (trabajador_id)   REFERENCES trabajadores (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_te_especialidad FOREIGN KEY (especialidad_id) REFERENCES especialidades (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- B2. Especialidades que exige un servicio (0..N).
CREATE TABLE servicio_especialidades (
  servicio_id     INT NOT NULL,
  especialidad_id INT NOT NULL,
  PRIMARY KEY (servicio_id, especialidad_id),
  KEY idx_sesp_especialidad (especialidad_id),
  CONSTRAINT fk_sesp_servicio     FOREIGN KEY (servicio_id)     REFERENCES servicios (id)
    ON DELETE CASCADE  ON UPDATE NO ACTION,
  CONSTRAINT fk_sesp_especialidad FOREIGN KEY (especialidad_id) REFERENCES especialidades (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- B3. Especialidades que exige un extra (0..N).
CREATE TABLE extra_especialidades (
  extra_id        INT NOT NULL,
  especialidad_id INT NOT NULL,
  PRIMARY KEY (extra_id, especialidad_id),
  KEY idx_eesp_especialidad (especialidad_id),
  CONSTRAINT fk_eesp_extra        FOREIGN KEY (extra_id)        REFERENCES servicios_extra (id)
    ON DELETE CASCADE  ON UPDATE NO ACTION,
  CONSTRAINT fk_eesp_especialidad FOREIGN KEY (especialidad_id) REFERENCES especialidades (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ── C. CAMBIOS EN TABLAS EXISTENTES (columnas NULL o con DEFAULT) ───────────

-- C1. solicitudes: snapshot del servicio y del inmueble, duración, precio, descuento,
--     reparto, método de pago elegido y modo de elección.
ALTER TABLE solicitudes ADD COLUMN servicio_nombre_aplicado VARCHAR(100) NULL AFTER servicio_id;
ALTER TABLE solicitudes ADD COLUMN inmueble_tipo_aplicado ENUM('CASA','OFICINA','DEPARTAMENTO') NULL AFTER inmueble_id;
ALTER TABLE solicitudes ADD COLUMN habitaciones_aplicado TINYINT UNSIGNED NULL AFTER inmueble_tipo_aplicado;
ALTER TABLE solicitudes ADD COLUMN banos_aplicado        TINYINT UNSIGNED NULL AFTER habitaciones_aplicado;
ALTER TABLE solicitudes ADD COLUMN medios_banos_aplicado TINYINT UNSIGNED NULL AFTER banos_aplicado;
ALTER TABLE solicitudes ADD COLUMN pisos_aplicado        TINYINT UNSIGNED NULL AFTER medios_banos_aplicado;
ALTER TABLE solicitudes ADD COLUMN duracion_estimada_min SMALLINT UNSIGNED NULL AFTER fecha_hora_programada;
ALTER TABLE solicitudes ADD COLUMN fecha_hora_fin_estimada DATETIME NULL AFTER duracion_estimada_min;
ALTER TABLE solicitudes ADD COLUMN notas TEXT NULL AFTER direccion_servicio;
ALTER TABLE solicitudes ADD COLUMN precio_base_aplicado        DECIMAL(10,2) NULL AFTER precio_estimado;
ALTER TABLE solicitudes ADD COLUMN precio_tamano_aplicado      DECIMAL(10,2) NULL AFTER precio_base_aplicado;
ALTER TABLE solicitudes ADD COLUMN precio_ajuste_tipo_aplicado DECIMAL(10,2) NULL AFTER precio_tamano_aplicado;
ALTER TABLE solicitudes ADD COLUMN precio_extras_aplicado      DECIMAL(10,2) NULL AFTER precio_ajuste_tipo_aplicado;
ALTER TABLE solicitudes ADD COLUMN precio_descuento_aplicado   DECIMAL(10,2) NULL AFTER precio_extras_aplicado;
ALTER TABLE solicitudes ADD COLUMN porcentaje_trabajador_aplicado DECIMAL(5,2) NULL AFTER precio_descuento_aplicado;
ALTER TABLE solicitudes ADD COLUMN ganancia_trabajador  DECIMAL(10,2) NULL AFTER porcentaje_trabajador_aplicado;
ALTER TABLE solicitudes ADD COLUMN comision_plataforma  DECIMAL(10,2) NULL AFTER ganancia_trabajador;
ALTER TABLE solicitudes ADD COLUMN cargo_cancelacion    DECIMAL(10,2) NULL AFTER comision_plataforma;
ALTER TABLE solicitudes ADD COLUMN metodo_pago ENUM('EFECTIVO','TARJETA') NOT NULL DEFAULT 'EFECTIVO' AFTER cargo_cancelacion;
ALTER TABLE solicitudes ADD COLUMN modo_eleccion ENUM('AUTOMATICA','MANUAL') NOT NULL DEFAULT 'AUTOMATICA' AFTER estado;
--     adeudo_cobrado: adeudos anteriores del cliente que paga en efectivo en ESTE servicio.
ALTER TABLE solicitudes ADD COLUMN adeudo_cobrado DECIMAL(10,2) NULL AFTER metodo_pago;
--     Cuatro estados INDEPENDIENTES (v9): servicio (solicitudes.estado y las columnas de
--     abajo), pago (estado_pago), reportes (solicitud_reportes.estado) y resolución del
--     admin (solicitud_resoluciones). Ninguno se deduce de otro.
--
--     ESTADO DEL PAGO (v9, decidido por el usuario el 2026-11-24):
--       PENDIENTE → todavía no se registra el pago.
--       PAGADO    → se registró el pago en efectivo: el trabajador tiene el dinero completo.
--                   En la MISMA transacción se registra UNA vez la comisión
--                   (COMISION_EFECTIVO, deuda del trabajador) y, si el servicio cobraba
--                   adeudos, COBRO_ADEUDO_CLIENTE. NO depende de que el trabajador marque
--                   el servicio como terminado.
--       ANULADO   → una resolución del admin determinó que el cobro no existió; la comisión
--                   se corrige con un AJUSTE (el historial financiero no se borra).
--     La transición es UPDATE … WHERE estado_pago = 'PENDIENTE': si dos lo intentan a la vez,
--     solo uno cambia la fila; y la BD impide una segunda comisión (uq_mov_una_vez_por_solicitud).
--     Quién lo registra (pago_registrado_por, D59, decidido por el usuario el 2026-11-24).
--     Basta con que UNA parte lo registre:
--       CLIENTE    «Ya pagué en efectivo» (app del cliente).
--       TRABAJADOR «Ya recibí el efectivo» (app del trabajador).
--       SISTEMA    nadie lo registró y el servicio se confirmó AUTOMÁTICAMENTE: se presume
--                  pagado, SOLO si el trabajador inició el servicio (EN_PROCESO) y no hay
--                  reportes, disputas, cancelación ni incidencia pendientes. Así no confirmar
--                  no sirve para evitar la comisión.
--       ADMIN      lo determinó una resolución.
--     Si el trabajador no recibió el efectivo, lo reporta (PAGO_EN_DISPUTA): el admin revisa
--     las pruebas y mantiene la comisión o la anula con un AJUSTE (el historial no se borra).
ALTER TABLE solicitudes
  ADD COLUMN estado_pago ENUM('PENDIENTE','PAGADO','ANULADO') NOT NULL DEFAULT 'PENDIENTE' AFTER adeudo_cobrado;
ALTER TABLE solicitudes ADD COLUMN pago_registrado_en DATETIME NULL AFTER estado_pago;
ALTER TABLE solicitudes
  ADD COLUMN pago_registrado_por ENUM('CLIENTE','TRABAJADOR','SISTEMA','ADMIN') NULL AFTER pago_registrado_en;
--     ESTADO DEL SERVICIO: marca de cada parte ("terminado") y confirmación (v8).
--       T = fecha_hora_fin_estimada.
--       * El cliente confirma → REALIZADO (realizado_via = CLIENTE) y se libera la ganancia.
--       * Solo el trabajador confirmó (con evidencia en evidencias_solicitud): en T + 30 min
--         (o al confirmar, si fue después) se avisa al cliente (aviso_evidencia_en) que tiene
--         15 min; si no confirma → REALIZADO (EVIDENCIA_TRABAJADOR) y se libera la ganancia.
--       * Nadie confirmó: en T + 30 min se pide a ambos (confirmacion_solicitada_en); si en
--         30 min nadie responde → REALIZADO (AUTOMATICO) SIN liberar la ganancia, que se
--         libera cuando el trabajador sube evidencia o el cliente confirma. En la MISMA
--         transacción, si el pago en efectivo seguía PENDIENTE, se presume pagado
--         (pago_registrado_por = SISTEMA) y se registra la comisión una sola vez (D59).
--       * Con un reporte SIN RESOLVER no se confirma ni por evidencia ni automáticamente:
--         decide el admin (realizado_via = RESOLUCION_ADMIN).
--       ganancia_liberada_en: cuándo se liberó lo que la plataforma le debe al trabajador por
--       este servicio (COMPENSACION_DESCUENTO; con tarjeta, GANANCIA_SERVICIO). Se escribe UNA
--       sola vez (UPDATE … WHERE ganancia_liberada_en IS NULL). La comisión NO espera a esto.
--       Los minutos están en parametros_negocio (los edita el admin).
ALTER TABLE solicitudes ADD COLUMN trabajador_marco_realizado_en DATETIME NULL AFTER pago_registrado_por;
ALTER TABLE solicitudes ADD COLUMN cliente_marco_realizado_en DATETIME NULL AFTER trabajador_marco_realizado_en;
ALTER TABLE solicitudes ADD COLUMN confirmacion_solicitada_en DATETIME NULL AFTER cliente_marco_realizado_en;
ALTER TABLE solicitudes ADD COLUMN aviso_evidencia_en DATETIME NULL AFTER confirmacion_solicitada_en;
ALTER TABLE solicitudes ADD COLUMN realizado_en DATETIME NULL AFTER aviso_evidencia_en;
ALTER TABLE solicitudes
  ADD COLUMN realizado_via ENUM('CLIENTE','EVIDENCIA_TRABAJADOR','AUTOMATICO','RESOLUCION_ADMIN') NULL AFTER realizado_en;
ALTER TABLE solicitudes ADD COLUMN ganancia_liberada_en DATETIME NULL AFTER realizado_via;

-- C1b. usuarios: un CLIENTE siempre tiene teléfono (único por la restricción existente
--      uq_usuarios_telefono), para que no pueda abrir otra cuenta y evadir un adeudo.
ALTER TABLE usuarios
  ADD CONSTRAINT chk_usuario_cliente_telefono CHECK (rol <> 'CLIENTE' OR telefono IS NOT NULL);

-- C1c. Identidad (v8): huella de la INE para que una persona no abra otra cuenta.
--      identidad_huella = HMAC-SHA256 (hex, 64 caracteres) del identificador normalizado
--      (CURP en mayúsculas, sin espacios ni guiones). El HMAC se calcula en el BACKEND,
--      FUERA de la BD, con una clave secreta que también vive fuera (variable de entorno):
--      el CURP nunca se envía a la BD ni se usa una función SQL para calcularlo. La BD no
--      guarda el CURP y no puede revertir la huella. El CURP original (solo para
--      cuestiones legales) se guarda cifrado FUERA de la BD principal, el tiempo que fije
--      la política de privacidad. La foto de la INE se borra al terminar la revisión
--      (documentos_*.archivo_eliminado_en).
--      UNIQUE por audiencia: la misma persona puede ser cliente y también trabajador.
ALTER TABLE usuarios ADD COLUMN identidad_huella CHAR(64) NULL AFTER estado_verificacion;
ALTER TABLE usuarios ADD COLUMN identidad_registrada_en DATETIME NULL AFTER identidad_huella;
ALTER TABLE usuarios ADD UNIQUE KEY uq_usuarios_identidad (identidad_huella);

-- C2. inmuebles: varios por cliente; "eliminar" = archivar (las solicitudes conservan su snapshot).
ALTER TABLE inmuebles ADD COLUMN archivado_en DATETIME NULL AFTER pisos;

-- C3. trabajadores: verificación, preferencia de horario y baja vigente.
--     (El historial completo de bajas y reactivaciones va en trabajador_estado_historial.)
ALTER TABLE trabajadores
  ADD COLUMN estado_verificacion ENUM('PENDIENTE','VERIFICADO','RECHAZADO') NOT NULL DEFAULT 'PENDIENTE' AFTER estado;
ALTER TABLE trabajadores ADD COLUMN mostrar_fuera_de_horario TINYINT(1) NOT NULL DEFAULT 0 AFTER estado_verificacion;
ALTER TABLE trabajadores ADD COLUMN baja_en DATETIME NULL AFTER mostrar_fuera_de_horario;
ALTER TABLE trabajadores ADD COLUMN baja_tipo ENUM('VOLUNTARIA','ADMINISTRATIVA') NULL AFTER baja_en;
ALTER TABLE trabajadores ADD COLUMN baja_motivo VARCHAR(255) NULL AFTER baja_tipo;
ALTER TABLE trabajadores
  MODIFY COLUMN estado ENUM('ACTIVO','INACTIVO','BAJA') NOT NULL DEFAULT 'ACTIVO';
--     Identidad (v8): igual que en usuarios (ver C1c).
ALTER TABLE trabajadores ADD COLUMN identidad_huella CHAR(64) NULL AFTER baja_motivo;
ALTER TABLE trabajadores ADD COLUMN identidad_registrada_en DATETIME NULL AFTER identidad_huella;
ALTER TABLE trabajadores ADD UNIQUE KEY uq_trabajadores_identidad (identidad_huella);

-- C4. trabajador_horarios: VARIAS franjas por día. Primero el índice nuevo (para que la FK
--     siga teniendo índice) y después se quita el único. La tabla tiene 0 filas.
ALTER TABLE trabajador_horarios ADD KEY idx_horario_trabajador_dia (trabajador_id, dia_semana, hora_inicio);
ALTER TABLE trabajador_horarios DROP INDEX uq_horario_dia;

-- C5. documentos_cliente y documentos_trabajador: revisión del admin por documento.
--     archivo_eliminado_en (v8): la foto se borra del almacenamiento al terminar la revisión
--     (no se guarda para siempre); la fila queda como constancia. Con fecha, archivo_url ya
--     no apunta a nada y el backend no lo devuelve.
ALTER TABLE documentos_cliente
  ADD COLUMN estado ENUM('PENDIENTE','APROBADO','RECHAZADO') NOT NULL DEFAULT 'PENDIENTE' AFTER archivo_url;
ALTER TABLE documentos_cliente ADD COLUMN motivo_rechazo VARCHAR(255) NULL AFTER estado;
ALTER TABLE documentos_cliente ADD COLUMN revisado_en DATETIME NULL AFTER motivo_rechazo;
ALTER TABLE documentos_cliente ADD COLUMN revisado_por INT NULL AFTER revisado_en;
ALTER TABLE documentos_cliente ADD KEY idx_doc_cliente_revisor (revisado_por);
ALTER TABLE documentos_cliente
  ADD CONSTRAINT fk_doc_cliente_revisor FOREIGN KEY (revisado_por) REFERENCES usuarios (id)
    ON DELETE SET NULL ON UPDATE NO ACTION;
ALTER TABLE documentos_cliente ADD COLUMN archivo_eliminado_en DATETIME NULL AFTER revisado_por;

ALTER TABLE documentos_trabajador
  ADD COLUMN estado ENUM('PENDIENTE','APROBADO','RECHAZADO') NOT NULL DEFAULT 'PENDIENTE' AFTER archivo_url;
ALTER TABLE documentos_trabajador ADD COLUMN motivo_rechazo VARCHAR(255) NULL AFTER estado;
ALTER TABLE documentos_trabajador ADD COLUMN revisado_en DATETIME NULL AFTER motivo_rechazo;
ALTER TABLE documentos_trabajador ADD COLUMN revisado_por INT NULL AFTER revisado_en;
ALTER TABLE documentos_trabajador ADD KEY idx_doc_trabajador_revisor (revisado_por);
ALTER TABLE documentos_trabajador
  ADD CONSTRAINT fk_doc_trabajador_revisor FOREIGN KEY (revisado_por) REFERENCES usuarios (id)
    ON DELETE SET NULL ON UPDATE NO ACTION;
ALTER TABLE documentos_trabajador ADD COLUMN archivo_eliminado_en DATETIME NULL AFTER revisado_por;

-- C6. notificaciones (las del CLIENTE): estado de lectura y tipos nuevos (al final, sin pérdida).
ALTER TABLE notificaciones ADD COLUMN leida_en DATETIME NULL AFTER mensaje;
ALTER TABLE notificaciones ADD KEY idx_notif_usuario_leida (usuario_id, leida_en);
ALTER TABLE notificaciones
  MODIFY COLUMN tipo ENUM(
    'SERVICIO_CONFIRMADO','CALIFICAR_SERVICIO',
    'INVITACION_RECHAZADA','INVITACIONES_RECHAZADAS',
    'SOLICITUD_DEVUELTA_A_BOLSA','DOCUMENTOS_APROBADOS','DOCUMENTOS_RECHAZADOS',
    'SERVICIO_CANCELADO_POR_PLATAFORMA','ADEUDO_REGISTRADO','CONFIRMAR_SERVICIO_REALIZADO',
    'AVISO_CONFIRMACION_CON_EVIDENCIA','SERVICIO_CONFIRMADO_AUTOMATICAMENTE',
    'REPORTE_REGISTRADO','REPORTE_RESUELTO'
  ) NOT NULL;


-- ── D. DETALLE E HISTORIA DE CADA SOLICITUD ─────────────────────────────────

-- D1. Áreas elegidas con el NOMBRE congelado al pedir.
CREATE TABLE solicitud_areas (
  solicitud_id    INT         NOT NULL,
  area_id         INT         NOT NULL,
  nombre_aplicado VARCHAR(60) NOT NULL,
  PRIMARY KEY (solicitud_id, area_id),
  KEY idx_sa_area (area_id),
  CONSTRAINT fk_sa_solicitud FOREIGN KEY (solicitud_id) REFERENCES solicitudes (id)
    ON DELETE CASCADE  ON UPDATE NO ACTION,
  CONSTRAINT fk_sa_area      FOREIGN KEY (area_id)      REFERENCES areas_limpieza (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- D2. Extras elegidos con NOMBRE, PRECIO y MINUTOS congelados al pedir.
CREATE TABLE solicitud_extras (
  solicitud_id          INT               NOT NULL,
  extra_id              INT               NOT NULL,
  nombre_aplicado       VARCHAR(100)      NOT NULL,
  precio_aplicado       DECIMAL(10,2)     NOT NULL,
  duracion_aplicada_min SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (solicitud_id, extra_id),
  KEY idx_se_extra (extra_id),
  CONSTRAINT fk_se_solicitud FOREIGN KEY (solicitud_id) REFERENCES solicitudes (id)
    ON DELETE CASCADE  ON UPDATE NO ACTION,
  CONSTRAINT fk_se_extra     FOREIGN KEY (extra_id)     REFERENCES servicios_extra (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- D3. Especialidades requeridas (servicio ∪ extras) con NOMBRE congelado.
CREATE TABLE solicitud_especialidades (
  solicitud_id    INT          NOT NULL,
  especialidad_id INT          NOT NULL,
  nombre_aplicado VARCHAR(100) NOT NULL,
  PRIMARY KEY (solicitud_id, especialidad_id),
  KEY idx_soesp_especialidad (especialidad_id),
  CONSTRAINT fk_soesp_solicitud    FOREIGN KEY (solicitud_id)    REFERENCES solicitudes (id)
    ON DELETE CASCADE  ON UPDATE NO ACTION,
  CONSTRAINT fk_soesp_especialidad FOREIGN KEY (especialidad_id) REFERENCES especialidades (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- D4. Participación de cada trabajador en cada solicitud (invitación o bolsa).
--     UNA fila por par (solicitud, trabajador) — UNIQUE —, que se reutiliza.
--     RECHAZADA y CANCELADA son DEFINITIVAS para ese par. CERRADA puede reabrirse.
--     aceptada_solicitud_id: columna GENERADA VIRTUAL = solicitud_id solo si ACEPTADA;
--     su UNIQUE impide EN LA BD dos aceptadas por solicitud. VIRTUAL (no STORED) porque
--     MySQL prohíbe ON DELETE CASCADE en la FK de una columna base de una columna
--     generada STORED. El backend NUNCA la escribe (@ignore en Prisma).
CREATE TABLE solicitud_trabajadores (
  id                    INT      NOT NULL AUTO_INCREMENT,
  solicitud_id          INT      NOT NULL,
  trabajador_id         INT      NOT NULL,
  origen                ENUM('INVITACION','BOLSA') NOT NULL,
  estado                ENUM('PENDIENTE','ACEPTADA','RECHAZADA','CERRADA','CANCELADA') NOT NULL DEFAULT 'PENDIENTE',
  motivo_cierre         ENUM('OTRO_TRABAJADOR_ACEPTO','CLIENTE_CANCELO','CAMBIO_A_AUTOMATICA',
                             'TRABAJADOR_OCUPADO','TRABAJADOR_CANCELO','TRABAJADOR_DADO_DE_BAJA') NULL,
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  respondida_en         DATETIME NULL,
  updated_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  aceptada_solicitud_id INT AS (IF(estado = 'ACEPTADA', solicitud_id, NULL)) VIRTUAL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_st_solicitud_trabajador (solicitud_id, trabajador_id),
  UNIQUE KEY uq_st_una_aceptada (aceptada_solicitud_id),
  KEY idx_st_trabajador_estado (trabajador_id, estado),
  KEY idx_st_solicitud_estado (solicitud_id, estado),
  CONSTRAINT fk_st_solicitud  FOREIGN KEY (solicitud_id)  REFERENCES solicitudes (id)
    ON DELETE CASCADE  ON UPDATE NO ACTION,
  CONSTRAINT fk_st_trabajador FOREIGN KEY (trabajador_id) REFERENCES trabajadores (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- D5. Historial de cambios de estado de la solicitud: quién, cuándo y por qué.
--     actor_id = usuarios.id (CLIENTE/ADMIN) o trabajadores.id (TRABAJADOR); sin FK.
CREATE TABLE solicitud_historial (
  id              INT      NOT NULL AUTO_INCREMENT,
  solicitud_id    INT      NOT NULL,
  estado_anterior ENUM('PENDIENTE','CONFIRMADO','EN_PROCESO','REALIZADO','CANCELADO','RECHAZADO') NULL,
  estado_nuevo    ENUM('PENDIENTE','CONFIRMADO','EN_PROCESO','REALIZADO','CANCELADO','RECHAZADO') NOT NULL,
  actor           ENUM('CLIENTE','TRABAJADOR','ADMIN','SISTEMA') NOT NULL,
  actor_id        INT          NULL,
  motivo          VARCHAR(255) NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_hist_solicitud (solicitud_id, created_at),
  KEY idx_hist_actor (actor, actor_id),
  CONSTRAINT fk_hist_solicitud FOREIGN KEY (solicitud_id) REFERENCES solicitudes (id)
    ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- D6. Uso de un descuento en una solicitud (uno por solicitud). El uso se CONSUME aunque
--     la solicitud se cancele. Los límites se cuentan sobre esta tabla.
CREATE TABLE descuento_usos (
  id               INT           NOT NULL AUTO_INCREMENT,
  descuento_id     INT           NOT NULL,
  solicitud_id     INT           NOT NULL,
  cliente_id       INT           NOT NULL,
  codigo_aplicado  VARCHAR(40)   NULL,
  monto_descontado DECIMAL(10,2) NOT NULL,
  created_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_du_solicitud (solicitud_id),
  KEY idx_du_descuento_cliente (descuento_id, cliente_id),
  KEY idx_du_cliente (cliente_id),
  CONSTRAINT fk_du_descuento FOREIGN KEY (descuento_id) REFERENCES descuentos (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_du_solicitud FOREIGN KEY (solicitud_id) REFERENCES solicitudes (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_du_cliente   FOREIGN KEY (cliente_id)   REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- D7. Adeudos de clientes (cancelación tardía de un servicio que se paga en efectivo).
--     PENDIENTE  → se generó; el cliente lo paga en efectivo en su PRÓXIMO servicio.
--     EN_COBRO   → quedó asignado a ese próximo servicio (solicitud_cobro_id); si ese
--                  servicio se cancela, vuelve a PENDIENTE.
--     COBRADO    → se registró el pago en efectivo de ese próximo servicio (estado_pago =
--                  PAGADO): a ese trabajador se le registra COBRO_ADEUDO_CLIENTE como deuda,
--                  con el motivo (UN movimiento por servicio con el total de sus adeudos).
--                  Si una resolución anula ese pago, el adeudo vuelve a PENDIENTE y el
--                  movimiento se corrige con AJUSTE.
--     Compensación del trabajador afectado (v9: DIAS_ESPERA_PAGO_ADEUDO = 0): la plataforma
--     la paga DE INMEDIATO al cancelarse el servicio (compensacion_pagada_por = PLATAFORMA)
--     y absorbe el costo. El adeudo sigue PENDIENTE y se intenta recuperar cuando el cliente
--     vuelva a contratar; ese dinero se queda en la plataforma y NO genera un segundo pago al
--     trabajador. Si el cliente nunca vuelve, la pérdida es de la plataforma.
--     (CLIENTE queda como valor posible por si el admin sube el plazo de espera.)
--     La BD impide liberar dos veces la misma compensación (uq_mov_una_vez_por_movimiento en E1).
--     Dos relaciones a solicitudes (origen y cobro): en Prisma llevan nombre.
CREATE TABLE cliente_adeudos (
  id                  INT           NOT NULL AUTO_INCREMENT,
  cliente_id          INT           NOT NULL,
  solicitud_origen_id INT           NOT NULL,
  motivo              ENUM('CANCELACION_TARDIA') NOT NULL,
  monto               DECIMAL(10,2) NOT NULL,
  estado              ENUM('PENDIENTE','EN_COBRO','COBRADO') NOT NULL DEFAULT 'PENDIENTE',
  solicitud_cobro_id  INT           NULL,
  trabajador_cobro_id INT           NULL,
  cobrado_en          DATETIME      NULL,
  compensacion_liberada_en DATETIME NULL,
  compensacion_pagada_por  ENUM('CLIENTE','PLATAFORMA') NULL,
  created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_adeudo_origen (solicitud_origen_id),
  KEY idx_adeudo_cliente_estado (cliente_id, estado),
  KEY idx_adeudo_cobro (solicitud_cobro_id),
  KEY idx_adeudo_trabajador (trabajador_cobro_id),
  CONSTRAINT fk_adeudo_cliente    FOREIGN KEY (cliente_id)          REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_adeudo_origen     FOREIGN KEY (solicitud_origen_id) REFERENCES solicitudes (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_adeudo_cobro      FOREIGN KEY (solicitud_cobro_id)  REFERENCES solicitudes (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_adeudo_trabajador FOREIGN KEY (trabajador_cobro_id) REFERENCES trabajadores (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- D8. Resoluciones del admin sobre una solicitud con reportes o desacuerdo (v9).
--     INMUTABLE: si el admin cambia de criterio, registra una resolución NUEVA (manda la
--     más reciente). Cada eje es independiente; NULL = esa resolución no lo cambia:
--       resultado_servicio REALIZADO / NO_REALIZADO
--       resultado_pago     PAGADO / NO_PAGADO
--     Los movimientos que la aplican (AJUSTE u otros) llevan trabajador_movimientos.resolucion_id.
CREATE TABLE solicitud_resoluciones (
  id                 INT          NOT NULL AUTO_INCREMENT,
  solicitud_id       INT          NOT NULL,
  admin_id           INT          NULL,
  resultado_servicio ENUM('REALIZADO','NO_REALIZADO') NULL,
  resultado_pago     ENUM('PAGADO','NO_PAGADO') NULL,
  motivo             VARCHAR(500) NOT NULL,
  created_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_res_solicitud (solicitud_id, created_at),
  KEY idx_res_admin (admin_id),
  CONSTRAINT fk_res_solicitud FOREIGN KEY (solicitud_id) REFERENCES solicitudes (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_res_admin     FOREIGN KEY (admin_id)     REFERENCES usuarios (id)
    ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- D9. Reportes e incidencias de un servicio (v9). Es el backend del botón "Reportar" que ya
--     tiene la app del cliente (hoy sin función); la app del trabajador tendrá el suyo.
--     Se habilita desde la hora programada. Ambas partes pueden reportar; cada parte puede
--     tener varios reportes y adjuntar evidencia (evidencias_solicitud.reporte_id).
--     reportado_por indica quién reporta: cliente_id (CLIENTE) o trabajador_id (TRABAJADOR).
--     (Sin CHECK que lo obligue: MySQL/TiDB no permiten CHECK sobre columnas con FK.)
--     ABIERTO → EN_REVISION (lo toma el admin) → RESUELTO (resolucion_id).
--     Mientras haya uno sin RESOLVER, el servicio no se confirma solo ni por evidencia.
--     Se conservan siempre (FK RESTRICT): son el historial de ambas partes.
CREATE TABLE solicitud_reportes (
  id            INT      NOT NULL AUTO_INCREMENT,
  solicitud_id  INT      NOT NULL,
  reportado_por ENUM('CLIENTE','TRABAJADOR') NOT NULL,
  cliente_id    INT      NULL,
  trabajador_id INT      NULL,
  tipo          ENUM('NO_SE_PUDO_COMPLETAR','INASISTENCIA','PROBLEMA_UBICACION','UBICACION_FALSA',
                     'PAGO_EN_DISPUTA','OTRO') NOT NULL,
  descripcion   TEXT     NULL,
  estado        ENUM('ABIERTO','EN_REVISION','RESUELTO') NOT NULL DEFAULT 'ABIERTO',
  resolucion_id INT      NULL,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_rep_solicitud_estado (solicitud_id, estado),
  KEY idx_rep_estado (estado, created_at),
  KEY idx_rep_cliente (cliente_id),
  KEY idx_rep_trabajador (trabajador_id),
  KEY idx_rep_resolucion (resolucion_id),
  CONSTRAINT fk_rep_solicitud  FOREIGN KEY (solicitud_id)  REFERENCES solicitudes (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_rep_cliente    FOREIGN KEY (cliente_id)    REFERENCES usuarios (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_rep_trabajador FOREIGN KEY (trabajador_id) REFERENCES trabajadores (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_rep_resolucion FOREIGN KEY (resolucion_id) REFERENCES solicitud_resoluciones (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- D10. evidencias_solicitud (tabla EXISTENTE, 0 filas): ahora la aportan ambas partes y puede
--      pertenecer a un reporte. aportada_por tiene DEFAULT 'TRABAJADOR' (la evidencia de
--      "servicio terminado" es del trabajador). reporte_id NULL = evidencia de terminación.
ALTER TABLE evidencias_solicitud
  ADD COLUMN aportada_por ENUM('CLIENTE','TRABAJADOR') NOT NULL DEFAULT 'TRABAJADOR' AFTER descripcion;
ALTER TABLE evidencias_solicitud ADD COLUMN reporte_id INT NULL AFTER aportada_por;
ALTER TABLE evidencias_solicitud ADD KEY idx_evid_reporte (reporte_id);
ALTER TABLE evidencias_solicitud
  ADD CONSTRAINT fk_evid_reporte FOREIGN KEY (reporte_id) REFERENCES solicitud_reportes (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION;


-- ── E. TRABAJADORES: LIBRO, ESTADOS Y NOTIFICACIONES ────────────────────────

-- E1. Libro de movimientos (INMUTABLE: solo INSERT; correcciones con AJUSTE).
--     Cuentas:
--       POR_COBRAR = dinero que el trabajador ya ganó, pero que todavía no puede retirar
--       DISPONIBLE = dinero que ya puede retirar
--       DEUDA      = dinero que el trabajador debe a la plataforma
--     Tipos (signo sobre su cuenta):
--       GANANCIA_SERVICIO        POR_COBRAR +  su % al liberarse la ganancia (pago con TARJETA)
--       COMPENSACION_CANCELACION POR_COBRAR +  su % si el cliente cancela fuera de plazo (la
--                                              plataforma la libera de inmediato: D55 = 0 días)
--       LIBERACION_SALDO         POR_COBRAR − y DISPONIBLE + (par)  cuando ya puede retirarse
--       COMISION_EFECTIVO        DEUDA +       pago en EFECTIVO: lo cobrado de más (15 %). Se
--                                              registra AL REGISTRARSE EL PAGO (estado_pago =
--                                              PAGADO), aunque nadie marque "terminado"
--       COBRO_ADEUDO_CLIENTE     DEUDA +       cobró en efectivo adeudos de otros servicios del
--                                              cliente (motivo en descripcion). UNO por servicio
--                                              con el total; el dinero recupera lo que ya pagó
--                                              la plataforma
--       COMPENSACION_DESCUENTO   DISPONIBLE +  pago en EFECTIVO con descuento: lo que la
--                                              plataforma le debe porque cobró de menos
--       RETENCION_DEUDA          DISPONIBLE − y DEUDA − (par): % configurable (10 %)
--       ABONO_DEUDA_CON_SALDO    DISPONIBLE − y DEUDA − (par): monto que ELIGE el trabajador
--       CARGO_CANCELACION        DEUDA +       el trabajador cancela fuera de plazo
--       PAGO_DEUDA_EXTERNO       DEUDA −       [futuro: tarjeta u otro medio]
--       RETIRO                   DISPONIBLE −  [futuro: tarjeta vinculada, cheque, OXXO]
--       AJUSTE                   cualquiera    corrección del movimiento relacionado (p. ej. la
--                                              comisión de un cobro que no existió). Con
--                                              resolucion_id si la ordena una resolución
--     Garantías EN LA BD contra pagos y comisiones dobles (v9):
--       uq_mov_idempotencia             la misma operación no se registra dos veces.
--       uq_mov_una_vez_por_solicitud    GANANCIA_SERVICIO, COMPENSACION_CANCELACION,
--                                       COMISION_EFECTIVO, COMPENSACION_DESCUENTO,
--                                       CARGO_CANCELACION y COBRO_ADEUDO_CLIENTE: UNA vez por
--                                       (solicitud, trabajador), aunque cambie la clave.
--       uq_mov_una_vez_por_movimiento   un movimiento se libera UNA vez y se corrige UNA vez:
--                                       cada mitad de LIBERACION_SALDO y cada AJUSTE apuntan
--                                       (movimiento_relacionado_id) al movimiento afectado.
--                                       Para corregir de nuevo se ajusta el AJUSTE.
--       chk_mov_referencia_obligatoria  LIBERACION_SALDO y AJUSTE siempre dicen a qué
--                                       movimiento afectan.
--     clave_unica_solicitud y clave_unica_referencia son columnas GENERADAS VIRTUALES:
--     el backend NUNCA las escribe (@ignore en Prisma).
CREATE TABLE trabajador_movimientos (
  id                        INT           NOT NULL AUTO_INCREMENT,
  trabajador_id             INT           NOT NULL,
  cuenta                    ENUM('POR_COBRAR','DISPONIBLE','DEUDA') NOT NULL,
  tipo                      ENUM('GANANCIA_SERVICIO','COMPENSACION_CANCELACION','LIBERACION_SALDO',
                                 'COMISION_EFECTIVO','COMPENSACION_DESCUENTO','RETENCION_DEUDA',
                                 'ABONO_DEUDA_CON_SALDO','CARGO_CANCELACION','COBRO_ADEUDO_CLIENTE','PAGO_DEUDA_EXTERNO',
                                 'RETIRO','AJUSTE') NOT NULL,
  monto                     DECIMAL(10,2) NOT NULL,
  saldo_resultante          DECIMAL(10,2) NOT NULL,
  porcentaje_aplicado       DECIMAL(5,2)  NULL,
  solicitud_id              INT           NULL,
  movimiento_relacionado_id INT           NULL,
  resolucion_id             INT           NULL,
  referencia_externa        VARCHAR(100)  NULL,
  descripcion               VARCHAR(255)  NULL,
  clave_idempotencia        VARCHAR(100)  NOT NULL,
  created_at                DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  clave_unica_solicitud     VARCHAR(80) AS (IF(tipo IN ('GANANCIA_SERVICIO','COMPENSACION_CANCELACION',
                                                       'COMISION_EFECTIVO','COMPENSACION_DESCUENTO',
                                                       'CARGO_CANCELACION','COBRO_ADEUDO_CLIENTE')
                                                AND solicitud_id IS NOT NULL,
                                               CONCAT(tipo, ':', solicitud_id, ':', trabajador_id), NULL)) VIRTUAL,
  clave_unica_referencia    VARCHAR(50) AS (IF(tipo IN ('LIBERACION_SALDO','AJUSTE'),
                                               CONCAT(tipo, ':', movimiento_relacionado_id, ':', cuenta), NULL)) VIRTUAL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mov_idempotencia (clave_idempotencia),
  UNIQUE KEY uq_mov_una_vez_por_solicitud (clave_unica_solicitud),
  UNIQUE KEY uq_mov_una_vez_por_movimiento (clave_unica_referencia),
  KEY idx_mov_trabajador_cuenta (trabajador_id, cuenta, id),
  KEY idx_mov_solicitud (solicitud_id),
  KEY idx_mov_relacionado (movimiento_relacionado_id),
  KEY idx_mov_resolucion (resolucion_id),
  CONSTRAINT fk_mov_trabajador  FOREIGN KEY (trabajador_id) REFERENCES trabajadores (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_mov_solicitud   FOREIGN KEY (solicitud_id)  REFERENCES solicitudes (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_mov_relacionado FOREIGN KEY (movimiento_relacionado_id) REFERENCES trabajador_movimientos (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_mov_resolucion  FOREIGN KEY (resolucion_id) REFERENCES solicitud_resoluciones (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  -- Usa la columna generada porque MySQL/TiDB no permiten un CHECK sobre una columna con
  -- FK (error 3823, aunque sea RESTRICT). Para LIBERACION_SALDO y AJUSTE,
  -- clave_unica_referencia es NULL solo si movimiento_relacionado_id es NULL.
  CONSTRAINT chk_mov_referencia_obligatoria
    CHECK (tipo NOT IN ('LIBERACION_SALDO','AJUSTE') OR clave_unica_referencia IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- E2. Historial de estados del trabajador (desactivar/activar, bajas, reactivaciones).
CREATE TABLE trabajador_estado_historial (
  id              INT          NOT NULL AUTO_INCREMENT,
  trabajador_id   INT          NOT NULL,
  estado_anterior ENUM('ACTIVO','INACTIVO','BAJA') NULL,
  estado_nuevo    ENUM('ACTIVO','INACTIVO','BAJA') NOT NULL,
  tipo            ENUM('ACTIVACION','DESACTIVACION','BAJA_VOLUNTARIA','BAJA_ADMINISTRATIVA','REACTIVACION') NOT NULL,
  actor           ENUM('TRABAJADOR','ADMIN','SISTEMA') NOT NULL,
  admin_id        INT          NULL,
  motivo          VARCHAR(255) NULL,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_teh_trabajador (trabajador_id, created_at),
  KEY idx_teh_admin (admin_id),
  CONSTRAINT fk_teh_trabajador FOREIGN KEY (trabajador_id) REFERENCES trabajadores (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_teh_admin      FOREIGN KEY (admin_id)      REFERENCES usuarios (id)
    ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- E3. Notificaciones del TRABAJADOR (tabla aparte: audiencias aisladas).
--     PAGO_EFECTIVO_PRESUMIDO (D59): el pago se dio por hecho al confirmarse el servicio
--     automáticamente y se registró la comisión; el mensaje le indica que, si no recibió el
--     efectivo, lo reporte.
CREATE TABLE notificaciones_trabajador (
  id            INT          NOT NULL AUTO_INCREMENT,
  trabajador_id INT          NOT NULL,
  solicitud_id  INT          NULL,
  tipo          ENUM('INVITACION_NUEVA','SOLICITUD_CANCELADA_POR_CLIENTE','COMPENSACION_REGISTRADA',
                     'CARGO_CANCELACION','GANANCIA_REGISTRADA','COMISION_EFECTIVO_REGISTRADA',
                     'DOCUMENTOS_APROBADOS','DOCUMENTOS_RECHAZADOS','BAJA_REGISTRADA',
                     'CUENTA_REACTIVADA','COBRO_ADEUDO_REGISTRADO','COMPENSACION_LIBERADA',
                     'SUBIR_EVIDENCIA_SERVICIO','SERVICIO_CONFIRMADO_AUTOMATICAMENTE',
                     'PAGO_SERVICIO_LIBERADO','REPORTE_REGISTRADO','REPORTE_RESUELTO',
                     'AJUSTE_REGISTRADO','PAGO_EFECTIVO_PRESUMIDO') NOT NULL,
  titulo        VARCHAR(100) NOT NULL,
  mensaje       VARCHAR(255) NOT NULL,
  leida_en      DATETIME     NULL,
  created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_notif_trab_leida (trabajador_id, leida_en),
  KEY idx_notif_trab_solicitud (solicitud_id),
  CONSTRAINT fk_notif_trab_trabajador FOREIGN KEY (trabajador_id) REFERENCES trabajadores (id)
    ON DELETE RESTRICT ON UPDATE NO ACTION,
  CONSTRAINT fk_notif_trab_solicitud  FOREIGN KEY (solicitud_id)  REFERENCES solicitudes (id)
    ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ── F. DATOS INICIALES (solo en tablas NUEVAS) ──────────────────────────────

-- F1. Áreas que hoy están fijas en la app cliente.
INSERT INTO areas_limpieza (nombre, orden) VALUES
  ('Cocina', 1), ('Sala', 2), ('Recámaras', 3), ('Baños', 4), ('Patio', 5), ('Áreas comunes', 6);

-- F2. Extras y precios que hoy están fijos en la app cliente (minutos: provisional 0; los edita el admin).
INSERT INTO servicios_extra (nombre, precio) VALUES
  ('Limpieza de ventanas',     300.00),
  ('Limpieza de estufa',       300.00),
  ('Limpieza de refrigerador', 200.00),
  ('Limpieza de alacena',      180.00),
  ('Limpieza de cajonera',     150.00);

-- F3. Una fila de cálculo (incrementos en 0, provisional; los edita el admin) por servicio.
INSERT INTO servicio_calculo (servicio_id) SELECT id FROM servicios;

-- F4. Cancelar una CONFIRMADA con menos de 24 h: se cobra el 100 % del precio
--     (al cliente y al trabajador), decidido por el usuario el 2026-11-24.
INSERT INTO reglas_cargo_cancelacion (aplica_a, horas_antes, tipo, valor) VALUES
  ('CLIENTE',    24, 'PORCENTAJE', 100.00),
  ('TRABAJADOR', 24, 'PORCENTAJE', 100.00);

-- F5. Parámetros decididos por el usuario (2026-11-24).
INSERT INTO parametros_negocio (clave, valor, descripcion) VALUES
  ('PORCENTAJE_TRABAJADOR',       85.00, 'Porcentaje del precio sin descuento que gana el trabajador (el resto es de la plataforma)'),
  ('PORCENTAJE_RETENCION_DEUDA',  10.00, 'Porcentaje de cada ingreso a DISPONIBLE que se usa para reducir la deuda'),
  ('MARGEN_TRASLADO_MIN',         60.00, 'Minutos mínimos entre dos servicios del mismo trabajador'),
  ('MAX_INVITACIONES_PENDIENTES',  5.00, 'Invitaciones pendientes a la vez por solicitud'),
  ('MINUTOS_ESPERA_CONFIRMACION',      30.00, 'Minutos tras la hora estimada de fin para pedir confirmación al cliente y evidencia al trabajador'),
  ('MINUTOS_PLAZO_CLIENTE_EVIDENCIA',  15.00, 'Minutos que tiene el cliente para confirmar antes de que se use la evidencia del trabajador'),
  ('MINUTOS_CONFIRMACION_AUTOMATICA',  30.00, 'Minutos tras pedir confirmación a ambos; si nadie responde se confirma solo, sin liberar el pago'),
  ('DIAS_ESPERA_PAGO_ADEUDO',           0.00, 'Días antes de que la plataforma pague la compensación al trabajador si el cliente no ha pagado su adeudo; 0 = de inmediato');
