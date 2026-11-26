# 06 — Contratos de la API

- **Fecha:** 2026-11-24 · **Fase:** 2 (autenticación). Las demás rutas se agregan en las Fases 3–5.
- Errores siempre con la forma `{ "mensaje": string, "codigo"?: string }`. Las apps muestran `mensaje`.
- IDs numéricos. Fechas en ISO 8601 (UTC).

## Autenticación por audiencia
| Audiencia | Prefijo | Cómo viaja la sesión | Vigencia por defecto |
|---|---|---|---|
| Cliente | `/api/cliente` | `Authorization: Bearer <token>` | 7 días |
| Trabajador | `/api/trabajador` | `Authorization: Bearer <token>` | 7 días |
| Admin | `/api/admin` (alias `/api/auth/admin`) | Cookie httpOnly `ql_admin` | 8 horas |

- Cada audiencia tiene su propio secreto y su `aud`: un token de una audiencia **nunca** sirve en otra.
- En cada petición el backend comprueba en la BD que la cuenta exista, tenga el rol correcto, no esté suspendida y no haya cambiado de contraseña.
- **Cambiar la contraseña invalida todos los tokens anteriores.**
- Logout de las apps (D9-a): la app borra su token. El token sigue siendo válido hasta que expira; no hay lista de sesiones.
- Las rutas de admin que cambian algo (POST, PUT, PATCH, DELETE) exigen un encabezado `Origin` que esté en `CORS_ORIGINS` (protección CSRF). El navegador lo envía solo.

### Códigos de error de autenticación
| HTTP | `codigo` | Cuándo |
|---|---|---|
| 400 | `DATOS_INVALIDOS` | Falta un campo o no es válido (el `mensaje` dice cuál) |
| 400 | `JSON_INVALIDO` | El body no es JSON |
| 400 | `PASSWORD_ACTUAL_INCORRECTA` | Cambio de contraseña con la actual mal |
| 401 | `NO_AUTENTICADO` | No viene token o cookie |
| 401 | `TOKEN_INVALIDO` | Token alterado, de otra audiencia o de una cuenta que ya no corresponde |
| 401 | `SESION_EXPIRADA` | El token expiró o la contraseña cambió: volver a iniciar sesión |
| 401 | `CREDENCIALES_INVALIDAS` | Login fallido (mismo mensaje exista o no la cuenta) |
| 403 | `CUENTA_SUSPENDIDA` | Cuenta de cliente o admin suspendida |
| 403 | `ORIGEN_NO_PERMITIDO` | Petición de admin sin `Origin` permitido |
| 409 | `CORREO_EN_USO` / `TELEFONO_EN_USO` | Registro con correo o teléfono ya usados |
| 429 | `DEMASIADOS_INTENTOS` | Demasiados intentos: por IP (login 30/15 min, registro 10/h, cambio de contraseña 10/15 min) o por cuenta (5 fallos gratis, 3 en el panel, y después bloqueos de 1, 5, 15, 30 y 60 min; **nunca permanente**). Trae `Retry-After` (segundos). Mismo mensaje exista o no la cuenta; durante el bloqueo ni la contraseña correcta entra |

## Cliente — `/api/cliente/auth`
| Método | Ruta | Body | Respuesta |
|---|---|---|---|
| POST | `/registro` | `{ nombre, correo, telefono, password }` | `201 { token, cliente }` |
| POST | `/login` | `{ correo, password }` **o** `{ telefono, password }` | `200 { token, cliente }` |
| GET | `/me` | — (Bearer) | `200 { cliente }` |
| POST | `/logout` | — (Bearer) | `204` |
| POST | `/cambiar-password` | `{ password_actual, password_nueva }` (Bearer) | `200 { token }` (el nuevo; el anterior deja de valer) |

`cliente = { id, nombre, correo, telefono, rol: "CLIENTE", foto_url, estado_cuenta, estado_verificacion }`

- `telefono` es **obligatorio** (los clientes se registran por número): 10 dígitos; se aceptan espacios, guiones y `+52`.
- `password`: mínimo 8 caracteres, máximo 72 bytes. El correo se guarda en minúsculas.
- Cualquier `rol` del body se ignora: el registro siempre crea un CLIENTE.

