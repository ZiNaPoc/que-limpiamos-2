# 09 — Decisiones pendientes

- **Fecha:** 2026-11-24 · **Actualizado:** Fase 1
- Las decisiones con la columna **Bloquea** impiden avanzar en la fase indicada.

## Respuestas del usuario (2026-11-24)

| ID | Respuesta | Estado |
|---|---|---|
| D1 | Sí, añadir contraseña a `trabajadores` | **Hecho**: columna `password_hash VARCHAR(255) NULL` creada en la BD real el 2026-11-24 y añadida al schema local. `Que-Limpiamos` puede quedar desactualizado (indicación del usuario). |
| D2 | El trabajador acepta → `CONFIRMADO`. Modo automático (bolsa) o manual con invitaciones a uno o varios trabajadores; rechazos notifican al cliente. Elegibilidad por especialidades (equipo/habilidad) y horario | Diseñado en `11_PROPUESTA_CAMBIOS_SCHEMA.md`; SQL 002 **no ejecutado** |
| D3 | Delegado: decidir tras ver las pantallas | Tablas `areas_limpieza`/`solicitud_areas`, `servicios_extra`/`solicitud_extras`, `solicitudes.notas` (SQL 002, **no ejecutado**) |
| D4 | Precio fijo por tamaño; cada servicio tiene precio distinto; fórmula aún no definida | Fórmula vacía en `src/modules/cliente/solicitudes/precio.ts` (Fase 3): `precio_base` + incrementos por servicio (en 0) + extras |
| D11 | Sí, sacar `generated/` | **Hecho** en Fase 1 |
| Admins | Se quedan en `usuarios` con rol ADMIN | Decidido |
| Fuente de verdad | La BD `queLimpiamos` + schema de que-limpiamos-3; `Que-Limpiamos/` puede quedar desactualizado | Decidido |
| D12 | Sí, eliminar rutas provisionales, sustituirlas y verificar que Flutter use las nuevas | Rutas **eliminadas** en Fase 1. Sustitutos y cambios en Flutter: Fases 2–4 |

## Tabla original

| ID | Tema | Bloquea | Opciones | Recomendación |
|---|---|---|---|---|
| **D1** | Credenciales de trabajadores: la tabla real `trabajadores` no tiene contraseña | Fase 2 (trabajador) y 4 | (a) Añadir columna `password_hash VARCHAR(255) NULL` a `trabajadores` (cambio de schema real, autorizado, con SQL revisado); (b) tabla nueva `trabajador_credenciales` 1:1; (c) añadir `TRABAJADOR` a `usuarios_rol` y enlazar `trabajadores.usuario_id` (cambio mayor); (d) login sin contraseña (código por SMS/correo) | **(a)**: mínima, nullable (no rompe filas existentes); el admin crea al trabajador y le asigna contraseña inicial. Requiere tu autorización para alterar la BD real y actualizar el schema de referencia |
| **D2** | Reglas de estados y quién asigna | Fases 3–5 | (a) Solo el admin asigna; el trabajador confirma/rechaza su asignación; (b) marketplace: el trabajador ve `PENDIENTE` sin asignar y acepta (como en la demo); (c) ambos | Necesito: ¿quién pasa a `CONFIRMADO`?, ¿quién puede `RECHAZADO` y desde qué estado?, ¿hasta qué estado puede cancelar el cliente?, ¿el trabajador solo ve disponibles de sus especialidades? |
| **D3** | Datos de `seleccion` (notas, áreas, extras, duración) no existen en el schema real | Fase 3 | (a) Descartarlos; (b) añadir columnas (`notas`, etc.) — cambio de schema; (c) guardarlos en otra tabla nueva | Confirmar si el negocio los necesita |
| **D4** | Precio | Fase 3 | (a) Servidor calcula `precio_estimado = servicios.precio_base`; (b) servidor aplica fórmula por inmueble (habitaciones, baños…); (c) aceptar el precio del cliente | (a) o (b). Nunca (c). Si (b), necesito la fórmula |
| **D5** | Almacenamiento de archivos (INE, documentos de trabajador, evidencias) | Fases 3–6 | Cloudinary, S3 / Cloudflare R2, Supabase Storage, Render Disk (persistente, de pago) | Servicio externo (S3/R2 compatible). Añade dependencia y variables nuevas |
| **D6** | Recuperación de contraseña: existe `password_reset_tokens` pero no hay proveedor de correo | Fase 3 | Resend, SendGrid, SMTP; o posponer | Posponer hasta tener proveedor |
| **D7** | Rutas de auth admin: el panel llama `/api/auth/admin/*` | Fase 2 | (a) Mover a `/api/admin/auth/*` y actualizar el panel; (b) mantener alias temporal | (a) + alias temporal hasta actualizar el panel |
| **D8** | Librería de hash | Fase 2 | `bcrypt` (nativa, la usa B y generó el hash del admin) o `bcryptjs` (JS puro, la usa A) | `bcryptjs` (sin compilación nativa en Render); hashes compatibles |
| **D9** | Logout con Bearer: no hay tabla de sesiones/lista negra | Fase 2 | (a) Logout solo en cliente (borrar token) + expiración corta; (b) tabla de sesiones nueva (cambio de schema) | (a) |
| **D10** | Dependencias nuevas | Fases 2, 6 | `zod` (validación), `express-rate-limit`, framework de tests (`vitest` + `supertest`), ESLint para reglas de importación | Autorizar `express-rate-limit` y `vitest`+`supertest`; validación manual o `zod` (tú eliges) |
| **D11** | Sacar `generated/` de git | Fase 1 | Sí / No | Sí (como B), regenerar en `postinstall` |
| **D12** | Compatibilidad con apps Flutter actuales (rutas provisionales) | Fase 1 | (a) Eliminar rutas viejas y actualizar apps; (b) mantener rutas viejas temporalmente | (a): las rutas viejas son inseguras y usan tablas que no existen en la BD real, no pueden funcionar contra ella |
| **D13** | Producción con `tsx` o compilado a `dist/` | Fase 7 | `tsx` (como B) / `tsc` → `node dist` | `tsx` al inicio; evaluar compilado en Fase 7 |
| **D14** | Notificaciones para trabajadores | Fase 6 | El schema solo notifica a `usuarios` | Sin notificaciones a trabajadores salvo cambio de schema |
| **D15** | Calificación del trabajador al cliente (pantalla `rate_client_screen` en app trabajador) | Fase 4 | No existe en el schema | Retirar de la app o cambio de schema |
| **D16** | Rotación de credenciales expuestas en el historial de `Que-Limpiamos` | Antes del deploy | — | Rotar contraseña de BD y secretos JWT; cambiar la contraseña del admin demo |
| **D17** | Convención de `dia_semana` | Fase 4 | 0=domingo…6=sábado (como el panel) o 1=lunes…7=domingo | Confirmar si ya hay datos cargados |

