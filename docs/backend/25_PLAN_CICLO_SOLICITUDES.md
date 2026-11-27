# 25 — Fase: ciclo de las solicitudes sin dinero — v2, IMPLEMENTADA y validada en local; parte de la Fase 3 COMPLETADA (2026-11-25, informe `26`)

- **Estado:** autorizada por el usuario el 2026-11-25, **solo para implementarla y probarla en local** (`quelimpiamos_dev` y `quelimpiamos_pruebas`).
- **Prohibido:** producción, TiDB Cloud, secretos y variables de producción, commits y despliegues.
- **Componentes:** backend, app del cliente, app del trabajador y panel web administrativo.
- **Decisiones:** doc `09`, secciones "Siguiente fase…", "Panel web…" y "Autorización de la fase". **Esta v2 prevalece** sobre la v1 y, en lo que contradiga, sobre `11` (se indica en cada punto).

## 1. Qué cubre y qué no
**Cubre:**
- catálogo y cotización;
- **«Mis inmuebles»**;
- crear la solicitud con invitación a un colaborador o en la bolsa;
- aceptar o rechazar;
- después de un rechazo, que el cliente elija qué hacer;
- cancelar sin cargo;
- vencer las solicitudes que nadie aceptó (motivo `VENCIDA`);
- iniciar dentro de la ventana permitida;
- «terminado» con fotos;
- confirmación del cliente;
- confirmación automática (D54);
- bloqueo por reportes (D57);
- resolución administrativa inmutable;
- avisos a cliente y trabajador;
- supervisión en el panel.

**No cubre:**
- pagos, comisiones, liberación de ganancias, cargos, compensaciones, adeudos, descuentos y movimientos financieros;
- tarjeta (D50);
- chat;
- negociación;
- subida de la INE;
- horarios (D17);
- corrección de resoluciones (procedimiento futuro);
- Trabajadores, Clientes, Catálogo e Inicio reales en el panel.

`estado_pago` siempre queda en `PENDIENTE`. No se escribe en `trabajador_movimientos`, `cliente_adeudos`, `descuento_usos` ni `solicitud_resoluciones.resultado_pago`. Los importes de la solicitud (precio, 85/15) son solo una copia informativa, como en la v1.