## Trabajador — `/api/trabajador/auth`
| Método | Ruta | Body | Respuesta |
|---|---|---|---|
| POST | `/registro` | `{ nombre, correo, telefono, direccion, password }` | `201 { token, trabajador }` |
| POST | `/login` | `{ correo, password }` **o** `{ telefono, password }` | `200 { token, trabajador }` |
| GET | `/me` | — (Bearer) | `200 { trabajador }` |
| POST | `/logout` | — (Bearer) | `204` |
| POST | `/cambiar-password` | `{ password_actual, password_nueva }` (Bearer) | `200 { token }` |

`trabajador = { id, rol: "TRABAJADOR", nombre, correo, telefono, direccion, foto_url, estado }`. `rol` es fijo: lo exige el modelo `ApiUser` de la app

- Un trabajador sin contraseña asignada (`password_hash` NULL) no puede iniciar sesión.
- Hasta que se aplique el SQL 002 no existe `estado_verificacion`. Un trabajador recién registrado no recibe trabajos porque esas rutas todavía no existen (Fase 4).

## Admin — `/api/admin/auth` (alias temporal `/api/auth/admin`, D7)
| Método | Ruta | Body | Respuesta |
|---|---|---|---|
| POST | `/login` | `{ correo, password }` | `200 { usuario }` + `Set-Cookie: ql_admin=…; HttpOnly; Path=/` |
| GET | `/session` (también `/me`) | — (cookie) | `200 { usuario }` |
| POST | `/logout` | — | `204` + borra la cookie |

`usuario = { id, nombre, correo, rol: "ADMIN" }`: es el tipo `Sesion` del panel (`appWeb/src/data/tipos.ts`).

- El panel debe usar `credentials: "include"` (ya lo hace).
- En producción la cookie lleva `Secure; SameSite=None`; en desarrollo, `SameSite=Lax`.
- El token nunca va en el body.

## Archivos privados — `/api/archivos`
| Método | Ruta | Respuesta |
|---|---|---|
| GET | `/temporal/<token>` | El archivo, con `Cache-Control: no-store` y `X-Content-Type-Options: nosniff`. 404 si el token es falso, está alterado o vencido, o si el archivo no existe |

Las URLs temporales (relativas: la app les antepone su `API_URL`) solo las emiten endpoints que ya autorizaron a quien las pide (Fases 3c y 5). No hay rutas estáticas. Detalle en `16`.

## Cambios pendientes en los consumidores (detalle y estado en `14`)
- **Apps Flutter** (`AuthApi` en `.../services/api_client.dart`):
  - cambiar `/login` y `/signup` por `/api/cliente/auth/login` y `/registro` (o las de trabajador);
  - leer `token` y `cliente` (o `trabajador`) en vez de `estrella`;
  - guardar el token y enviarlo como `Authorization: Bearer`;
  - quitar `rol` del registro;
  - en la app del trabajador, mandar `direccion`.
- **Panel:**
  - ya llama a `/api/auth/admin/login`; puede pasar a `/api/admin/auth/login`, y entonces se quita el alias;
  - al abrir, llamar a `GET /session` para validar la cookie y, ante un 401, volver al login;
  - el botón de cerrar sesión debe llamar a `POST /logout`.

## Fase 3a — reseñas, reportes, moderación y permisos (2026-11-25)
Contratos implementados y probados: `20_ESPECIFICACION_RESENAS_Y_REPORTES.md` §8 (rutas y autorización) y los DTO en `src/dominio/{resenas,reportes,moderacion,permisos}.ts`. Resumen de formatos:
- **Reseña pública:** `{ puntuacion, comentario, mes, anio }`. Sin autor, id, servicio ni fecha exacta.
- **Reseña propia:** `{ id, solicitudId, calificaA, puntuacion, comentario, fecha, editadaPorModeracion, eliminadaPorModeracion }`.
- **Reputación:** `{ promedio: number | null, cantidad }`.
- **Reporte propio:** `{ id, solicitudId, reportaA, tipo, descripcion, estado, fecha, eliminadoPorModeracion, evidencias: [{ id, tipoMime, tamanoBytes }] }`.
- **Crear un reporte:** `multipart/form-data` con `tipo?`, `descripcion?` y `fotos[]` (máx. 5 · 8 MB · 16 MB; JPEG, PNG o WebP), o JSON sin fotos.
- **Moderación:** toda modificación exige `motivo` (1–500). Errores: `{ mensaje, codigo }`. Códigos nuevos: `PUNTUACION_INVALIDA`, `COMENTARIO_LARGO`, `FOTOS_NO_PERMITIDAS`, `SERVICIO_NO_FINALIZADO`, `PLAZO_VENCIDO`, `RESENA_DUPLICADA`, `NO_ES_PARTE`, `REPUTACION_NO_AUTORIZADA`, `REPORTE_ANTES_DE_HORA`, `SIN_CONTRAPARTE`, `DEMASIADAS_FOTOS`, `FOTO_DEMASIADO_GRANDE`, `REPORTE_DEMASIADO_GRANDE`, `TIPO_NO_PERMITIDO`, `EXTENSION_NO_COINCIDE`, `TIPO_NO_COINCIDE`, `PERMISO_REQUERIDO`, `MOTIVO_REQUERIDO`, `AUTO_OTORGAMIENTO`, `AUTO_REVOCACION`, `RESOLUCION_FINANCIERA`.