## Nuevas pendientes (2026-11-24)
Respondidas: D18 `America/Cancun`; D20 máx. 5 invitaciones configurable; D21 sin pagos por ahora (preparado para tabla `pagos`); D22 el cliente cancela en PENDIENTE o CONFIRMADO. Abiertas: D19 uso de `trabajador_servicios`, D20b si el máximo cuenta pendientes o total, D24 estados en que cancela el admin, y la autorización para ejecutar el SQL 002 (ver `11` y `12`).

## Actualización v3 (2026-11-24)
| Tema | Decisión |
|---|---|
| D20b | El máximo de 5 cuenta invitaciones **pendientes a la vez** (aceptado: "todo está bien") |
| D24 → Papel del admin | Solo aprueba documentos, ve el dashboard, administra el catálogo y los descuentos. **No interviene entre cliente y trabajador** (no asigna, no cancela, no toca invitaciones). La asignación de admin del backend de referencia NO se porta; el panel debe quitar esa función |
| Registro de trabajador | Se registra solo y sube documentos; no recibe trabajos hasta que el admin los aprueba |
| Especialidades | Las marca el trabajador; cuentan de inmediato |
| INE del cliente | Sin INE aprobada no puede crear solicitudes |
| Archivar trabajadores | En vez de borrar. Sus CONFIRMADO vuelven a la bolsa; con EN_PROCESO no se archiva |
| Cargo al cliente | Cancelar una CONFIRMADO con menos de 24 h antes del servicio → cargo según reglas (monto pendiente, hoy 0) |
| Cancelación del trabajador | Puede cancelar una CONFIRMADO; con menos de 24 h → cargo = saldo negativo; al cliente se le devuelve su dinero y se le avisa; la solicitud vuelve a PENDIENTE |
| D14 | Resuelto: tabla `notificaciones_trabajador` |

Abiertas: D26 descuentos (diseño), D27 si el trabajador recibe parte del cargo del cliente, D28 quién archiva (supuesto: admin) y si el trabajador puede darse de baja solo, D29 si un trabajador con saldo negativo puede seguir aceptando, montos de `reglas_cargo_cancelacion` y de `servicio_tarifas`, y la autorización para ensayar y ejecutar el SQL 002 v3.
Supuesto del asistente, a confirmar: el trabajador que canceló una solicitud no la vuelve a ver en la bolsa.

## Actualización v4 (2026-11-24)
| Tema | Decisión |
|---|---|
| Baja del trabajador | Archivar = dar de baja. Todas sus invitaciones se cancelan (`CANCELADA`, motivo `TRABAJADOR_DADO_DE_BAJA`) |
| Trabajos encimados | Un trabajador no puede aceptar trabajos que se crucen (p. ej. 10–12 y 11–13) |
| Re-invitar | No a la misma solicitud si ya rechazó; sí a solicitudes futuras |
| Nombres históricos | Las áreas (y por coherencia: servicio, especialidades, extras) guardan el nombre que tenían al pedir |
| updated_at | Debe actualizarse de verdad → verificado que la BD ya lo hace (`ON UPDATE`); se añade `@updatedAt` en Prisma |
| D29 | Con saldo negativo **sí** puede aceptar trabajos; la deuda se cubre con un % de cada ganancia o pagándola él |
| Dinero del trabajador | Libro de movimientos `trabajador_movimientos` (cuentas GANANCIAS/DEUDA, inmutable) |