## 2. Reglas del ciclo
| Paso | Quién | Condición | Efecto | Aviso |
|---|---|---|---|---|
| Cotizar | Cliente | Servicio activo; fecha futura, a 365 días como máximo (igual que la app); extras activos | Precio = base + extras; duración = base + minutos de los extras; fin estimado. **No crea nada.** Se permite con la INE en revisión (D65) | — |
| Crear | Cliente | INE `VERIFICADO` (si no, 403 `IDENTIDAD_NO_VERIFICADA`); lo mismo que al cotizar; inmueble guardado propio y no archivado, o uno nuevo en el formulario | PENDIENTE con **snapshot inmutable**: tipo, medidas, dirección y alias del inmueble; servicio; especialidades (servicio y extras); áreas; extras; precios. Con colaborador elegible: 1 invitación (`MANUAL`); sin colaborador: bolsa (`AUTOMATICA`). Una solicitud idéntica (mismo servicio, fecha y dirección) aún PENDIENTE: 409 `SOLICITUD_DUPLICADA` | Invitado: `INVITACION_NUEVA` |
| Aceptar | Trabajador | Activo y verificado, con las especialidades exigidas, sin traslape con 60 min de traslado, y antes de la hora programada. Transacción pesimista (`11` §4.2) | CONFIRMADO; las demás filas se cierran (`OTRO_TRABAJADOR_ACEPTO`) y también sus otras invitaciones que ahora se traslapan (`TRABAJADOR_OCUPADO`) | Cliente: `SERVICIO_CONFIRMADO` |
| Rechazar | Trabajador | Invitación pendiente, o una solicitud de la bolsa que ve | Su fila queda RECHAZADA (definitiva: no vuelve a verla ni a ser invitado a ella). La solicitud sigue PENDIENTE | Si era invitación, cliente: `INVITACION_RECHAZADA` |
| Tras el rechazo | Cliente | PENDIENTE sin invitaciones pendientes | **Enviar a la bolsa** (`AUTOMATICA`), **invitar a otro** (elegible, nunca uno que ya rechazó o canceló, máx. 5 pendientes) o **cancelar** | Nuevo invitado: `INVITACION_NUEVA` |
| Cancelar (cliente) | Cliente | PENDIENTE, o CONFIRMADO con **24 h o más** de anticipación. Con menos: 409 `CANCELACION_NO_DISPONIBLE` | CANCELADO; las filas abiertas pasan a CERRADA (`CLIENTE_CANCELO`) | Invitados o asignado: `SOLICITUD_CANCELADA_POR_CLIENTE` |
| Cancelar (trabajador) | Trabajador asignado | CONFIRMADO con 24 h o más. Con menos: 409 `CANCELACION_NO_DISPONIBLE` | Su fila queda CANCELADA (`TRABAJADOR_CANCELO`, definitiva); la solicitud vuelve a PENDIENTE en la bolsa, sin trabajador (`11` §4.4) | Cliente: `SOLICITUD_DEVUELTA_A_BOLSA` |
| **Vencer** | Sistema | PENDIENTE al llegar su hora programada | CANCELADO por `SISTEMA` (historial: «Vencida: ningún trabajador la aceptó»). Las filas PENDIENTE pasan a CERRADA con **`motivo_cierre = VENCIDA`** (nuevo, SQL 004). Sin cargos | Cliente: `SERVICIO_CANCELADO_POR_PLATAFORMA` |
| **Iniciar** | Trabajador asignado | CONFIRMADO. **Desde 30 min antes hasta 30 min después** de la hora programada. Activo y verificado, sin otro servicio en curso sin marcar terminado y sin traslape (60 min) entre [ahora, ahora + duración] y sus otros servicios pendientes de terminar | EN_PROCESO | — |
| Sin iniciar | — | CONFIRMADO, más de 30 min después de la hora | Sigue CONFIRMADO. **Alerta** en «requieren atención» del panel. El cliente puede reportar `INASISTENCIA` | — |
| Terminar | Trabajador asignado | EN_PROCESO y aún no marcado; **1 a 5 fotos** (JPEG, PNG o WebP; 8 MB cada una, 16 MB en total; tipo real; sin GPS) | `trabajador_marco_realizado_en`; fotos en `evidencias_solicitud` (`aportada_por = TRABAJADOR`, sin `reporte_id`) | — |
| Confirmar | Cliente | EN_PROCESO, sin reportes activos (si los hay: 409 `REPORTE_EN_REVISION`) | REALIZADO (`CLIENTE`, `cliente_marco_realizado_en`) | — |
| D54 con evidencia | Sistema | Marcado por el trabajador, sin la confirmación del cliente, sin reportes activos | Al llegar max(T + 30 min, marca): aviso (`aviso_evidencia_en`). **15 min** después: REALIZADO (`EVIDENCIA_TRABAJADOR`) | Cliente: `AVISO_CONFIRMACION_CON_EVIDENCIA` |
| D54 sin marcas | Sistema | EN_PROCESO sin marcas ni reportes activos | En T + 30 min: se pide confirmar (`confirmacion_solicitada_en`). **30 min** después, si sigue sin marcas: REALIZADO (`AUTOMATICO`) | Cliente: `CONFIRMAR_SERVICIO_REALIZADO`; trabajador: `SUBIR_EVIDENCIA_SERVICIO`; al confirmarse, ambos: `SERVICIO_CONFIRMADO_AUTOMATICAMENTE` |
| Bloqueo D57 | — | Un reporte activo (no RESUELTO y no eliminado) | La tarea no avanza esa solicitud | — |
| **Resolución** | Admin con `GESTIONAR_INCIDENCIAS_FINANZAS` | Solicitud CONFIRMADO o EN_PROCESO con al menos un reporte activo; motivo obligatorio (10–500) | Ver §4 | Ambos: `REPORTE_RESUELTO` |

