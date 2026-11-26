# 20 — Especificación definitiva: reseñas, reportes, moderación y auditoría (Fase 3a)

- **Versión 3 · fecha:** 2026-11-25. **Todas las decisiones están resueltas** (X0–X8 y D63a; §10). Reemplaza a las v1 y v2.
- **Estado:**
  - **implementado y probado en el backend** contra la BD LOCAL (TiDB 8.5.3 en Docker, doc `22`);
  - **conectado en el panel** y verificado en el navegador;
  - apps Flutter con el cliente HTTP listo, sin pantallas (Fase 3b).

  Detalle en §11.
- **Producción no tiene todavía el 002 ni el 003 v2**: nada de esto funciona allí hasta que se autorice aplicar las migraciones (doc `21` §9).
- Leyenda: **Implementado** (el código existe) · **Probado** (hay prueba automática que pasa) · **Integrado** (funciona con su consumidor real).

## 1. Reseñas — reglas
| # | Regla | Dónde se aplica |
|---|---|---|
| R1 | Bidireccionales, al estilo Uber: el cliente califica al trabajador y el trabajador al cliente | `dominio/resenas.ts` (`autor_rol`) |
| R2 | Calificación obligatoria, entera, de 1 a 5 | Backend (400 `PUNTUACION_INVALIDA`) + CHECK `chk_resena_puntuacion` |
| R3 | Comentario opcional, **máximo 500 caracteres** (X1) | Backend (400 `COMENTARIO_LARGO`); la columna es `TEXT` |
| R4 | Sin fotografías | Backend: campo de foto → 400 `FOTOS_NO_PERMITIDAS`; multipart → 415 |
| R5 | Solo con la solicitud en `REALIZADO` | Backend (409 `SERVICIO_NO_FINALIZADO`) |
| R6 | Una por autor y solicitud; como máximo dos por solicitud | UNIQUE `(solicitud_id, autor_rol)` → 409 `RESENA_DUPLICADA` |
| R7 | Opcionales: no bloquean pagos, cierres ni nuevas solicitudes | El módulo no toca ninguna otra tabla (probado) |
| R8 | Se publican de inmediato | Probado: visible antes de que califique la otra parte |
| R9 | Plazo de **168 horas exactas** desde que la solicitud pasa a `REALIZADO` (X7, X8) | Backend contra `solicitudes.realizado_en` (UTC); 409 `PLAZO_VENCIDO` |
| R10 | El usuario no edita ni elimina sus reseñas | No existen rutas `PATCH`/`DELETE` para usuarios (probado: 404) |
| R11 | Cada usuario ve en su historial las que escribió | `GET /api/{cliente,trabajador}/resenas` |
| R12 | Nunca se revela el autor a clientes ni a trabajadores | DTO público sin autor, id, servicio ni fecha exacta (probado) |
| X4 | Una reseña **eliminada lógicamente sigue ocupando su lugar único**: no se puede volver a calificar ese servicio con ese rol | El UNIQUE incluye las eliminadas (probado) |

## 2. Privacidad y visibilidad
| # | Regla |
|---|---|
| V1–V2 | Reseña pública = `{ puntuacion, comentario, mes, anio }` (mes y año en UTC). Sin servicio, sin fecha exacta, sin id. |
| V3 | Perfil del trabajador: promedio y cantidad (`GET /api/cliente/trabajadores/:id/reputacion` y `/resenas`). |
| V4 | Selección manual: estrellas de varios trabajadores (`GET /api/cliente/trabajadores/reputacion?ids=…`). |
| V5 | Reputación del cliente: solo el trabajador **asignado** a una solicitud de ese cliente o **invitado** con invitación vigente (`PENDIENTE` o `ACEPTADA`), y los administradores con `MODERAR_CONTENIDO`. Otro trabajador → 403. |
| V6 / **X0** | El autor **nunca** llega a clientes ni a trabajadores. Solo el admin con `MODERAR_CONTENIDO` lo ve, en la moderación del panel. Un admin sin el permiso recibe **403** en `GET /api/admin/resenas`. |