Abiertas: D26 descuentos, D27 parte del cargo del cliente para el trabajador, D28 quién da de baja, D31 parte del precio que gana el trabajador, D32 % de retención, D33 compensar una deuda nueva con ganancias pendientes, D34 duración de los servicios (hoy 300 min) y margen entre trabajos. Supuestos a confirmar en `11` §8.

## Actualización v5 (2026-11-24)
Decidido: duración según servicio e inmueble (configurable), traslado de 60 min, reparto 85/15, retención del 10 % configurable, abono a la deuda elegido por el trabajador, libro inmutable, dinero como saldo en la plataforma, retiros futuros (sin implementar), compensación del 85 % si el cliente cancela tarde, disponibilidad por días y horarios con preferencia de mostrar fuera de horario, no reinvitar ni volver a mostrar tras cancelar, baja voluntaria y administrativa, varios inmuebles por cliente con snapshot en la solicitud.
Abiertas (detalle en `11` §8): D34 minutos reales, D36 confirmar el diseño POR_COBRAR, D37 comisión en pagos en efectivo, D38 diferencia entre el cargo al cliente y la compensación, D39 turnos partidos, D40 baja voluntaria inmediata o aprobada / reactivación, D26 descuentos.
**Bloqueante para el ensayo:** autorizar una BD de ensayo (`queLimpiamos_shadow`, vacía, o crear una con un usuario con permisos).

## Actualización v6 (2026-11-24)
Decidido:
- duración y precio provisionales, editables por el admin;
- efectivo: el 15 % queda como deuda;
- se conservan las 3 cuentas;
- cancelación tardía: 100 % al cliente y 100 % al trabajador;
- varias franjas por día;
- no puede desactivarse ni darse de baja con trabajos confirmados o en proceso;
- la baja es inmediata; la voluntaria la reactiva el trabajador y la administrativa solo el admin;
- la baja administrativa cancela todo (lo EN_PROCESO pasa a CANCELADO);
- descuentos completos, la plataforma absorbe la pérdida y el uso se consume aunque se cancele;
- BD de ensayo: `queLimpiamos_proyecto`.

Abiertas (detalle en `11` §0.6):
- D46 cobrar el cargo a un cliente que paga en efectivo;
- D47 cargo al trabajador en la baja administrativa (supuesto: no);
- D48 ¿varios descuentos por solicitud? (supuesto: uno);
- D49 elección entre descuentos automáticos (supuesto: el mayor);
- D50 bloquear tarjeta hasta tener pasarela;
- D51 cuándo pasa POR_COBRAR → DISPONIBLE.

**Pendiente: autorización para aplicar el 002 v6 en producción.**

## Actualización v7 (2026-11-24)
Decidido:
- D46: adeudo del cliente, cobrado en efectivo en su próximo servicio; el trabajador que lo cobra lo tiene como deuda (con motivo) y se libera la compensación del trabajador afectado. Si el cliente no vuelve → pérdida.
- Clientes registrados por teléfono (CHECK en la BD) y con INE.
- D47: sin cargo en la baja administrativa.
- D48/D49: un solo descuento por solicitud; se aplica el mayor.
- D50: tarjeta bloqueada hasta tener pasarela.
- D51: REALIZADO = efectivo confirmado + las dos partes marcan.

Abiertas:
- D52: ¿el trabajador pierde la compensación si el cliente nunca paga? (supuesto: sí);
- D53: ¿guardar un identificador de la INE para detectar cuentas duplicadas?
- D54: ¿qué pasa si una parte no marca el servicio como realizado?

**Pendiente: autorización para aplicar el 002 v7 en producción.**

## Actualización v8 (2026-11-24) — vigente
Decidido (detalle en `11` §0.9):
- D52: la compensación del trabajador afectado **siempre** se paga, una sola vez. Si el cliente vuelve y paga el adeudo, se paga con ese dinero; si no paga en `DIAS_ESPERA_PAGO_ADEUDO` días, la paga la plataforma (la pérdida es de la empresa). Si el cliente paga después, ese dinero se queda en la plataforma. La BD impide los pagos dobles.
- D53: al aprobar la INE se extrae el CURP, se normaliza y se guarda **cifrado fuera de la BD** solo para cuestiones legales. En la BD solo queda una huella (HMAC) única por cuenta, para detectar cuentas duplicadas. Las fotos de la INE se borran al terminar la revisión.
- D54 (sustituye D51): si el cliente confirma, REALIZADO y se paga. Si solo el trabajador confirma (con evidencia), en fin + 30 min se avisa al cliente y tiene 15 min; después se usa la evidencia. Si nadie confirma, en fin + 30 min se pide a ambos y en 30 min más se confirma solo, **sin pagar** hasta que haya evidencia o confirmación del cliente.

Abiertas:
- D55: días de espera antes de que la plataforma pague la compensación (provisional 30; 0 = al momento).
- D56: en la confirmación automática, ¿la deuda del 15 % del efectivo se registra ya o espera a la evidencia? (recomendación: ya).
- D57: ¿qué pasa si el cliente dice que el servicio no se hizo, o si el trabajador nunca llega?
- D58: dónde y cuánto tiempo se guarda el CURP fuera de la BD (infraestructura de la Fase 2; no cambia el SQL).

**Pendiente: autorización para aplicar el 002 v8 en producción.**