- **T** = `fecha_hora_fin_estimada`. Todas las fechas van en UTC (X8).
- **Cada cambio de estado** es un `UPDATE` condicional (`WHERE estado = …`) en una transacción, con su fila en `solicitud_historial`.
- **Avisos:** con `clave_evento` (D60), así que repetir una operación o la tarea no duplica nada.
- **La tarea periódica** corre cada minuto dentro del servidor y es idempotente.
- **Tipos de aviso:** todos los que usa la fase ya existen en la BD.

## 3. «Mis inmuebles» (decisión del 2026-11-25)
- **El cliente puede:**
  - guardar **tantos inmuebles como quiera**, cada uno con su **nombre** (`alias`, obligatorio, de 1 a 100 caracteres);
  - consultarlos, editarlos y eliminarlos;
  - elegir uno al crear una solicitud, o capturar uno nuevo sin guardarlo (`inmueble_id = NULL`). También puede guardarlo en ese momento con un nombre.
- **Eliminar = archivar** (`archivado_en`, `11` §4.6): desaparece de su lista y ya no se puede elegir. La fila no se borra porque `fk_sol_inmueble` es `ON DELETE RESTRICT` y protege las solicitudes que la usaron.
- **Copia inmutable:** cada solicitud copia tipo, habitaciones, baños, medios baños, pisos, dirección y **alias** (columna nueva `inmueble_alias_aplicado`, SQL 004). Ninguna ruta modifica esas columnas, así que editar o archivar el inmueble no cambia nada de las solicitudes anteriores (con prueba automática).
- **Validación**, igual que la app:
  - tipo: CASA, OFICINA o DEPARTAMENTO;
  - dirección: de 5 a 255 caracteres;
  - habitaciones, baños y medios baños: de 0 a 20;
  - pisos: de 1 a 10 (la BD exige `pisos >= 1`).
- Un cliente solo ve y usa **sus** inmuebles: si no es suyo, 404.

## 4. Resolución administrativa (decisiones del 2026-11-25; prevalece sobre `11` §0.10)
- **Una sola resolución de servicio por solicitud, inmutable.** No hay ninguna ruta para editarla, borrarla ni sustituirla. La BD lo garantiza con un UNIQUE sobre una columna generada (SQL 004). La regla anterior de `11` ("si el admin cambia de criterio, registra otra resolución") **queda sustituida**: la rectificación será un procedimiento futuro aparte, que conserve la original y registre la corrección, el motivo y la auditoría. **No se implementa en esta fase.**
- **Efecto, en una transacción** con la fila de la solicitud bloqueada (`FOR UPDATE`):
  - se crea la fila en `solicitud_resoluciones` con `admin_id`, el `admin_permiso_id` vigente de incidencias, `resultado_servicio` y el motivo. `resultado_pago` queda vacío;
  - `REALIZADO` → REALIZADO (`RESOLUCION_ADMIN`). `NO_REALIZADO` → CANCELADO;
  - los reportes activos pasan a RESUELTO con su `resolucion_id`, y cada uno deja un evento `RESOLVER` en `moderacion_eventos`;
  - historial con actor `ADMIN`.
- **Concurrencia:** la primera gana. La segunda recibe **409 `RESOLUCION_EXISTENTE`**. El UNIQUE de la BD es la última barrera: P2002 → 409. Nada se sobrescribe y la auditoría queda íntegra (prueba con dos admins a la vez).
- **Moderación:**
  - los reportes de una solicitud **sin cerrar** (PENDIENTE, CONFIRMADO o EN_PROCESO) ya no se resuelven con `POST /api/admin/reportes/:id/resolucion`: responde 409 `RESOLUCION_DE_SERVICIO`;
  - los de solicitudes cerradas se siguen moderando igual que hoy;
  - eliminar un reporte lo deja de contar (X5, sin cambios).