Promedio = `AVG` y `COUNT` de las reseñas **válidas** (no eliminadas); la corregida cuenta con su valor nuevo. Sin reseñas: `promedio: null` (nunca 0 estrellas).

## 3. Reportes
| # | Regla | Dónde |
|---|---|---|
| P1 | El cliente reporta al trabajador y el trabajador al cliente | `dominio/reportes.ts` |
| P2 | Antes de que termine el servicio, **desde la hora programada** (D57) | 409 `REPORTE_ANTES_DE_HORA` antes de esa hora |
| P3 | Independiente de las reseñas | Probado |
| P4 | Ligado a una solicitud; se guardan explícitamente reportante y reportado | `reportado_cliente_id` / `reportado_trabajador_id` + CHECK `chk_rep_partes` |
| P5 | Descripción y fotos opcionales | `tipo` también es opcional: por defecto `OTRO` (la columna del 002 es obligatoria) |
| P6 | Fotos: máx. **5**, **8 MB** cada una, **16 MB** en total; **1 MB = 1 000 000 bytes** (X3) | multer (cantidad y tamaño mientras se recibe) + `validarFotos` (total) |
| X2 | Formatos: **JPEG, PNG y WebP**, según el **contenido real** (bytes mágicos); la extensión y el tipo declarado deben coincidir; se quita GPS/EXIF | `shared/almacenamiento` (415 `TIPO_NO_PERMITIDO`, `EXTENSION_NO_COINCIDE`, `TIPO_NO_COINCIDE`) |
| X6 | El reporte completo solo lo ven **quien lo creó** y los admins con `MODERAR_CONTENIDO`. El reportado no tiene ninguna ruta para verlo ni para saber quién fue (404) | Probado |
| X5 | Un reporte **eliminado lógicamente deja de bloquear** la confirmación automática; uno activo (no `RESUELTO` y no eliminado) sigue bloqueando (D57) | `bloqueaConfirmacionAutomatica()` (probado) |
| D59/D61 | `PAGO_EN_DISPUTA`: solo el trabajador y solo dentro de `solicitudes.reporte_pago_hasta` | 400 / 409 `PLAZO_REPORTE_PAGO_VENCIDO` |

Las fotos se guardan en el almacenamiento local privado (doc `16`). La BD guarda la clave, el MIME, el tamaño y el sha256. Se descargan solo con una URL temporal de 5 minutos, que se entrega después de autorizar.

## 4. Moderación (panel, `MODERAR_CONTENIDO`)
- **Reseñas:**
  - consultar todas, con autor y calificado;
  - filtrar;
  - corregir calificación y/o comentario (p. ej. 1 → 5 estrellas);
  - eliminar (lógico).
- **Reportes:**
  - consultar reportante, reportado, descripción y fotos;
  - poner en revisión o volver a abierto;
  - agregar notas de seguimiento;
  - editar tipo y descripción;
  - retirar una foto (lógico);
  - registrar la resolución (`RESUELTO`);
  - eliminar (lógico).
- **Toda** acción exige motivo y deja un evento de auditoría en la misma transacción.
- La eliminación siempre es **lógica**: no se borra ningún registro original.
- Un `PAGO_EN_DISPUTA` **no** se resuelve por moderación (409 `RESOLUCION_FINANCIERA`): es el flujo financiero de D62, Fase 5.

## 5. Auditoría (`moderacion_eventos`)
- Cada evento guarda:
  - el admin;
  - el permiso con el que actuó;
  - la fecha (UTC);
  - la operación;
  - `datos_anteriores` y `datos_nuevos` (JSON);
  - el **motivo obligatorio**.