## Actualización v9 (2026-11-24) — vigente
Decidido (detalle en `11` §0.10):
- D55: plazo de 0 días. La plataforma paga la compensación de inmediato y absorbe el costo; el adeudo del cliente sigue pendiente y se intenta recuperar cuando vuelva a contratar. Recuperarlo no genera un segundo pago al trabajador.
- D56: la comisión del 15 % en efectivo se registra en cuanto el pago queda registrado, una sola vez, aunque nadie marque "terminado". Servicio y pago son estados independientes. Se avisa al trabajador. Las disputas las resuelve el admin y la corrección es un AJUSTE, sin borrar historial.
- D57: reportes de ambas partes desde la hora programada (no se pudo completar, inasistencia, ubicación con problemas o falsa, pago en disputa, otro), con evidencia de ambas partes. Decide el admin. Con un reporte pendiente no se confirma automáticamente. "No terminado" es un reporte y la calificación usa `resenas`.
- D58: el HMAC del CURP se calcula fuera de la BD; la BD guarda solo la huella UNIQUE. El CURP se guarda fuera de la BD principal durante el tiempo que fije la política de privacidad.

Abierta:
- D59: ¿quién puede registrar el pago en efectivo (cliente, trabajador o ambos)? Y si nadie lo registra y el servicio se confirma solo, ¿se presume pagado? (Supuesto: cualquiera de los dos; sin registro no hay comisión.)

**Pendiente: autorización para aplicar el 002 v9 en producción.**

## Actualización v10 (2026-11-24) — vigente
Decidido (detalle en `11` §0.10, "D59"):
- D59: cualquiera de las dos partes registra el pago en efectivo («Ya pagué en efectivo» / «Ya recibí el efectivo»); con una basta, y la comisión del 15 % se registra una sola vez. Si nadie lo registra, al confirmarse automáticamente el servicio se presume pagado (`SISTEMA`), solo si el trabajador lo inició y no hay reportes, disputas, cancelación ni incidencia pendientes. El trabajador puede reportar que no recibió el efectivo; el admin mantiene o anula la comisión con un AJUSTE, sin borrar el historial.

No quedan decisiones abiertas sobre el SQL 002.

**Pendiente: autorización para aplicar el 002 v10 en producción.**

## D63a — Cuenta candidata a propietario (consulta de SOLO LECTURA en producción, 2026-11-24) — SIN asignar permisos
| id | Correo (enmascarado) | Estado | Creada | Observación |
|---|---|---|---|---|
| **1** | `ad***@q***********.demo` | ACTIVA | 2026-11-15 | Es la **única** cuenta de producción (usuarios = 1, rol ADMIN). Su dominio es **`.demo`**: parece la cuenta de demostración, y su contraseña pudo quedar expuesta en el historial de git de `Que-Limpiamos` y del panel (D16) |

**Recomendación (a decidir por el usuario):**
- antes de nombrarla propietaria, **cambiar su contraseña** (D16);
- o, mejor, crear una cuenta de propietario con un correo real tuyo, por script revisado, y dejar la cuenta demo sin permisos especiales.

No se otorgó ningún permiso: `admin_permisos` ni siquiera existe todavía (SQL 003 no aplicado).

## D66 y D67 — DECIDIDAS (usuario, 2026-11-24)
| ID | Decisión | Consecuencia |
|---|---|---|
| **D66** | Los documentos de identidad los ven **solo los administradores con el permiso específico de revisión de identidad** | Permiso `REVISAR_DOCUMENTOS_IDENTIDAD` en `admin_permisos` (SQL 003 v2), otorgado y revocado **solo por el propietario** (D63), con historial. Cada consulta se registra en `documento_accesos` y usa una URL temporal de 60 s. Tener sesión de admin no basta |
| **D67** | Las **evidencias de servicio** se conservan **12 meses**. Los **documentos INE** tienen una **política de eliminación aparte**: se borran al **concluir su revisión** (D53), no a los 12 meses | Evidencias: borrado programado a los 12 meses del cierre del servicio o de su reporte (tarea periódica, Fase 4/6). INE: borrado del archivo al aprobar o rechazar (`archivo_eliminado_en`); como red de seguridad, borrado de lo que siga en el espacio `identidad` 30 días después. La fila del documento y su historial se conservan |

## D5 CORREGIDA por el usuario (2026-11-24) — prevalece sobre la fila D5 de abajo
Proyecto escolar, **sin gastos**: **no** se agregan R2 ni proveedores externos por ahora. **Almacenamiento local privado** para desarrollo:
- fuera de las carpetas públicas y de git;
- con abstracción para migrar a S3 compatible;
- acceso con autenticación y permisos;
- validación de tamaño, tipo real y extensión;
- sin GPS;
- sin rutas estáticas ni URLs públicas;
- documentar que Render no es persistente;
- solo dependencias gratuitas y ninguna de nube.

→ **Implementado y probado** (`16` v2). D5a (proveedor) queda **aplazada** hasta que haga falta.