## 5. Permisos del panel (separados)
| Permiso | Para qué | Quién lo tiene |
|---|---|---|
| `SUPERVISAR_SOLICITUDES` (nuevo, SQL 004) | Ver la lista, el detalle y las fotos de las solicitudes | **El propietario automáticamente** (quien tenga `ADMINISTRAR_PERMISOS` vigente), sin una fila propia. A los demás se lo otorga el propietario |
| `GESTIONAR_INCIDENCIAS_FINANZAS` | Resolver el servicio (y, en la fase de dinero, los pagos) | Lo otorga el propietario a otros admins. Que el propietario lo tenga sigue siendo D63b (abierta) |
| `MODERAR_CONTENIDO` | Reseñas y reportes (sin cambios, salvo §4) | Igual que hoy |
| `ADMINISTRAR_PERMISOS` | Ser propietario: otorgar y revocar | Asignación inicial por script |

- Nadie se otorga un permiso a sí mismo (CHECK en la BD).
- `GET /api/admin/permisos/mios` devuelve los permisos **efectivos**, con `SUPERVISAR_SOLICITUDES` implícito para el propietario.
- **Para resolver desde el panel** hay que poder ver el detalle (supervisar) y tener el permiso de incidencias. El backend valida cada permiso por separado.
- **Reportes en el detalle de la solicitud** (X6: el contenido completo solo lo ven el autor y los admins autorizados):
  - con solo `SUPERVISAR_SOLICITUDES` se ve un **resumen**: tipo, estado, si reportó el cliente o el trabajador, y la fecha;
  - la descripción y las fotos del reporte, solo con `GESTIONAR_INCIDENCIAS_FINANZAS` (hace falta para resolver) o desde la página de Reportes con `MODERAR_CONTENIDO`, como hoy.
- **El admin no puede** asignar, reasignar, confirmar, finalizar ni cancelar solicitudes ordinarias (D24): no existe ninguna ruta para hacerlo y el panel quita esos botones.

## 6. Base de datos — SQL 004 (solo en las BD locales)
Archivo `docs/backend/sql/004_ciclo_solicitudes.sql`, con su `004_rollback.sql`:

1. `admin_permisos.permiso`: se añade el valor `SUPERVISAR_SOLICITUDES` **al final** del ENUM. Los valores existentes no cambian.
2. `solicitud_trabajadores.motivo_cierre`: se añade `VENCIDA` al final.
3. `solicitudes`: columna nueva `inmueble_alias_aplicado VARCHAR(100) NULL`. Las filas existentes quedan en NULL: no se rellenan ni se alteran.
4. `solicitud_resoluciones`: columna generada `servicio_resuelto_solicitud_id` (= `solicitud_id` si `resultado_servicio` no es NULL) con UNIQUE `uq_res_una_de_servicio`.

**Cómo se prueba y aplica:**
- **Ensayo** en `quelimpiamos_pruebas`, que se reconstruye con 000 + 002 + 003 v2 + 004. Comprueba:
  - los valores y la columna nuevos;
  - que se puedan insertar los valores anteriores;
  - el UNIQUE (dos resoluciones de servicio → error; una de servicio y otra solo de pago → permitido, para la fase de dinero);
  - el rollback.
- **En `quelimpiamos_dev`** (con datos): primero **respaldo lógico** (`backend/backups/`, ignorado por git) y conteo de filas por tabla. Después se aplica y se comprueba que las filas y sus valores sean **idénticos** (huella de datos por tabla).
- **Prisma:** se actualiza `schema.prisma` y se regenera con `prisma generate` (`generated/` nunca se edita a mano).
- **En producción** iría después del 002 y del 003 v2, solo con otra autorización.

