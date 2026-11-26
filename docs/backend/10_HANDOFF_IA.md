# 10 — Handoff para la siguiente IA

- **Fecha:** 2026-11-25 · **Fases terminadas:** 1 (fundación) y 2 (auth por audiencia, **cerrada**: backend 65/65, panel original compila e integra la auth, apps Flutter verificadas por el usuario). **Siguiente:** que el usuario revise `20` (reseñas y reportes) y el SQL 003 v2; después, la Fase 3. **La Fase 3 no ha empezado.**

## Al retomar — Pruebas en el teléfono (2026-11-25, doc `24`)
- **Fase 3b validada manualmente** en el teléfono por el usuario (2026-11-25), con las dos APK: satisfactoria. No modificar lo que ya funciona.
- **Fase 3 (3a, 3b y ciclo sin dinero): COMPLETADA** (2026-11-25, aprobada por el usuario; informe `26`).
- **No empezar la siguiente fase** sin la aprobación del usuario.
- **Pasan a fases posteriores:** el perfil del cliente, el dinero y los documentos e INE.
- **No tocar** el reporte abierto de la S3.
  Decisiones: `09`, sección "Autorización de la fase".
- **SQL 004:** solo en las BD locales (`npm run bd:ensayo-004`, `npm run bd:local -- migrar`). En producción, después del 002 y del 003 v2, con otra autorización.
- **Cuentas de prueba:** `datos:local` crea el propietario de prueba (correo de D63a), admin1, admin2 y trabajador2; las credenciales están en `backend/.local/`. `--restablecer-claves=<clave>` restablece solo esa cuenta.
- **Servidor local:** si se detiene con TaskStop, verificar que no quede un proceso `node` hijo escuchando en el puerto 3000 (pasó el 2026-11-25).
- **Base de datos:** solo `quelimpiamos_dev` local.
- **Comandos** (en `backend`):
  - `npm run bd:local -- iniciar`;
  - `npm run datos:local` (idempotente; no crea solicitudes);
  - `npm run servidor:local` (escucha solo en `127.0.0.1` y en la IP privada de la Wi-Fi).
- **Credenciales ficticias:** en `backend/.local/cuentas-prueba-local.json`.
- **APK:** recompiladas con `--dart-define=API_URL=http://192.168.0.78:3000`. Si la IP cambia, se recompila.
- **Firewall:** regla "Que Limpiamos backend local (pruebas)", TCP 3000, perfil Privado, solo la subred local. Se quita al terminar (doc `24` §6).
- **Bloqueo:** las apps aún crean solicitudes con `/galaxias` y `/hoyo-negro` (404).
- **Mientras tanto:** `npm run solicitudes:local` crea 3 solicitudes ficticias (ids 1, 2 y 3; idempotente; doc `24` §5). Su plazo para calificar vence el 2026-12-01.

## Al retomar — Fase 3b implementada (2026-11-25). Lo más reciente primero
- **Flutter:** `C:\Users\lolil\flutter\bin\flutter.bat` (no está en el `PATH`). Las dos apps: `analyze` limpio, pruebas nuevas OK y `build apk --debug` OK.
- **Apps:**
  - historial, calificar, reportar y "mis reseñas/reportes" usan la API real (doc `23`);
  - el historial **local** del trabajador y el modo demo siguen como estaban;
  - la **creación** de solicitudes sigue con las rutas obsoletas (siguiente fase).
- **Docker en Windows:** si no arranca, borra los 3 sockets viejos (doc `22` §4) y luego `npm run bd:local -- iniciar`.

## Al retomar — Fase 3a implementada (2026-11-25, noche). Lo más reciente primero
- **BD:** todo corre contra el **TiDB LOCAL** (doc `22`):
  - arranca con `npm run bd:local -- iniciar`;
  - el esquema es 000 + 002 + 003 v2;
  - **no toques el clúster remoto**: ni producción ni `queLimpiamos_proyecto`;
  - los scripts `*-002`/`*-003` antiguos apuntan al clúster: **no los ejecutes**.
- **Schema Prisma:** se genera con `npm run prisma:local`. Ya no coincide con producción.
- **Fase 3a:** reseñas, reportes, evidencias, moderación, `MODERAR_CONTENIDO` y auditoría están implementados y probados (123/123). Especificación final en `20` (sin pendientes); SQL en `21` §10.
- **Panel:**
  - las páginas Reseñas y Reportes están conectadas;
  - los permisos salen de `/api/admin/permisos/mios`;
  - el backend responde 403 sin el permiso.