## D5, D63, D64, D65 y seguridad de autenticación — DECIDIDAS (usuario, 2026-11-24)
El SQL 002 y el 003 siguen **sin autorización** para producción.
| ID | Decisión del usuario | Consecuencia / estado |
|---|---|---|
| **D5** Almacenamiento | Archivos en un **almacenamiento privado en la nube**, separado de la BD y del servidor público. **Sin URLs públicas permanentes**; acceso con autorización y **URLs temporales**. Los documentos de identidad, **solo personal autorizado**. Debe haber un procedimiento para **eliminar o reemplazar** documentos. Antes de elegir proveedor: alternativas, costos y compatibilidad | Diseño, alternativas y costos en **`16_DISENO_ALMACENAMIENTO_DOCUMENTOS.md`**. **Falta elegir proveedor** (D5a) |
| **D63** Permisos financieros | Solo el **administrador principal o propietario autorizado** otorga o revoca el permiso de incidencias financieras. Toda asignación y revocación queda en la auditoría. **Nadie se otorga ese permiso a sí mismo** | Requiere el cambio de schema propuesto en `13` §7 (SQL 003 v2): permiso `ADMINISTRAR_PERMISOS` del propietario y CHECK contra el auto-otorgamiento. **Falta:** qué cuenta es la del propietario (D63a) |
| **D64** Plazo de reclamación | Las 24 h **también** aplican cuando el **cliente** registra que pagó. El trabajador recibe un aviso del pago registrado y tiene 24 h. El plazo se calcula y **guarda al registrarse, sin modificarse después** | `reporte_pago_hasta` se llena cuando el pago lo registra el CLIENTE o el SISTEMA (no cuando lo registra el propio trabajador). Tipo de aviso nuevo `PAGO_EFECTIVO_REGISTRADO` en `13` §7 (SQL 003 v2). Escritura única: `UPDATE … WHERE reporte_pago_hasta IS NULL` |
| **D65** INE en revisión | Con la INE en revisión el cliente **puede** registrarse, completar su perfil, agregar inmuebles y cotizar. **No puede** enviar una solicitud definitiva ni contratar hasta que su identidad esté **aprobada**. Mostrar el estado de verificación y el **motivo del rechazo**, y permitir **volver a subir** el documento | Reglas de la Fase 3 (`15`): `POST` de solicitud → 403 `IDENTIDAD_NO_VERIFICADA` si `usuarios.estado_verificacion ≠ VERIFICADO`. El perfil devuelve el estado y el motivo. Re-subida con historial (`16` §5) |
| **Seguridad de auth** | **Aprobado:** límite de intentos de inicio de sesión con bloqueo **temporal progresivo**, protección contra abuso y respuestas que **no revelen** si el correo o el teléfono existen. **Nunca** bloqueo permanente | Diseño en `14` §5. Se implementa como primer paso (orden en `15` §0) |

Abiertas nuevas:
- **D5a:** proveedor (`16` §3).
- **D63a:** cuenta del propietario.
- **D63b:** si el propietario también necesita el permiso financiero, ¿se le asigna por script revisado? (La BD impedirá que cualquiera se lo otorgue a sí mismo.)
- **D66:** quién es "personal autorizado" para ver documentos de identidad (`16` §6).
- **D67:** cuánto tiempo se conservan las evidencias de los servicios (`16` §6).

## D60, D61 y D62 — CERRADAS (decisión del usuario, 2026-11-24) → SQL 003 (detalle en `13`)
| ID | Decisión | Cómo queda |
|---|---|---|
| D60 | Protección **en la BD** contra notificaciones duplicadas por el mismo evento, conservando las de eventos distintos | `clave_evento NOT NULL` + UNIQUE por destinatario en `notificaciones` y `notificaciones_trabajador`. Las existentes quedan como `LEGADO:<id>`, sin perder datos |
| D61 | **24 horas** desde la confirmación automática del pago presumido. El trabajador recibe un aviso claro con el plazo y cómo reportar | Parámetro `HORAS_PLAZO_REPORTE_PAGO = 24` y `solicitudes.reporte_pago_hasta` (fecha guardada al presumir). Aviso `PAGO_EFECTIVO_PRESUMIDO` único, con fecha y ruta en la app ("Reportar → No recibí el efectivo"). Fuera de plazo: 409 |
| D62 | Solo un admin **activo** con **permiso específico** para incidencias y movimientos financieros. No basta con la sesión. La identidad sale de la sesión, nunca del body | Tabla `admin_permisos` (con historial), resolución con `admin_id NOT NULL` + FK compuesta al permiso del **mismo** admin, y todo AJUSTE con resolución (CHECK). El backend comprueba en la misma transacción: rol ADMIN, cuenta ACTIVA y permiso vigente (con bloqueo de la fila) |

Nuevas abiertas: **D63** (a quién se otorga el permiso y quién lo otorga o revoca), **D64** (si el plazo de 24 h también cuenta cuando el pago lo registró el cliente) y **D65** (si se puede pedir con la INE en revisión). Ver `15` §5.