## 7. Trabajo por componente
### 7.1 Backend
**Dominio** (`src/dominio/`):
- `ciclo-solicitudes.ts`: cotización, creación, transiciones y reglas;
- `inmuebles.ts`;
- `elegibilidad.ts`: elegibles y traslapes;
- `notificaciones.ts`: crear con `clave_evento`, listar y marcar como leídas;
- `tarea-ciclo.ts`: vencimiento y D54, cada minuto; se arranca desde `server.ts` y `servidor:local`, y no se ejecuta durante las pruebas;
- `resoluciones.ts`;
- `supervision.ts`: consultas del admin.

**Rutas del cliente** (`/api/cliente`):
- `GET /catalogo`;
- `POST /cotizaciones`;
- `GET|POST /inmuebles`, `PATCH|DELETE /inmuebles/:id`;
- `GET /trabajadores?servicioId=&fecha=`: la ruta ya existe; se añade el filtro de traslapes;
- `POST /solicitudes`;
- `GET /solicitudes` (se amplía con estado, invitación y acciones permitidas) y `GET /solicitudes/:id`;
- `POST /solicitudes/:id/bolsa`, `/invitaciones`, `/cancelar` y `/confirmar`;
- `GET /solicitudes/:id/evidencias/:evidenciaId`: URL temporal de las fotos del trabajador;
- `GET /notificaciones`, `POST /notificaciones/:id/leida` y `POST /notificaciones/leidas`.

**Rutas del trabajador** (`/api/trabajador`):
- `GET /solicitudes/disponibles`;
- `POST /solicitudes/:id/aceptar`, `/rechazar`, `/cancelar`, `/iniciar` y `/terminar` (multipart);
- `GET /solicitudes` (se amplía) y `GET /solicitudes/:id`;
- `GET /solicitudes/:id/evidencias/:evidenciaId`;
- las mismas tres rutas de notificaciones que el cliente.

**Rutas del admin** (`/api/admin`):
- `GET /solicitudes`: filtros por estado, modo, fechas, búsqueda y `atencion=1`; paginación;
- `GET /solicitudes/:id`;
- `GET /solicitudes/:id/evidencias/:evidenciaId`;
- `POST /solicitudes/:id/resolucion`;
- `PERMISOS_OTORGABLES` añade `SUPERVISAR_SOLICITUDES` y `GESTIONAR_INCIDENCIAS_FINANZAS`;
- moderación según §4.

**Pruebas:**
- **Contrato:** `06_CONTRATOS_API.md` con cada ruta.
- **Rechazos:** cada transición y cada rechazo (400, 403, 404 y 409).
- **Concurrencia:** aceptación simultánea, resolución simultánea y doble ejecución de la tarea.
- **Plazos y fotos:** los de D54 con el reloj del dominio; fotos válidas y no válidas.
- **Inmuebles:** snapshots que no cambian.
- **Permisos:** que estén separados y que el propietario tenga el implícito.
- **Sin dinero:** que no se escriba nada en las tablas de dinero.
- **Rutas obsoletas:** que no existan.

### 7.2 Panel web
- **Lista** de solicitudes reales con filtros (estado, modo, fechas, búsqueda) y «requieren atención»:
  - reporte activo;
  - CONFIRMADO sin iniciar 30 min después de su hora;
  - EN_PROCESO esperando confirmación;
  - PENDIENTE a menos de 2 h de vencer.
- **Detalle:**
  - cliente;
  - snapshot del servicio y del inmueble;
  - precio informativo;
  - modo;
  - invitaciones o bolsa, con el estado, el motivo y la fecha de cada trabajador;
  - línea de tiempo del historial;
  - marcas de D54;
  - fotos (URL temporal);
  - reportes y resolución.
