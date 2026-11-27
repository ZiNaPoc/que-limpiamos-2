# 15 — Plan de la Fase 3 (audiencia CLIENTE) — v2, PROPUESTA para revisión (no iniciada)

- **Fecha:** 2026-11-24 · **Estado:** solo plan. No se ha escrito código de la Fase 3 ni se aplicó ningún SQL en producción.
- **v2:** incorpora D5 (almacenamiento, `16`), D63–D65, la seguridad de auth aprobada (`14` §5) y el **orden de implementación** para no rehacer trabajo.
- Leyenda de estado: **Implementado** (código existe) · **Probado** (prueba automática que pasa) · **Integrado** (funciona con su consumidor real).

## 0a. Avance al 2026-11-24 (después de la corrección de D5)
| Paso | Estado |
|---|---|
| 1. Límite de intentos | **Implementado y probado** (14 pruebas); integrado en el panel |
| Almacenamiento (antes en el paso 5) | **Local implementado y probado** (`16` v2, sin dependencias); sin proveedor externo |
| 4. Integración de auth | Panel: **integrado y probado en el navegador**. Apps Flutter: **implementado, sin compilar** (no hay Flutter SDK aquí) |
| 0. Configuración del usuario | Pendiente: JWT en `.env` y, opcional, la BD `queLimpiamos_dev`. La demo local (`17`) funciona sin ellas |
| 2. SQL 003 v2 | Pendiente de tu OK al diseño (`13` §7): D63 propietario, D64 aviso, D66 permiso y tablas de documentos |
| 3, 5 (dominio), 6 (Fase 3) | No iniciados |

## 0. Orden de implementación recomendado
| Paso | Qué | Por qué en este orden | Depende de |
|---|---|---|---|
| **0** | **Tú:** secretos JWT en `.env`; crear la BD de desarrollo `queLimpiamos_dev` (vacía, con permisos para la cuenta del backend); elegir el proveedor de almacenamiento (D5a) y la cuenta del propietario (D63a) | Sin esto no se puede probar la integración sin tocar producción, ni cerrar el schema | — |
| **1** | **Límite de intentos y bloqueo progresivo** (backend, `14` §5) + pruebas | Cierra la Fase 2. Las apps deben conocer el 429 **antes** de integrarse; si no, habría que tocarlas dos veces | Aprobado |
| **2** | **SQL 003 v2** (D63 propietario y no auto-otorgamiento, D64 aviso, permiso y tablas de documentos de `16` §5) + ensayo | Todo cambio de schema **antes** de aplicar a producción y de escribir código que lo use: una sola migración y un solo ensayo, sin SQL 004 | 0 (D63a, D5a), tu revisión del diseño |
| **3** | Preparar `queLimpiamos_dev` con la estructura de producción + 002 + 003 v2 (sin datos reales, con cuentas de prueba) y cambiar el schema Prisma activo **en el árbol de trabajo** al previsto | Permite desarrollar las Fases 3–5 sin tocar producción. El servidor local apunta a la BD de desarrollo | 2 |
| **4** | **Integración de auth** en las dos apps y el panel (`14` §4) contra la BD de desarrollo | Las rutas de auth ya no cambian (pasos 1–2 cerrados). Todo lo demás de las apps cuelga de la sesión | 1, 3, tu OK a `flutter_secure_storage` |
| **5** | **`src/dominio/`** (libro de movimientos con sus garantías, `notificar()` con `clave_evento`, precio y duración) y **`src/shared/almacenamiento`** (S3, URLs firmadas, validación, EXIF) + pruebas | Lo usan las Fases 3, 4 y 5: hacerlo una vez evita duplicar reglas de dinero | 3; almacenamiento: D5a + bucket de prueba |
| **6** | **Fase 3a → 3b → 3c** (§2) | 3a no maneja dinero ni archivos; 3b usa el dominio; 3c usa el almacenamiento | 5 |
| **7** | Fase 4 (trabajador + tarea periódica), Fase 5 (admin: permisos del propietario, revisión de documentos con auditoría, resoluciones), Fase 6 (logs) y Fase 7 (deploy) | La 4 cierra el flujo del servicio; la 5 necesita permisos y documentos | 6 |
| **—** | **Aplicar 002 + 003 v2 en producción** | Cuando lo autorices, idealmente después del paso 2 y antes del deploy de la Fase 3. Hasta entonces todo vive en la BD de desarrollo y la de pruebas | Tu autorización |

## 1. Requisitos previos — estado
| # | Requisito | Estado |
|---|---|---|
| R1 | Schema del 002 + 003 disponible | **Ensayado, no aplicado.** Camino propuesto: la BD de desarrollo (paso 3) mientras no autorices producción |
| R2 | Secretos JWT en `.env` | **Pendiente (tú).** Hoy el servidor no arranca |
| R3 | D63 permisos | **Decidido** (solo el propietario; sin auto-otorgamiento). Falta **D63a** (qué cuenta) y **D63b** |
| R4 | D5 almacenamiento | **Resuelto para esta etapa:** almacenamiento local privado implementado y probado (`16` v2). Faltan **D66** y **D67**; el proveedor de nube queda aplazado |
| R5 | Límite de intentos | **Aprobado**, diseño en `14` §5, paso 1 |
| R6 | BD de desarrollo `queLimpiamos_dev` | **Pendiente (tú)**: crearla en la consola de TiDB |