## Fase 3b — consultas para las apps (2026-11-25, solo lectura)
Detalle en `23_FASE_3B_INSPECCION_APPS.md` §1.
- `GET /api/cliente/solicitudes` → `{ solicitudes: [{ id, estado, fechaProgramada, realizadoEn, servicio, direccion, trabajador: { id, nombre } | null, miResena: { puntuacion, comentario, fecha, eliminadaPorModeracion } | null, calificarHasta, puedeCalificar, puedeReportar }] }`
- `GET /api/trabajador/solicitudes` → `{ solicitudes: [{ id, estado, relacion: "ASIGNADO" | "INVITADO", invitacion, fechaProgramada, realizadoEn, servicio, cliente: { nombre }, miResena, calificarHasta, puedeCalificar, puedeReportar, puedeVerReputacionCliente }] }`
- `GET /api/cliente/trabajadores?servicioId=` → `{ trabajadores: [{ id, nombre, especialidades: string[], reputacion: { promedio, cantidad } }] }`. Solo `ACTIVO` y `VERIFICADO`; con `servicioId`, solo quien tiene todas las especialidades exigidas (404 si el servicio no existe).

## Ciclo de las solicitudes sin dinero (2026-11-25, doc `25` v2)
Errores: `{ mensaje, codigo }`. Todo cambio de estado es un `UPDATE` condicional: si otro llegó antes, 409. Sin pagos ni movimientos (`estado_pago` siempre `PENDIENTE`).

**Cliente** (`Authorization: Bearer`)
- `GET /api/cliente/catalogo` → `{ servicios: [{ id, nombre, descripcion, precioBase, duracionMin, especialidades }], areas: [{ id, nombre }], extras: [{ id, nombre, descripcion, precio, duracionMin }] }`.
- `POST /api/cliente/cotizaciones`:
  - **Cuerpo:** `{ servicioId, fechaProgramada (ISO), areaIds?, extraIds?, notas? (≤ 500), inmuebleId | inmueble: { tipo, direccion, habitaciones, banos, mediosBanos, pisos, guardarComo? } }`.
  - **Respuesta:** `{ cotizacion: { servicio, fechaProgramada, duracionMin, finEstimado, precio: { base, extras, total, moneda }, extras, areas, inmueble, especialidadesRequeridas, metodoPago: "EFECTIVO" } }`.
  - No crea nada y se permite con la INE en revisión.
  - **Errores:**
    - 400: `FECHA_PASADA`, `FECHA_DEMASIADO_LEJANA` (más de 365 días), `DATOS_INVALIDOS`;
    - 404: `SERVICIO_NO_ENCONTRADO`, `EXTRA_NO_ENCONTRADO`, `AREA_NO_ENCONTRADA`, `INMUEBLE_NO_ENCONTRADO`.
- `POST /api/cliente/solicitudes`:
  - **Cuerpo:** el mismo que la cotización, más `trabajadorId?`.
  - **Respuesta:** 201 `{ solicitud }`, con el detalle de abajo.
  - **Errores:**
    - 403: `IDENTIDAD_NO_VERIFICADA`;
    - 409: `SOLICITUD_DUPLICADA` y `COLABORADOR_<NO_ACTIVO | NO_VERIFICADO | SIN_ESPECIALIDADES | TRASLAPE>`.
  - Sin `trabajadorId` va a la bolsa. El precio que mande el cliente **se ignora** (D4).