- **Actualización:** cada **20 s, solo con la página visible**; botón «Actualizar» y «actualizado hace…».
- **Botones:** **se quitan** asignar, cambiar, confirmar, finalizar y cancelar, con su lógica local.
- **Resolver:** con confirmación y motivo, solo con los dos permisos. Muestra el 409 si otro admin resolvió antes.
- **Menú y páginas** según los permisos efectivos. La página de permisos otorga los nuevos.
- **Reportes:** «Resolver» se desactiva, con explicación, si la solicitud no está cerrada.
- Trabajadores, Clientes, Catálogo e Inicio **siguen con datos de demostración**, con su insignia (Fase 5).

### 7.3 App del cliente
- **Mis inmuebles:** lista, crear, editar y eliminar, desde el perfil y al pedir.
- **Pedir:** catálogo y cotización del servidor (precio único) y colaboradores elegibles para la fecha. **Pago solo en efectivo:** la tarjeta queda «no disponible» (D50). Crea con la ruta nueva y avisa si falta la INE.
- **Historial y detalle:** estados reales; acciones después de un rechazo; cancelar; «Confirmar que se realizó» viendo las fotos; actualización **cada 15 s** en el detalle.
- **Avisos:** con las notificaciones reales.
- **Chat:** oculto en las solicitudes reales.
- **Rutas obsoletas:** se borra `SolicitudApi` (`/galaxias`, `/hoyo-negro`).

### 7.4 App del trabajador
- **Disponibles:** bolsa e invitaciones con las rutas nuevas, **cada 3 s**; aceptar y rechazar sin propuestas ni contraofertas.
- **Mis trabajos:** iniciar (con el motivo si está fuera de la ventana), «Marcar terminado» con 1 a 5 fotos y cancelar.
- **Avisos:** con las notificaciones reales.
- **Chat:** oculto en las reales.
- **Datos simulados:** «Restablecer demostración» se conserva; las solicitudes reales y las simuladas se distinguen.
- **`RequestsApi`:** se borran las rutas obsoletas.

### 7.5 Datos locales (`datos:local`, idempotente; solo `quelimpiamos_dev`)
- **Cliente ficticio:** `estado_verificacion = VERIFICADO`.
- **Cuentas nuevas:**
  - **propietario de prueba**: el correo que indicó el usuario (D63a), rol ADMIN, con la asignación inicial (`ADMINISTRAR_PERMISOS` y `MODERAR_CONTENIDO`, plantilla del 003 v2);
  - **2 admins ficticios** (`.test`): reciben permisos del propietario **por el backend**, con auditoría, durante las pruebas;
  - **un 2.º trabajador ficticio**, activo y verificado.
- **Contraseñas:** solo en `backend/.local/cuentas-prueba-local.json` (ignorado por git). Nunca en producción.

## 8. Orden y controles
| Etapa | Qué | Control |
|---|---|---|
| 1 | Este plan y el doc `09` | Sin contradicciones con las decisiones |
| 2 | SQL 004: ensayo en `quelimpiamos_pruebas` | Ensayo en verde; las 133 pruebas del backend siguen pasando |
| 3 | SQL 004 en `quelimpiamos_dev` | Respaldo previo; huella de datos sin cambios |
| 4 | Backend | Typecheck y `npm test` en verde, con las pruebas nuevas |
| 5 | Panel | `tsc` y build en verde; lint sin errores nuevos (hoy hay 13); navegador contra el backend local |
| 6 | App del cliente | `analyze`, `flutter test` y APK debug |
| 7 | App del trabajador | Lo mismo. `app_state_test` ya fallaba: se informa, no se oculta |
| 8 | Pruebas integrales de los cuatro componentes (lista del usuario) | Por la API y la IP de la Wi-Fi desde la PC, y el panel en el navegador |
| 9 | Seguridad, permisos, datos históricos y documentación | Informe final |

## 9. Riesgos
- **Tamaño:** muchos cambios en cuatro componentes. Por eso los controles de cada etapa.
- **Datos simulados:** la app del trabajador mezcla solicitudes reales y simuladas.
- **ENUM con columna generada:** `admin_permisos.permiso` alimenta `permiso_activo`. Si TiDB no deja cambiar el ENUM con esa dependencia, el 004 tendrá que quitar y recrear la columna generada. Se verá en el ensayo, antes de tocar `quelimpiamos_dev`.