## 2. Alcance de la Fase 3 (con D64 y D65)
### 3a — Sin dinero ni archivos
- **Perfil:** `GET/PATCH /api/cliente/perfil`. Incluye `estado_verificacion` y, por documento, `estado` + `motivo_rechazo` (D65).
- **Inmuebles:** CRUD propio; "eliminar" = archivar; `pisos >= 1`.
- **Catálogo** de servicios, extras y áreas activos.
- **Cotización** (`POST /api/cliente/cotizaciones`): precio y duración calculados en el servidor, mejor descuento aplicable y adeudos pendientes.
  - **Permitida con la INE en revisión** (D65).
  - No crea nada ni consume descuentos.
- **Notificaciones:** listar y marcar como leídas.
- **Reseñas** de solicitudes REALIZADAS, en las dos direcciones (cliente → trabajador y trabajador → cliente), anónimas para los usuarios, con promedios, moderación del admin y auditoría. **Especificación definitiva: `20_ESPECIFICACION_RESENAS_Y_REPORTES.md`** (cambia la tabla `resenas`). **SQL 003 v2 preparado, no aplicado: `21`.**
- **Reportes** entre cliente y trabajador (antes o después de finalizar, con fotos opcionales). Las reglas están en `20` §2; la carga de fotos depende del almacenamiento (3c).

### 3b — Solicitudes y dinero
- **Crear solicitud:** exige `estado_verificacion = VERIFICADO`; si no, **403 `IDENTIDAD_NO_VERIFICADA`** con el estado actual (D65). Luego:
  - precio recalculado en el servidor;
  - snapshot;
  - descuento único (el mayor) y su uso consumido;
  - adeudos a EN_COBRO;
  - bolsa o hasta 5 invitaciones a trabajadores elegibles.
- **Cancelar:**
  - en PENDIENTE: sin cargo;
  - en CONFIRMADO con menos de 24 h: cargo del 100 %, adeudo del cliente y compensación que la plataforma paga de inmediato (D55).
- **«Ya pagué en efectivo»** (D56/D59/D64), en una transacción:
  1. registra el pago (`pago_registrado_por = CLIENTE`);
  2. guarda `reporte_pago_hasta = ahora + 24 h`, una sola vez, sin cambios después;
  3. registra la comisión del 15 % una sola vez;
  4. avisa al trabajador con `PAGO_EFECTIVO_REGISTRADO`, que incluye el plazo y cómo reportar.
- **Marcar terminado / no terminado** ("no terminado" = reporte).

### 3c — Documentos y reportes (necesita el almacenamiento)
- **INE:** subir frente y reverso por el backend (validación y EXIF, `16` §4.2) y **volver a subir si se rechazó**, con historial (`documento_eventos`).
  - El cliente ve el estado y el motivo, **no la imagen**.
  - La aprobación (Fase 5) borra el archivo y registra el CURP cifrado y su HMAC (D53/D58).
- **Reportes del cliente** con evidencia (privada; URL temporal solo para las partes y el admin con permiso).

## 3. Decisiones técnicas propuestas
| Tema | Propuesta |
|---|---|
| Lógica compartida | `src/dominio/` (libro, notificaciones, precio) y `src/shared/almacenamiento/`, sin Express ni audiencias |
| Transacciones | Interactivas, con `SELECT … FOR UPDATE` en el trabajador, el descuento, el permiso y el adeudo |
| Notificaciones | Siempre con `clave_evento` (D60); P2002 = "ya avisado" |
| Pruebas | `node:test` contra la BD de pruebas (estructura de producción + 002 + 003 v2, aplicada por el soporte). Almacenamiento: un falso en memoria para las pruebas unitarias y una prueba contra un bucket de **prueba** si se entregan sus credenciales |
| Contrato | `06_CONTRATOS_API.md` se amplía con cada ruta antes de cambiar las apps |

## 4. Preguntas abiertas
| ID | Pregunta | Propuesta |
|---|---|---|
| D5a | Proveedor de almacenamiento | R2 (simple) o S3 `mx-central-1` (datos en México), ver `16` §3 |
| D63a | ¿Qué cuenta es la del propietario? | La indicas tú; se asigna con un script revisado |
| D63b | Si el propietario necesita también el permiso financiero | Asignarlo por script revisado (la BD impide otorgárselo a sí mismo) |
| D66 | **Decidido:** solo los admins con el permiso específico de revisión de identidad (`REVISAR_DOCUMENTOS_IDENTIDAD`, lo otorga el propietario) | — |
| D67 | **Decidido:** evidencias 12 meses; INE con eliminación aparte al concluir su revisión | — |