- **Apps:** solo `lib/services/resenas_reportes_api.dart`. Las pantallas van en la Fase 3b, junto con el historial de solicitudes.
- **Propietario (D63a):** la cuenta no existe. **No crees usuarios ni cambies roles.** Cuando exista: `npm run permisos:asignar-propietario -- --correo <correo>` (local) o la plantilla SQL (producción, con autorización).
- **Confirmación automática:** la tarea de la Fase 4 debe usar `bloqueaConfirmacionAutomatica()` (`dominio/reportes.ts`).
- **Auditoría:** nunca escribas en `moderacion_eventos` fuera de `dominio/auditoria.ts`; la prueba estática falla si lo haces.

## Al retomar (2026-11-25, tarde) — preparación de la Fase 3a
- **Panel local:** `appWeb/.env.local` ya apunta a `http://localhost:3000`. `appWeb/.env` apunta al backend desplegado: **no lo toques**. El backend local se levanta con `npm run demo:local` (`npm run dev` necesita `JWT_SECRET_*`).
- **Reseñas y reportes:** especificación v2 en `20`; SQL 003 v2, rollback y plantilla en `21` y `sql/003_v2_*`. **Nada ejecutado.** No uses la BD compartida para ensayarlo: el usuario pidió un entorno local aislado (`21` §8).
- **X0 resuelta:** el admin con `MODERAR_CONTENIDO` ve al autor; clientes y trabajadores nunca. Ya no bloquea. Siguen abiertas X1–X8 (`20` §10).
- **Ningún permiso asignado.** La plantilla del propietario espera D63a y no admite el ID 1 por suposición.

## Al retomar (2026-11-25) — lo más reciente primero
- **Panel** (`limpiandotuhogar/appWeb`): compila (`npx tsc -p tsconfig.app.json --noEmit` → 0 errores; `npm run build` OK). Detalle de los 22 errores resueltos, las acciones sin endpoint y la prueba en el navegador: `18`.
  - Trabaja con **`SolicitudListado`** en todas partes. El detalle usa `SolicitudDetalle`, cuyos campos extra son opcionales hasta el endpoint de detalle (Fase 5).
  - Asignar, confirmar, finalizar y cancelar desde el detalle **se conservaron** (el usuario pidió no quitar funciones) y responden "no conectada". **D24** dice que el admin no interviene: lo decide el equipo, no tú.
  - `SolicitudesProvider` solo se monta en `DashboardPage`; no lo vuelvas a poner en `main.tsx`, porque pediría datos sin sesión.
  - Para probarlo con la demo: `$env:VITE_API_URL = "http://localhost:3000"; npm run dev`. Los `.env` locales del equipo tienen un valor que no llega al backend; **no leas su valor** (regla de `.env`).
- **Reseñas:** `ResenasPage` reactivada; estructura en `data/resenas.ts`, `ResenasContext.ts` y `ResenasProvider.tsx`, con el interruptor `RESENAS_CONECTADAS_AL_BACKEND = false`. **No agregues datos de ejemplo.** La especificación completa (reglas decididas, diseño propuesto y preguntas Q1–Q8) está en **`20`**. La implementación es de la **Fase 3a**, no antes.
  - La tabla actual `resenas` **no cumple** la especificación (UNIQUE por solicitud, una sola dirección): el cambio de schema va en el SQL 003 v2 y **requiere autorización**.
- **Reglas vigentes:**
  - no modificar producción;
  - no aplicar el SQL 002 ni el 003, ni ejecutar el 003 v2 sin autorización;
  - no alterar respaldos;
  - **no asignar permisos de propietario, y ningún permiso a la cuenta demo ID 1**;
  - sin commits ni despliegues;
  - no leer valores de `.env`;
  - no tocar `generated/` a mano.
- **Demo y pruebas:** `npm run demo:local` usa `queLimpiamos_proyecto`. Si se detiene a la fuerza, ejecuta `npm run demo:limpiar` (debe decir 0 tablas) antes de `npm test`.
- **Avisos al cerrar procesos en Windows:** `TaskStop` puede dejar vivos a los hijos (Vite, `demo-local`). Revisa los puertos 3000 y 5173 y detén solo los procesos cuya línea de comandos sea `vite` o `demo-local`.