## 10. Resultado de la implementación (2026-11-25) — solo local; sin commits, despliegues ni producción
| Etapa | Resultado |
|---|---|
| 1. Plan | v2 con las decisiones del usuario; `09` "Autorización de la fase" |
| 2. SQL 004 en `quelimpiamos_pruebas` | `npm run bd:ensayo-004`: **19/19 OK**. Hallazgo: TiDB no deja cambiar el ENUM `permiso` porque de él depende la columna generada `permiso_activo` (error 3108); el 004 la quita y la vuelve a crear igual, con su UNIQUE. Rollback probado (los valores nuevos de los ENUM se quedan: TiDB no permite quitarlos) |
| 3. SQL 004 en `quelimpiamos_dev` | `npm run bd:local -- migrar`: respaldo previo en `backend/backups/2026-11-25T23-17-52-551Z-quelimpiamos_dev-antes-de-migrar/`, 9 sentencias. Huella idéntica de las 39 tablas y 74 filas. Segunda ejecución: «sin migraciones pendientes». Prisma regenerado con `prisma:local` |
| 4. Backend | Typecheck 0 errores. **`npm test` 166/166**: 133 anteriores (2 adaptadas a la regla nueva de moderación, ver abajo) + 33 nuevas (`test/ciclo-solicitudes.test.ts`) |
| 5. Panel | `tsc -b` 0, build OK, lint **13 errores, los mismos de antes** (ninguno nuevo). Revisión visual en el navegador con sesión: **OK** (§11) |
| 6. App del cliente | `analyze` sin issues; `flutter test` **29/29** (22 + 7 nuevas); APK debug OK con `API_URL=http://192.168.0.78:3000` |
| 7. App del trabajador | `analyze`: **72 info, los mismos de siempre** (0 errores y 0 advertencias); `flutter test` **24 OK + 1 que ya fallaba** (`app_state_test` «Flujo completo…»: espera `null` de `acceptOpportunity`, que ya era asíncrono; no se modificó); APK debug OK |
| 8. Integrales | Por la API y la IP de la Wi-Fi contra `quelimpiamos_dev`, con el servidor local real y su tarea periódica: todo OK (detalle en `24` §7) |
| 9. Revisión | 72 de las 74 filas previas idénticas; las 2 distintas son cambios explicados (cliente ficticio VERIFICADO; contraseña del trabajador de prueba 1 restablecida). 0 filas de dinero |

**Cambio de regla en 2 pruebas existentes** (decisión del usuario, §4):
- `reportes.test.ts` «seguimiento, edición… cada una deja SU evento» y «un reporte ACTIVO bloquea…» resolvían por moderación reportes de solicitudes EN_PROCESO.
- Ahora comprueban primero el 409 `RESOLUCION_DE_SERVICIO`. Después verifican lo mismo de antes por la vía válida: moderación de una solicitud ya cerrada, o resolución del servicio con el permiso de incidencias.

**Archivos nuevos:**
- **BD:** `docs/backend/sql/004_ciclo_solicitudes.sql` y `004_rollback.sql`.
- **Backend:**
  - `src/dominio/`: `ciclo-solicitudes.ts` (catálogo, cotización, creación, elegibilidad y traslapes, transiciones, vistas), `inmuebles.ts`, `notificaciones.ts`, `tarea-ciclo.ts`, `resoluciones.ts`, `supervision.ts`;
  - rutas: `src/modules/cliente/inmuebles/routes.ts`, `src/modules/cliente/notificaciones/routes.ts`, `src/modules/admin/solicitudes/routes.ts`;
  - scripts: `src/scripts/ensayo-004.ts`, `src/scripts/lib/entorno-bd-pruebas.ts`;
  - pruebas: `test/ciclo-solicitudes.test.ts`.