- Cubre reseñas, reportes **y permisos** (otorgar, revocar y asignación inicial).
- El primer evento de cada objeto conserva su versión original.
- **Protección** (TiDB no tiene triggers):
  1. solo `dominio/auditoria.ts` escribe, y solo con `create`, vigilado por `test/auditoria-estatica.test.ts`;
  2. no hay rutas para editar ni borrar eventos (404);
  3. CHECK de la BD: motivo no vacío, objetivo único, actor coherente, operación válida por entidad y JSON objeto;
  4. FK RESTRICT: no se borra físicamente nada que tenga historial;
  5. en producción, una cuenta de BD con permisos por tabla (doc `21` §6; requiere tu acción en la consola de TiDB Cloud).

## 6. Permiso `MODERAR_CONTENIDO` y propietario (D63, D63a)
- El **propietario** (`ADMINISTRAR_PERMISOS`) otorga y revoca `MODERAR_CONTENIDO` a otros admins activos.
- Nadie se lo otorga a sí mismo (CHECK de la BD y backend).
- El propietario tampoco puede revocarse el suyo (no podría recuperarlo).
- Cada otorgamiento y revocación queda en `admin_permisos` y en `moderacion_eventos`.
- **D63a — decidida (2026-11-25):** la cuenta propietaria es la del correo que indicó el usuario (`sa***@gmail.com`; el correo completo no se publica en el repositorio).
- **Resultado de la asignación inicial: NO realizada.**
  - Esa cuenta **no existe** en la BD local: se construye solo con la estructura, sin filas.
  - Tampoco existe en producción: según la inspección de solo lectura del 2026-11-25, producción tiene una sola cuenta, el admin id 1 con correo de demostración.
  - No se crearon usuarios ni se cambiaron roles.
  - Mecanismo listo: `npm run permisos:asignar-propietario -- --correo <correo>` (BD local) y la plantilla SQL revisada para producción (doc `21` §5).
  - **Falta:** que esa cuenta exista como ADMIN.

## 7. Modelo de datos (SQL 003 v2, aplicado SOLO en la BD local)
Detalle en `21`. Resumen:
- `resenas` reconstruida (`autor_rol`, `cliente_id` y `trabajador_id` con FK compuestas a la solicitud, `puntuacion` 1–5, `comentario TEXT`, `editada_en`, borrado lógico);
- `solicitud_reportes` y `evidencias_solicitud` (del 002) reutilizadas y extendidas;
- `admin_permisos` con propietario y `origen`;
- `moderacion_eventos` nueva.

## 8. Endpoints implementados
| Audiencia | Ruta | Autorización |
|---|---|---|
| Cliente | `POST /api/cliente/solicitudes/:id/resena` · `GET /api/cliente/resenas` | Token de cliente; ser el cliente de la solicitud |
| Cliente | `GET /api/cliente/trabajadores/:id/resenas` · `/:id/reputacion` · `/trabajadores/reputacion?ids=` | Token de cliente; respuestas anónimas |
| Cliente | `POST /api/cliente/solicitudes/:id/reportes` (multipart o JSON) · `GET /api/cliente/reportes[/:id]` · `GET /api/cliente/reportes/:id/evidencias/:evidenciaId` | Token; ser el cliente de la solicitud; solo sus propios reportes |
| Trabajador | `POST /api/trabajador/solicitudes/:id/resena` · `GET /api/trabajador/resenas` · `GET /api/trabajador/resenas/recibidas` | Token de trabajador; ser el trabajador asignado |
| Trabajador | `GET /api/trabajador/solicitudes/:id/reputacion-cliente` | Asignado o invitado vigente (V5) |
| Trabajador | `POST /api/trabajador/solicitudes/:id/reportes` · `GET /api/trabajador/reportes[/:id]` · `…/evidencias/:evidenciaId` | Igual que el cliente |
| Admin | `GET /api/admin/resenas` · `PATCH`/`DELETE /api/admin/resenas/:id` | Cookie de admin + **`MODERAR_CONTENIDO`** (403 sin él); motivo obligatorio |
| Admin | `GET /api/admin/reportes[/:id]` · `PATCH /api/admin/reportes/:id` · `POST …/:id/estado` · `POST …/:id/seguimiento` · `POST …/:id/resolucion` · `DELETE …/:id` · `DELETE …/:id/fotos/:fotoId` | Igual |
| Admin | `GET /api/admin/moderacion/eventos?entidad=&id=` | `MODERAR_CONTENIDO`; los eventos de permisos, solo el propietario |
| Admin | `GET /api/admin/permisos/mios` | Cualquier admin |
| Admin | `GET /api/admin/permisos` · `POST /api/admin/permisos` · `POST /api/admin/permisos/:id/revocar` | **`ADMINISTRAR_PERMISOS`** (propietario) |