## Lee primero
1. `08_ESTADO_IMPLEMENTACION.md` — qué está hecho y verificado.
2. `09_DECISIONES_PENDIENTES.md` — respuestas del usuario y lo que sigue abierto.
3. `04_ARQUITECTURA_BACKEND.md` — estructura y reglas.
4. `01_COMPARACION_PROYECTOS.md` §5 — tabla de equivalencias (nombres provisionales prohibidos).
5. `02_MAPA_SCHEMA_REAL.md` — schema real y máquina de estados.

## Rutas
- Backend de trabajo: `que-limpiamos-3/limpiandotuhogar/backend` (escribible).
- Fuente de verdad: `Que-Limpiamos/backend/prisma/schema.prisma` (**solo lectura**).
- Consumidores a actualizar: `que-limpiamos-3/limpiandotuhogar/apps/app_contratador_diseno_que_limpiamos/app_contratador/lib/services/` (cliente), `.../apps/app_trabajador/lib/services/` (trabajador), `.../appWeb/src/data/` (panel).

## Estado
- Backend arranca con `npm run dev`; solo expone `/health` y `/health/db`.
- Schema local = schema real + `trabajadores.password_hash` (única diferencia, D1). Cliente Prisma regenerado.
- Rutas provisionales eliminadas → las apps Flutter están rotas hasta las Fases 2–4 (aceptado por el usuario).
- Nada commiteado: los cambios están en el working tree de `que-limpiamos-3`.

## Decisiones ya tomadas
- D1: `trabajadores.password_hash` (nullable) **ya existe** en la BD real y en el schema local. El login de trabajador está desbloqueado. `DATABASE_URL` ya corregido y verificado (apunta a `queLimpiamos`).
- D2: el trabajador acepta trabajos (detalle de estados pendiente).
- D4: precio fijo calculado en servidor según pisos/cuartos/baños/medios baños; fórmula pendiente → no inventar montos.
- D11, D12: hechas.

## Siguiente paso concreto (Fase 2)
1. Resolver D8 (hash) y añadir `jsonwebtoken`, `cookie-parser` (+ tipos).
2. `shared/auth/jwt.ts` (aud/iss/sub, secreto por audiencia) y `shared/auth/password.ts`; ampliar `config/env.ts` con `JWT_SECRET_CLIENTE/TRABAJADOR/ADMIN`.
3. Módulo cliente: registro, login, me. Módulo admin: login/session/logout con cookie (alias `/api/auth/admin/*` para el panel, D7).
4. Módulo trabajador: login/me (el admin asigna la contraseña inicial; `password_hash` puede ser NULL → login rechazado).
5. Pruebas de aislamiento de tokens entre audiencias.
6. Actualizar `AuthApi` en ambas apps Flutter (rutas nuevas, guardar token, enviar `Authorization: Bearer`, quitar `rol` del signup).

## Actualización 2026-11-24 (tarde)
- Motor real: **TiDB Cloud Serverless v8.5.3** (no MariaDB). Ver `11_PROPUESTA_CAMBIOS_SCHEMA.md` §4.7.
- SQL 002 v2 **propuesto y NO ejecutado**; el usuario lo revisará antes. No ejecutar sin autorización explícita.
- Antes de ejecutar: seguir `12_RESPALDO_Y_RECUPERACION.md` §3 (verificar → respaldo → ensayo opcional → ejecutar → verificar → actualizar Prisma con `sql/002_schema_prisma_previsto.prisma`).
- Decisiones nuevas: zona `America/Cancun`; máx. 5 invitaciones (configurable; falta confirmar si cuentan las pendientes o el total, D20b); sin pagos por ahora; el cliente cancela solo en PENDIENTE/CONFIRMADO. Pendiente: D24 (estados en que cancela el admin).

## Actualización v3 (2026-11-24)
- SQL 002 **v3** propuesto, NO ejecutado. Leer `11_PROPUESTA_CAMBIOS_SCHEMA.md` (§1 decisiones, §4 reglas de negocio, §8 pendientes).
- **El admin NO interviene entre cliente y trabajador**: no implementar asignación, cancelación ni gestión de invitaciones en `/api/admin`. El admin aprueba documentos, ve el dashboard, administra el catálogo y los descuentos, y archiva trabajadores (supuesto D28).
- Los trabajadores se registran solos (`/api/trabajador/auth/registro`) y no son elegibles hasta `estado_verificacion = VERIFICADO`. Nunca borrar trabajadores: se archivan.