- `GET /api/cliente/solicitudes`: los campos de la Fase 3b **más** los del detalle.
- `GET /api/cliente/solicitudes/:id` → `{ solicitud }`. Los campos:
  - datos: `id`, `estado`, `modo` (`INVITACION` o `BOLSA`), `servicio`, `fechaProgramada`, `finEstimado`, `duracionMin`, `precio`, `metodoPago`, `direccion`, `notas`, `areas`, `extras`, `creadaEn`;
  - `inmueble` (copia: `{ nombre, tipo, habitaciones, banos, mediosBanos, pisos }`);
  - `trabajador`, `invitaciones`, `invitacionRechazada`, `reporteEnRevision`;
  - `marcas` (D54: `{ trabajadorTerminoEn, clienteConfirmoEn, confirmacionSolicitadaEn, avisoEvidenciaEn, realizadoEn, realizadoVia }`) y `fotosTerminado`;
  - `acciones: { puedeCancelar, motivoNoCancelar, puedeEnviarABolsa, puedeInvitarOtro, puedeConfirmar }`.

  La solicitud de otro cliente: 404.
- `POST /api/cliente/solicitudes/:id/bolsa`: 409 `YA_EN_BOLSA`, `SOLICITUD_VENCIDA` o `ESTADO_NO_PERMITIDO`.
- `POST /api/cliente/solicitudes/:id/invitaciones` `{ trabajadorId }`: 409 `INVITACION_NO_PERMITIDA` (ya rechazó o canceló), `MAXIMO_INVITACIONES` o `COLABORADOR_*`.
- `POST /api/cliente/solicitudes/:id/cancelar` `{ motivo? }`: PENDIENTE, o CONFIRMADO con 24 h o más. Si no, 409 `CANCELACION_NO_DISPONIBLE` o `NO_CANCELABLE`.
- `POST /api/cliente/solicitudes/:id/confirmar`: solo EN_PROCESO. 409 `REPORTE_EN_REVISION` (D57) o `ESTADO_NO_PERMITIDO`.
- `GET /api/cliente/solicitudes/:id/evidencias/:evidenciaId` → `{ url, expiraEnSegundos }`: foto de «terminado», con URL temporal.
- `GET /api/cliente/trabajadores?servicioId=&fecha=`: con la fecha, además sin traslapes (60 min de traslado).
- «Mis inmuebles»:
  - `GET /api/cliente/inmuebles` → `{ inmuebles: [{ id, nombre, tipo, direccion, habitaciones, banos, mediosBanos, pisos, actualizadoEn }] }`;
  - `POST /api/cliente/inmuebles` `{ nombre (1–100), tipo, direccion (5–255), habitaciones (0–20), banos (0–20), mediosBanos (0–20), pisos (1–10) }` → 201;
  - `PATCH /api/cliente/inmuebles/:id`: edición parcial;
  - `DELETE /api/cliente/inmuebles/:id`: archivar.

  El de otro cliente o uno archivado: 404.
- Avisos:
  - `GET /api/cliente/notificaciones` → `{ noLeidas, notificaciones: [{ id, solicitudId, tipo, titulo, mensaje, leida, fecha }] }`;
  - `POST /api/cliente/notificaciones/:id/leida`;
  - `POST /api/cliente/notificaciones/leidas`.

**Trabajador** (`Authorization: Bearer`)
- `GET /api/trabajador/solicitudes/disponibles` → `{ verificado, solicitudes: [vista] }`: sus invitaciones pendientes y la bolsa en la que es elegible, con hora futura.
- `GET /api/trabajador/solicitudes` (Fase 3b, se amplía con la vista) y `GET /api/trabajador/solicitudes/:id`. La vista trae:
  - `relacion` (`ASIGNADO`, `INVITADO` o `BOLSA`);
  - `direccion`: **solo si está asignado**;
  - `cliente: { nombre }`, `gananciaEstimada` (informativa), `ventanaInicio`;
  - `acciones: { puedeAceptar, puedeRechazar, puedeIniciar, motivoNoIniciar, puedeTerminar, puedeCancelar, motivoNoCancelar }`.