**Fase 3b (solo lectura, doc `23` §1):**
- `GET /api/cliente/solicitudes`;
- `GET /api/trabajador/solicitudes`;
- `GET /api/cliente/trabajadores` (solo trabajadores activos y verificados).

La identidad, el rol y los permisos salen **siempre** de la sesión, nunca del cuerpo.

## 9. Pruebas (todas pasan: `npm test`, 123/123)
`test/resenas.test.ts` (21), `test/reportes.test.ts` (19), `test/moderacion.test.ts` (14) y `test/auditoria-estatica.test.ts` (4) cubren cada punto de las secciones 1 a 6. La lista está en `08`.

## 10. Decisiones (todas resueltas el 2026-11-25)
| Clave | Decisión |
|---|---|
| X0 | El admin con `MODERAR_CONTENIDO` ve al autor; clientes y trabajadores nunca. Sin el permiso: 403 en `GET /api/admin/resenas` |
| X1 | Comentario de máximo 500 caracteres |
| X2 | Fotos de reportes: JPEG, PNG y WebP |
| X3 | 1 MB = 1 000 000 bytes |
| X4 | La reseña eliminada sigue ocupando su lugar único: no se puede volver a calificar |
| X5 | Un reporte eliminado deja de bloquear la confirmación automática |
| X6 | El reporte completo solo lo ven su autor y los admins autorizados; el reportado no lo ve ni sabe quién fue |
| X7 | Los 7 días empiezan exactamente cuando la solicitud pasa a `REALIZADO` |
| X8 | Fechas en UTC; plazo de 168 horas exactas |
| D63a | Propietario: la cuenta con el correo indicado por el usuario (enmascarado aquí). Asignación pendiente porque esa cuenta todavía no existe |

## 11. Estado por pieza
| Pieza | Implementado | Probado | Integrado |
|---|---|---|---|
| SQL 003 v2 (esquema) | Sí | Aplicado y probado en el TiDB **local** (168 sentencias, los CHECK verificados) | **No** en producción (sin autorización) |
| Backend: reseñas, reportes, evidencias, moderación, permisos, auditoría | Sí | Sí: 58 pruebas nuevas, 123/123 en total | Con el panel: sí |
| Panel: Reseñas (moderación) y Reportes (página nueva) | Sí | `tsc` 0 errores y build OK. En el navegador, contra la demo local: corregir, poner en revisión, resolver; foto por URL temporal; sin permiso → mensaje y 403 | **Sí** (backend local) |
| Apps Flutter (Fase 3b, doc `23`): historial real, calificar, reportar con fotos, mis reseñas y reportes, reputación | Sí | `analyze` sin errores; pruebas nuevas OK (cliente 22/22, trabajador 18 nuevas); **APK debug OK en las dos** | Con el backend: sí, por los endpoints reales. **No probado en un dispositivo** |
| Confirmación automática (tarea periódica, Fase 4) | Solo la regla `bloqueaConfirmacionAutomatica()` | Sí | La tarea no existe todavía |
| Asignación inicial al propietario | Mecanismo sí | Sí (con cuentas de prueba) | **Pendiente:** la cuenta no existe |