## Actualización v4 (2026-11-24)
- SQL 002 **v4** propuesto, NO ejecutado. Fuente: `11_PROPUESTA_CAMBIOS_SCHEMA.md` (§4 reglas, §8 pendientes).
- Reglas críticas del backend: bloquear la fila del trabajador (`SELECT … FOR UPDATE`) al aceptar trabajos (encimados) y al escribir en `trabajador_movimientos`. El libro es inmutable: solo INSERT; las correcciones con `AJUSTE`.
- Los `updated_at` existentes ya se actualizan en la BD; no quitar `ON UPDATE` en ningún script.

## Actualización v5 (2026-11-24)
- SQL 002 **v5**: ver `11_PROPUESTA_CAMBIOS_SCHEMA.md`. NO se ha aplicado en ninguna BD.
- El ensayo (`npm run db:ensayo-002`) quedó **bloqueado** porque el usuario de la BD no puede crear bases. Opciones en `12_RESPALDO_Y_RECUPERACION.md` §6. No usar `queLimpiamos_shadow` sin autorización explícita del usuario; **nunca** tocar `PIXAN`.
- Tras un ensayo OK, aplicar en producción solo con autorización explícita, siguiendo `12` §3.

## Actualización v6 (2026-11-24)
- SQL 002 **v6** ENSAYADO OK (29/29) en `queLimpiamos_proyecto`. **No** aplicado en producción: falta la autorización explícita del usuario.
- Para repetir el ensayo: `ENSAYO_DATABASE_NAME=queLimpiamos_proyecto npx tsx src/scripts/ensayo-002.ts` (exige la BD vacía y la deja vacía). Nunca tocar `PIXAN`.
- Producción tiene `CHECK (pisos >= 1)` en `inmuebles` (Prisma no lo muestra): validar en el backend.
- Después de aplicarlo en producción:
  1. Copiar `docs/backend/sql/002_schema_prisma_previsto.prisma` a `prisma/schema.prisma` (ajustando el comentario de cabecera).
  2. Correr `prisma generate` y `typecheck`.
  3. Empezar la Fase 2 (auth).

## Actualización 2026-11-24 (verificación previa a la Fase 3) — leer primero
- **No empezar la Fase 3** hasta cerrar:
  - las apps Flutter (`19`; bloqueado: sin Flutter SDK);
  - la compilación del panel (`18`; bloqueado: necesita autorización del equipo);
  - el SQL 003 v2 (necesita OK);
  - la cuenta del propietario (D63a, `09`).
- D66 y D67 decididas (`09`).
- Secretos: en producción nunca se generan (servidor, firma de archivos y demo); está probado en `test/config.test.ts`.

## Actualización 2026-11-24 (corrección de D5)
- **D5 v2:** almacenamiento LOCAL privado (`src/shared/almacenamiento`), sin proveedores externos ni dependencias de nube. Interfaz lista para S3 (`16` §4). Las URLs temporales firmadas las sirve `/api/archivos/temporal/:token`.
- **Límite de intentos** implementado (`shared/auth/intentos.ts`, `shared/http/limites.ts`). En las pruebas, el reloj se simula con `reloj.ahora`.
- **Auth integrada:** panel (probado en el navegador) y dos apps Flutter (**sin compilar**: no hay Flutter SDK).
- El panel commiteado **no compila** por `ResenasPage` (equipo): no tocarlo sin consultar.
- **Demo local:** `npm run demo:local` / `npm run demo:limpiar` (`17`). Deja `queLimpiamos_proyecto` vacía al terminar; si no, `npm test` y los ensayos se niegan a correr.
- **Siguiente:** SQL 003 v2 (necesita el OK del usuario al diseño de `13` §7), compilar las apps cuando haya Flutter, y después los pasos 3, 5 y 6 de `15` §0.

## Actualización 2026-11-24 (cierre)
- Decididas D5, D63–D65 y el límite de intentos (`09`). **Siguiente:** el orden de `15` §0. El paso 0 lo hace el usuario (JWT, BD `queLimpiamos_dev`, D5a, D63a); después, paso 1 (límite de intentos) y paso 2 (SQL 003 v2: `13` §7 + `16` §5).
- Diseño de almacenamiento: `16`. Integración de las apps y el panel: `14` §4. Límite de intentos: `14` §5.
- **No** aplicar 002/003 en producción, **no** commit y **no** empezar la Fase 3 sin el OK del usuario al plan v2 (`15`) y a `16`.