- `POST /api/trabajador/solicitudes/:id/aceptar`: 409 `SOLICITUD_YA_TOMADA`, `SOLICITUD_VENCIDA` o `NO_ELEGIBLE_*`; 404 `SOLICITUD_NO_DISPONIBLE`.
- `POST /api/trabajador/solicitudes/:id/rechazar`: definitivo. Si era invitación, avisa al cliente.
- `POST /api/trabajador/solicitudes/:id/cancelar` `{ motivo? }`: CONFIRMADO con 24 h o más. Vuelve a la bolsa.
- `POST /api/trabajador/solicitudes/:id/iniciar`: de 30 min antes a 30 min después de la hora. 409 `ANTES_DE_LA_VENTANA`, `DESPUES_DE_LA_VENTANA`, `OTRO_SERVICIO_EN_CURSO` o `TRASLAPE`.
- `POST /api/trabajador/solicitudes/:id/terminar`:
  - multipart, campo `fotos` (de 1 a 5; JPEG, PNG o WebP; 8 MB cada una y 16 MB en total);
  - errores: 400 `FOTOS_REQUERIDAS`, `DEMASIADAS_FOTOS`; 413; 409 `YA_TERMINADO`.
- `GET /api/trabajador/solicitudes/:id/evidencias/:evidenciaId`.
- Avisos: `GET /api/trabajador/notificaciones`, `POST /notificaciones/:id/leida` y `POST /notificaciones/leidas`.

**Admin** (cookie + Origin)
- `GET /api/admin/solicitudes`:
  - **Permiso:** `SUPERVISAR_SOLICITUDES`, o ser el propietario (implícito).
  - **Filtros:** `?estado=&modo=INVITACION|BOLSA&desde=&hasta=&q=&atencion=1&pagina=&tamano=(≤100)`.
  - **Respuesta:** `{ total, pagina, tamano, actualizadoEn, solicitudes: [{ id, estado, modo, servicio, direccion, fechaProgramada, finEstimado, creadaEn, precio, cliente, trabajador, invitaciones: { pendientes, rechazadas }, reportesActivos, alertas }] }`.
  - **`alertas`:** `REPORTE_ACTIVO`, `SIN_INICIAR` (más de 30 min tarde), `ESPERANDO_CONFIRMACION`, `POR_VENCER` (menos de 2 h).
- `GET /api/admin/solicitudes/:id` → `{ solicitud }` con:
  - el snapshot, `trabajadores` (invitaciones y bolsa), `historial` (con `actorNombre`), `marcas`, `fotosTerminado`;
  - `reportes`: con el contenido **solo** si el admin tiene `GESTIONAR_INCIDENCIAS_FINANZAS` (X6);
  - `resolucion`, `alertas`, `puedeResolver`.
- `GET /api/admin/solicitudes/:id/evidencias/:evidenciaId`: las fotos de un reporte exigen además el permiso de incidencias.
- `POST /api/admin/solicitudes/:id/resolucion` `{ resultadoServicio: "REALIZADO" | "NO_REALIZADO", motivo (10–500) }` → 201:
  - **Permiso:** `GESTIONAR_INCIDENCIAS_FINANZAS`.
  - Solo sobre una solicitud CONFIRMADO o EN_PROCESO con reportes activos. **Inmutable.**
  - **Errores:** 409 `RESOLUCION_EXISTENTE` (también si dos resuelven a la vez), `SIN_REPORTES_ACTIVOS`, `ESTADO_NO_PERMITIDO`; 400 `RESULTADO_INVALIDO`, `MOTIVO_REQUERIDO`.
- `GET /api/admin/permisos/mios` → `{ permisos, implicitos }`. El propietario incluye `SUPERVISAR_SOLICITUDES` implícito.
- Permisos que el propietario otorga y revoca: `MODERAR_CONTENIDO`, `SUPERVISAR_SOLICITUDES` y `GESTIONAR_INCIDENCIAS_FINANZAS`.
- `POST /api/admin/reportes/:id/resolucion` (moderación): 409 `RESOLUCION_DE_SERVICIO` si la solicitud sigue abierta. Los reportes del panel traen `estadoSolicitud` y `resolverConServicio`.
- **No existen** rutas para asignar, reasignar, confirmar, finalizar ni cancelar solicitudes (D24).

**Rutas obsoletas:** `/galaxias` y `/hoyo-negro` siguen sin existir (404). Ninguna app las usa ya.