## Fase 2 — decisiones técnicas adoptadas (2026-11-24)
Se aplicó la recomendación documentada de cada una; todas son reversibles y no tocan la BD.
| ID | Adoptado | Notas |
|---|---|---|
| D7 | `/api/admin/auth/*` + alias temporal `/api/auth/admin/*` | El panel funciona sin cambios. Quitar el alias cuando el panel use la ruta nueva |
| D8 | `bcryptjs` (JS puro). Se desinstaló `bcrypt` (nativo, no se usaba en el código) | Compatible con los hashes `$2a$`/`$2b$` existentes |
| D9 | (a) Logout en la app + expiración (7 d apps, 8 h panel) | Además, cambiar la contraseña invalida todos los tokens anteriores (huella `pwv` en el token), sin tabla de sesiones |
| D10 | Solo `jsonwebtoken` y `cookie-parser` (previstos en el plan). **Pruebas con el runner nativo `node:test`** (sin vitest ni supertest) y validación manual (sin zod) | **Pendiente:** rate limiting en los logins (`express-rate-limit`), previsto para la Fase 6. **Debe estar antes del deploy** |

## Revisión de D59 en el backend (2026-11-24) — el SQL 002 v10 NO se modifica
Estado real comprobado en `backend/src`: solo existe la Fase 1 (health y errores). **No hay** tarea periódica, auth, módulo admin ni endpoints de pagos o reportes. Las garantías de D59 hoy solo están en el SQL y en el ensayo (`ensayo-002.ts`, 43/43).

| ID | Punto | Estado real | Propuesta |
|---|---|---|---|
| **D60** | La tarea periódica no debe generar notificaciones duplicadas | **No implementado** (Fase 4). Diseño: cada notificación se crea en la misma transacción que un `UPDATE` condicional (`… WHERE estado = 'EN_PROCESO'`, `… IS NULL`), así que una segunda ejecución, o una simultánea, no cambia filas y no notifica. Probado solo en el ensayo (`avisos = 1` con dos ejecuciones a la vez). **No hay garantía en la BD**: `notificaciones` y `notificaciones_trabajador` no tienen ninguna restricción única | (a) **Ahora, sin cambiar el schema:** en la Fase 4, cada notificación de la tarea con su prueba de doble ejecución. (b) **SQL 003 (futuro, con tu autorización):** columna `clave_unica VARCHAR(120) NULL UNIQUE` en ambas tablas (p. ej. `PAGO_EFECTIVO_PRESUMIDO:sol:123`), para que la BD rechace el duplicado. **Recomendación:** (a) ya, y (b) junto con el siguiente cambio de schema |
| **D61** | Plazo para que el trabajador reporte que no recibió el efectivo | **No definido** en el SQL, los parámetros ni los documentos. Hoy un `PAGO_EN_DISPUTA` podría abrirse en cualquier momento | Parámetro **`HORAS_PLAZO_REPORTE_PAGO`** en `parametros_negocio` (es un dato, no schema; se insertaría con un SQL 003 de datos o desde el dashboard del admin). Se cuenta desde `pago_registrado_en`. Dentro del plazo el trabajador puede reportar; fuera de él el backend responde 409 y la comisión queda firme. **Necesito el valor:** opciones 24, 48 o 72 h (recomendación: **48 h**) |
| **D62** | Solo un admin autorizado resuelve el reporte, anula el pago presumido y genera el AJUSTE | **No implementado** (no hay auth ni módulo admin). En la BD, `solicitud_resoluciones.admin_id` es una FK **opcional** (`SET NULL`) a `usuarios` **sin comprobar el rol**: la BD no puede exigir que sea ADMIN (no hay CHECK entre tablas) | (1) **Fase 2 (esta tarea):** guard `requireAdmin`, que exige token de audiencia admin, `rol = ADMIN` y `estado_cuenta = ACTIVA`, verificados en la BD en cada petición. (2) **Fase 5:** el endpoint de resolución toma `admin_id` de la sesión (nunca del body) y hace todo en una transacción: reportes a RESUELTO, `estado_pago` y AJUSTE con `resolucion_id`. (3) **SQL 003 (futuro):** `admin_id NOT NULL` + `ON DELETE RESTRICT` (los admins no se borran, se suspenden). **Necesito confirmar:** ¿"autorizado" = cualquier admin ACTIVO (único modelo que existe hoy) o hace falta un permiso especial para resolver disputas de dinero? Supuesto: cualquier admin activo |

## Reseñas y reportes (2026-11-25) — decididas por el usuario
- **Especificación definitiva en `20_ESPECIFICACION_RESENAS_Y_REPORTES.md`.** Incluye: reseñas en las dos direcciones, solo tras finalizar, 1–5 estrellas, comentario opcional y sin fotos, una por usuario y servicio, opcionales, publicadas de inmediato, autor oculto para los usuarios y no editables por ellos; promedio del trabajador en su perfil y en la selección manual. Reportes independientes, antes o después de finalizar, con fotos opcionales. Moderación del admin (editar y eliminar) con **auditoría obligatoria** (admin, fecha, operación, antes, después, motivo).
- **Abiertas:** Q1–Q8 en `20` §8 (filas antiguas de `resenas`, plazo para calificar, largo del comentario, vistas autorizadas de la reputación del cliente, datos que se ocultan para no deducir el autor, permiso de moderación, límites de fotos, borrado lógico o físico).
- Se implementa en la **Fase 3a**; el cambio de schema va en el SQL 003 v2 (requiere autorización).