## Estado al 2026-11-24 (noche)
- **SQL 002 v10** (43/43) y **SQL 003 v1** (23/23): ensayados, **NO aplicados**. El orden es 002 → 003, solo con autorización explícita (`12` §3 y §3b).
- **Fase 2:** implementada y probada (29/29). Integración con las apps pendiente (`14`).
- **Fase 3:** solo plan (`15`). Requisitos: R1 (aplicar 002 + 003, o trabajar con el schema previsto solo en la BD de pruebas), R2 (secretos JWT), R4 (almacenamiento, D5) y R5 (rate limiting).
- Decisiones abiertas: D63, D64, D65 (`15` §5) y D5. D60–D62 cerradas (`09`).
- Reglas nuevas para el código que use el 003:
  - toda notificación lleva `clave_evento` (`<TIPO>:<entidad>:<id>`) y P2002 significa "ya avisado";
  - el pago presumido guarda `reporte_pago_hasta`;
  - la resolución de admin exige el permiso vigente (consulta en `13` §4, con `FOR UPDATE`) y el admin de la sesión, nunca del body.

## Fase 2 — Auth por audiencia (2026-11-24) — IMPLEMENTADA y probada (29/29), sin commit
- Contrato: `06_CONTRATOS_API.md`. Estructura: `04` ("Agregado en la Fase 2").
- Funciona con el schema **actual** (sin el SQL 002): solo usa `usuarios` y `trabajadores`.
- **Para arrancar el servidor** hay que agregar al `.env` `JWT_SECRET_CLIENTE`, `JWT_SECRET_TRABAJADOR` y `JWT_SECRET_ADMIN`: distintos y de 32+ caracteres (comando en `.env.example`). Hoy el `.env` no los tiene, así que `npm run dev` se detiene con "Falta la variable de entorno JWT_SECRET_CLIENTE". Los scripts de BD (`db:*`) no los necesitan.
- **Pruebas:** `npm test`.
  - Usan la BD `queLimpiamos_proyecto` (o `PRUEBAS_DATABASE_NAME`), que debe estar **vacía**.
  - Crean las tablas de producción sin datos, las borran al final y comprueban que producción no cambió.
  - Para pruebas nuevas, copiar el patrón de `test/auth.test.ts` (primer import: `./soporte/entorno`).
- Reglas para las Fases 3–5:
  - proteger cada ruta con su guard;
  - el actor sale de `clienteActual(res)`, `trabajadorActual(res)` o `adminActual(res)`, **nunca** del body;
  - toda salida pasa por un DTO, sin `password_hash`;
  - las rutas de admin que cambian datos ya pasan por `exigirOrigenPermitido`.
- Cuando se aplique el SQL 002:
  - `requireTrabajador` debe bloquear la baja administrativa;
  - `requireCliente` y el registro de cliente pueden apoyarse en el CHECK de teléfono, que ya validan.
- Pendiente antes del deploy:
  - rate limiting de los logins (D10, Fase 6);
  - actualizar `AuthApi` en las dos apps Flutter y el cierre de sesión del panel (ver `06`).
- D59 en el backend: D60–D62 en `09` (nada de eso está implementado todavía; D62 depende de este `requireAdmin`).

## Actualización v10 (2026-11-24) — vigente (prevalece sobre la v9)
- SQL 002 **v10** = v9 + tipo de notificación del trabajador `PAGO_EFECTIVO_PRESUMIDO` + reglas de D59 documentadas en el SQL. Siguen siendo **84** objetos (el tipo nuevo está en una tabla nueva). NO aplicado en producción. Resultado del ensayo en `12` §6.
- Reglas del backend (D59, detalle en `11` §0.10):
  - endpoints «Ya pagué en efectivo» (cliente) y «Ya recibí el efectivo» (trabajador): los dos llaman a la misma función, que registra el pago y la comisión una sola vez;
  - la tarea periódica, al confirmar automáticamente, presume el pago (`SISTEMA`) **solo** si la solicitud estaba EN_PROCESO y no tiene reportes sin resolver. Va en la misma transacción y notifica `PAGO_EFECTIVO_PRESUMIDO`. El SQL exacto está en `11` §0.10;
  - el trabajador puede reportar `PAGO_EN_DISPUTA` también después de la confirmación automática.
- Ya no quedan decisiones abiertas sobre el 002.