- **Panel:** `src/data/solicitudesAdmin.ts`, `src/hooks/useActualizacionPeriodica.ts`, `src/utils/fechasDeSolicitudes.ts`, `src/pages/PermisosPage.tsx`.
- **App del cliente:** `lib/services/ciclo_api.dart`, `lib/screens/solicitud_detalle_screen.dart`, `lib/screens/mis_inmuebles_screen.dart`, `test/ciclo_solicitudes_test.dart`.
- **App del trabajador:** `test/ciclo_solicitudes_test.dart`.

**Archivos modificados:**
- **Backend:**
  - `prisma/schema.prisma` (y `generated/` con `prisma generate`), `package.json` (`bd:ensayo-004`);
  - `src/server.ts`, `src/dominio/permisos.ts`, `moderacion.ts`, `reportes.ts` (bloquea la solicitud al reportar) y `solicitudes.ts`;
  - rutas de cliente, trabajador, admin y permisos;
  - `src/scripts/bd-local.ts`, `lib/bd-local.ts`, `servidor-local.ts`, `datos-prueba-local.ts`;
  - `test/reportes.test.ts`.
- **Panel:**
  - `SolicitudesProvider.tsx`, `SolicitudesContext.tsx`, `PermisosProvider.tsx`, `permisos.ts`, `reportes.ts`, `tipos.ts`;
  - `SolicitudesPage.tsx`, `DashboardPage.tsx`, `ReportesPage.tsx`, `MenuLateral.tsx`;
  - `components/solicitudes/` (los 3) y `utils/reglasDeSolicitudes.ts` (se quitaron las reglas de asignar, confirmar, finalizar y cancelar).
- **App del cliente:**
  - `api_client.dart` (DELETE), `solicitud_api.dart`, `historial_api.dart`;
  - `service_request_data.dart`, `service_details_screen.dart`, `service_request_screen.dart`;
  - `cotizacion_screen.dart`, `collaborators_screen.dart`, `collaborator_profile_screen.dart`, `pago_screen.dart`, `quote_screen.dart`;
  - `historial_screen.dart`, `avisos_screen.dart`, `profile_screen.dart`, `widgets/flow_widgets.dart`.
- **App del trabajador:** `requests_api.dart` (reescrito con las rutas nuevas), `app_state.dart`, `resenas_reportes_api.dart`, `request_actions.dart`, `widgets/request_card.dart`.

## 11. Pendientes reales
- ~~El panel en el navegador~~: **revisado** con la sesión del propietario de prueba, que inició el usuario (2026-11-25). Funcionó:
  - menú con «Solicitudes» (permiso implícito) y «Permisos»;
  - lista real con actualización cada 20 s y el filtro «requieren atención», que mostró la S3 con «reporte activo» y «sin iniciar»;
  - detalle completo; reportes en resumen sin el permiso de incidencias, con la explicación de por qué no se puede resolver;
  - resolución inmutable de la solicitud 12;
  - «Registrar resolución» deshabilitado en Reportes con la solicitud abierta;
  - otorgar y revocar un permiso desde la página de Permisos, con motivo.

  Se corrigió un texto: «Actualizado sin actualizar» ahora dice «Cargando…».
- ~~Las APK en el teléfono~~: **validadas por el usuario** en su teléfono (2026-11-25). Las dos apps funcionan: navegación y funciones sin problemas.
- **D54 en vivo:** confirmación automática y por evidencia. Tarda horas (fin estimado + 30/15/30 min); se verificó con las pruebas automáticas y el reloj controlado. El servidor real sí canceló en vivo una solicitud vencida.
- **Rendimiento:** el historial del cliente consulta el detalle de cada solicitud, una por una (hasta 200). Basta para pruebas; conviene agruparlo antes de producción.
- **Producción:** el SQL 004 debe ir después del 002 y del 003 v2, con una ventana sin escrituras en `admin_permisos`, y requiere otra autorización.