## Reseñas y reportes v2 (2026-11-25) — decididas por el usuario; prevalece sobre la sección anterior
- **Decidido:** plazo de 7 días para calificar; se muestran solo calificación, comentario y mes/año (sin servicio ni fecha exacta); reputación del cliente solo para el trabajador invitado o asignado y para los admins; fotos de reportes (máx. 5, 8 MB cada una, 16 MB en total); descripción y fotos opcionales en los reportes; eliminación administrativa lógica; permiso `MODERAR_CONTENIDO` que otorga el propietario; asignación inicial auditada; **las reseñas antiguas no se conservan** (se reconstruye `resenas`).
- **X0 decidida (2026-11-25):** el administrador con `MODERAR_CONTENIDO` **ve al autor** de cada reseña en el panel de moderación. Para clientes y trabajadores el autor sigue oculto siempre.
- **Abiertas** (`20` §10): X1 largo del comentario (500 sin confirmar); X2 tipos de archivo; X3 MB = 10^6 o 2^20; X4 volver a calificar tras una eliminación; X5 reporte eliminado y D57; X6 si el reportado ve el reporte; X7 desde cuándo cuentan los 7 días; X8 zona horaria; D63a/D63b.
- SQL preparado (no aplicado): `21`.

## Fase 3a (2026-11-25) — TODAS las decisiones de reseñas y reportes RESUELTAS (prevalece sobre las dos secciones anteriores)
| Clave | Decisión |
|---|---|
| X0 | El admin con `MODERAR_CONTENIDO` ve al autor; clientes y trabajadores nunca. Sin el permiso: 403 en `GET /api/admin/resenas` |
| X1 | Comentario de máximo 500 caracteres |
| X2 | Fotos de reportes: JPEG, PNG y WebP |
| X3 | 1 MB = 1 000 000 bytes |
| X4 | La reseña eliminada lógicamente sigue ocupando su lugar único: no se puede volver a calificar |
| X5 | Un reporte eliminado lógicamente deja de bloquear la confirmación automática |
| X6 | El reporte completo solo lo ven su autor y los admins autorizados; el reportado no lo ve ni conoce al reportante |
| X7 | Los 7 días empiezan exactamente cuando la solicitud pasa a `REALIZADO` (`solicitudes.realizado_en`) |
| X8 | Fechas en UTC; plazo de 168 horas exactas |
| D63a | Propietario: la cuenta con el correo indicado por el usuario (`sa***@gmail.com`; el correo completo no se publica aquí). **Asignación pendiente:** esa cuenta no existe todavía |

- **Decisiones técnicas tomadas al implementar** (dentro de las reglas aprobadas):
  - el tipo del reporte es opcional (`OTRO` por defecto) porque la columna del 002 es obligatoria;
  - `PAGO_EN_DISPUTA` solo del trabajador y dentro de `reporte_pago_hasta` (D59/D61);
  - la moderación no resuelve un `PAGO_EN_DISPUTA` (es financiero, D62);
  - el propietario no puede revocar su propio permiso.
- **Sigue abierto:** D63b (si el propietario recibe también los permisos financiero y de identidad); D64 y las tablas de documentos en el 003 v2; la autorización para aplicar el 002 y el 003 v2 en producción.

## Siguiente fase: ciclo de las solicitudes sin dinero (2026-11-25) — decididas por el usuario; la fase NO ha empezado
Contexto: la Fase 3b (reseñas y reportes en las apps) quedó **validada manualmente** por el usuario en el teléfono (doc `24`).

| Clave | Decisión |
|---|---|
| Alcance | **Ciclo sin dinero:** cotizar, crear, aceptar o rechazar, cancelar, iniciar, marcar terminado y confirmación automática (D54, tarea periódica). **Sin** pago en efectivo, comisión del 15 %, cargos, compensaciones, descuentos ni adeudos: `estado_pago` queda `PENDIENTE` y nada se libera |
| D65 para probar | Se mantiene D65 (403 `IDENTIDAD_NO_VERIFICADA`). El script de datos locales marca como `VERIFICADO` **solo** a la cuenta ficticia del cliente (`.test`), en la BD local. La subida de la INE queda para su fase |
| D4 precio | Precio único del servidor = precio base del servicio + extras elegidos. Los incrementos por tamaño y tipo de inmueble siguen en 0 hasta que se definan. La app muestra ese precio, sin rango, y nunca envía el total |
| Negociación | **Se quita** en las solicitudes reales: el trabajador solo acepta o rechaza al precio calculado |
| Invitaciones (D2) | Con colaborador elegido: una invitación a ese trabajador. Sin colaborador: bolsa de los elegibles. El backend admite hasta 5 (D20) para ampliarlo después |
| Elegibilidad | Cuenta activa y verificada, especialidades del servicio y sin trabajos encimados (traslado de 60 min). **Sin filtro por horario** hasta decidir D17 |
| Evidencia (D54) | Para marcar «terminado» el trabajador sube **al menos 1 foto** (máx. 5; JPEG, PNG o WebP; mismas reglas de tamaño que los reportes) |
| Chat | **Se oculta** en las solicitudes reales (no hay tabla ni rutas de mensajes) |
| Cancelaciones | Se permiten las que no generan dinero: en PENDIENTE y en CONFIRMADO con **24 h o más** de anticipación. Con menos de 24 h responden «no disponible todavía» hasta la fase de dinero |