## Actualización v9 (2026-11-24) — prevalece sobre la v8
- SQL 002 **v9** (ver el resultado del ensayo en `12` §6). NO aplicado en producción: falta la autorización del usuario. `db:verificar-002` cuenta **84** objetos.
- Reglas del backend que añade la v9 (detalle en `11` §0.10):
  - **Cuatro estados independientes:** servicio (`solicitudes.estado`), pago (`estado_pago`), reporte (`solicitud_reportes.estado`) y resolución (`solicitud_resoluciones`). Nunca deducir uno de otro.
  - **Registrar el pago en efectivo:** `UPDATE … WHERE estado_pago = 'PENDIENTE'`. Si cambió la fila, en la misma transacción se registran `COMISION_EFECTIVO` y, si hay adeudos, **un** `COBRO_ADEUDO_CLIENTE` con el total. No espera a "terminado". La app del trabajador muestra la advertencia de `11` §0.10.
  - **Tarea periódica:** no confirma ni libera la ganancia si hay reportes sin RESOLVER (`NOT EXISTS`). Crear un reporte bloquea la fila de la solicitud (`SELECT … FOR UPDATE`).
  - **Resolución del admin:** fila nueva e inmutable, reportes a RESUELTO, ejes aplicados y movimientos con `resolucion_id`. Las correcciones son `AJUSTE`, que siempre lleva `movimiento_relacionado_id`, y solo puede haber uno por movimiento.
  - **Compensación:** `DIAS_ESPERA_PAGO_ADEUDO = 0`, así que la plataforma la libera en la misma transacción de la cancelación tardía.
  - **Reportes:** se aceptan desde `fecha_hora_programada`. Conectar el botón "Reportar" existente de la app del cliente (`historial_screen.dart`) y crear el equivalente en la app del trabajador.
- Renombres respecto de la v8: `pago_liberado_en` → `ganancia_liberada_en`, `clave_unica_liberacion` → `clave_unica_referencia` (`uq_mov_una_vez_por_movimiento`) y `chk_mov_liberacion_con_origen` → `chk_mov_referencia_obligatoria`. Se quitó `efectivo_recibido_en`.
- Pendiente D59: quién registra el pago en efectivo.

## Actualización v8 (2026-11-24) — prevalece sobre la v7
- SQL 002 **v8** (ver resultado del ensayo en `12` §6). NO aplicado en producción: falta la autorización del usuario. `db:verificar-002` cuenta **78** objetos.
- Reglas del backend que añade la v8 (detalle en `11` §0.9):
  - **pagos dobles:** la BD ya los impide (`uq_mov_una_vez_por_solicitud`, `uq_mov_una_liberacion`, `chk_mov_liberacion_con_origen`). Aun así, el backend escribe `pago_liberado_en` y `compensacion_liberada_en` con `UPDATE … WHERE … IS NULL` en la misma transacción que los movimientos, y trata P2002 como "ya estaba hecho";
  - cada mitad de un par `LIBERACION_SALDO` lleva `movimiento_relacionado_id` = el movimiento que libera;
  - confirmación del servicio con plazos (parámetros 30 / 15 / 30 min) → hace falta una **tarea periódica** (cada minuto) en la Fase 4;
  - la compensación la paga la plataforma tras `DIAS_ESPERA_PAGO_ADEUDO` días si el cliente no pagó;
  - identidad: HMAC-SHA256 del CURP normalizado con `IDENTIDAD_HMAC_SECRETO` (solo el nombre de la variable va en `.env.example`); el CURP cifrado va fuera de la BD; al terminar la revisión se borran las fotos de la INE (`archivo_eliminado_en`) y el backend ya no devuelve `archivo_url`;
  - la evidencia del trabajador usa la tabla existente `evidencias_solicitud`.
- Las columnas generadas `clave_unica_solicitud` y `clave_unica_liberacion` llevan `@ignore`: nunca escribirlas.
- TiDB no permite un CHECK sobre una columna con FK (error 3823, aunque sea RESTRICT): por eso el CHECK usa la columna generada.

## Actualización v7 (2026-11-24)
- SQL 002 **v7** ENSAYADO OK (31/31). NO aplicado en producción: falta la autorización del usuario.
- Reglas del backend que añade la v7 (detalle en `11` §0.8):
  - el backend rechaza `metodo_pago = TARJETA`;
  - REALIZADO exige `efectivo_recibido_en` + las dos marcas;
  - flujo de adeudos PENDIENTE → EN_COBRO → COBRADO;
  - un solo descuento por solicitud, el mayor;
  - el registro de cliente exige teléfono (la BD también lo exige).