**Ya decidido antes, que se aplica:**
- D50: tarjeta bloqueada hasta tener pasarela; la app ofrece solo efectivo.
- D12: las rutas obsoletas `/galaxias` y `/hoyo-negro` se sustituyen por rutas `/api/...` en las dos apps.
- D60: avisos con `clave_evento`.
- D57 y X5: un reporte pendiente impide la confirmación automática.
- Todo se desarrolla y prueba en la BD **local**. Producción sigue sin el 002 ni el 003 v2.

**Propuesta técnica del asistente:** ~~el inmueble se crea o reutiliza a partir del formulario~~. **Corregida** en el doc `25` (supuesto S3): solo el snapshot en la solicitud, con `inmueble_id = NULL`, como permite `11` §4.6.

## Panel web en el ciclo de solicitudes (2026-11-25) — decididas por el usuario; la fase NO ha empezado
El panel web entra en el alcance de la fase. El plan completo está en `25_PLAN_CICLO_SOLICITUDES.md`.

| Clave | Decisión |
|---|---|
| Ver solicitudes | Con un **permiso nuevo**, `SUPERVISAR_SOLICITUDES`, que otorga el propietario. Requiere un **SQL 004** (valor nuevo del ENUM de `admin_permisos`), que se autoriza aparte |
| Botones del detalle | **Se quitan** asignar o cambiar colaborador, confirmar, finalizar y cancelar (D24): el panel solo supervisa |
| Intervención | **Resolución del servicio** (realizado o no realizado) cuando hay un reporte, **sin la parte de pago**. La hace un admin con `GESTIONAR_INCIDENCIAS_FINANZAS` (D62), con motivo y auditoría. El propietario podrá otorgar ese permiso |
| Solicitud sin aceptar | **Vence sola** al llegar su hora programada: CANCELADO por el sistema, con las invitaciones cerradas y aviso al cliente. Sin cargo |
| Rechazo del invitado | La solicitud sigue PENDIENTE y **el cliente decide**: enviarla a la bolsa, invitar a otro colaborador o cancelarla |
| Moderación de reportes | Los reportes de una solicitud **sin cerrar** solo se resuelven con la resolución del servicio. La moderación sigue editando, eliminando y resolviendo los de solicitudes ya cerradas |

**Supuestos a confirmar al autorizar:** S1–S9 en `25` §5.

## Autorización de la fase (2026-11-25) — prevalece sobre las dos secciones anteriores y sobre los supuestos S1–S9 de la v1 del `25`
El usuario autorizó implementar y probar la fase **solo en local**. Plan vigente: `25` v2.

| Tema | Decisión |
|---|---|
| Ventana de inicio | De **30 min antes a 30 min después** de la hora programada, sujeta a disponibilidad y al traslado de 60 min. Más tarde, la solicitud sigue CONFIRMADA y genera una **alerta** para administración. El cliente puede reportar la inasistencia |
| Mis inmuebles | **Se incluye en esta fase.** Inmuebles sin límite, con nombre; consultar, editar y eliminar (archivar); elegir uno guardado o capturar uno nuevo sin guardarlo. La solicitud conserva una **copia inmutable** (también el nombre: columna nueva en el SQL 004). *Sustituye "por ahora no hay pantallas de «Mis inmuebles»" y el supuesto S3 de la v1* |
| Vencimiento | Cancelación automática por el sistema, invitaciones cerradas con el motivo nuevo **`VENCIDA`** (SQL 004), aviso al cliente y sin cargos |
| Resoluciones | **Inmutables** desde el panel: ni se corrigen ni se sustituyen. La rectificación futura será un procedimiento aparte (no en esta fase). *Sustituye la regla de `11` §0.10 "si el admin cambia de criterio, registra otra resolución"* |
| Propietario | Tiene `SUPERVISAR_SOLICITUDES` **automáticamente**, sin asignárselo, y puede otorgarlo a otros admins |
| Resoluciones simultáneas | Gana la primera; la segunda recibe **409**; nada se sobrescribe y la auditoría queda íntegra |
| Cuentas de prueba locales | El propietario de prueba con el correo de D63a, 2 admins ficticios y un 2.º trabajador ficticio. Las credenciales, solo en `backend/.local/` |
| Actualización | Panel cada 20 s (solo con la página visible); app del cliente cada 15 s en el detalle; app del trabajador cada 3 s |
| Pruebas | Pruebas locales completas de principio a fin, además de las automáticas |

## Cierre de la Fase 3 (2026-11-25) — decidido por el usuario
| Tema | Decisión |
|---|---|
| Cierre | La Fase 3 (3a, 3b y el ciclo sin dinero) queda **COMPLETADA** (informe `26`) |
| Alcance | El **perfil del cliente** (`GET/PATCH /api/cliente/perfil`), el **dinero** (pagos, comisión, cargos, compensaciones, descuentos, adeudos) y los **documentos e INE**, que el doc `15` incluía en la Fase 3, pasan formalmente a fases posteriores |
| E1 | Se autoriza corregir `app_state_test`: esperar (`await`) a `acceptOpportunity`, sin cambiar lo que verifica |
| Siguiente fase | No empieza hasta que el usuario la apruebe |
