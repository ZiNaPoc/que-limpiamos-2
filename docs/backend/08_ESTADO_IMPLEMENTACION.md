# 08 — Estado de implementación

- **Última actualización:** 2026-11-25 · **Fase 3: COMPLETADA** (aprobada por el usuario; informe `26`).
  - 3a, 3b y el ciclo sin dinero, en local: backend 166/166, app del cliente 29/29, app del trabajador 25/25 (E1 corregido), panel revisado en el navegador y las dos APK validadas por el usuario en su teléfono.
  - Producción sin cambios.
  - La siguiente fase **no ha empezado**: espera la aprobación del usuario. La Fase 3b quedó validada manualmente por el usuario. Producción sin cambios. Ver "Fase 3b" y doc `23`.
- *(Línea anterior, del 2026-11-24: "2 terminada y verificada (29/29 pruebas)", de antes del límite de intentos y la integración.)*

| Fase | Estado | Verificado | Notas |
|---|---|---|---|
| 0 — Auditoría | ✅ | Sí | Docs 00–03, 07, 09, 10 |
| 1 — Fundación | ✅ | Sí (typecheck, arranque, health, conexión BD) | Ver abajo |
| 2 — Auth | ✅ | Sí (`npm test` 29/29, typecheck) | Ver "Fase 2 — detalle". Falta: rate limiting (Fase 6) y actualizar las apps |
| 3 — Cliente (3a, 3b y ciclo sin dinero) | ✅ **COMPLETADA** (2026-11-25) | Sí: backend 166/166; app del cliente 29/29; app del trabajador 25/25; panel revisado en el navegador; apps validadas por el usuario en el teléfono | Informe `26`. Perfil, dinero e INE pasan a fases posteriores |
| 4 — Trabajador | ⏸ | — | D1 (ejecución), detalle de D2 |
| 5 — Admin | ⏸ | — | |
| 6 — Transversal | ⏸ | — | D5, D10, D14 |
| 7 — QA/Deploy | ⏸ | — | D13, D16 |

## Fase 1 — detalle

### Archivos modificados
- `backend/prisma/schema.prisma` → reemplazado por copia exacta del schema real (hash SHA-256 idéntico).
- `backend/package.json` → nombre, `engines.node >=24`, scripts `dev`/`start`/`typecheck`/`postinstall`/`prisma:generate`/`db:probar`; `dotenv` declarado; `prisma` y `tsx` movidos a `dependencies`; eliminado el campo `prisma.schema` erróneo.
- `backend/package-lock.json` → sincronizado con `npm install`.
- `backend/tsconfig.json` → alineado con B (`noEmit`, `types: ["node"]`, `include`), conserva `noUncheckedIndexedAccess`.
- `backend/.gitignore` → añade `generated` y `dist`.
- `backend/src/app.ts`, `server.ts`, `config/prisma.ts`, `middleware/error.middleware.ts` → reescritos.

### Archivos creados
- `backend/.env.example`, `src/config/env.ts`, `src/shared/errors/AppError.ts`, `src/shared/errors/prismaErrors.ts`, `src/scripts/probar-db.ts`.
- `docs/backend/04_ARQUITECTURA_BACKEND.md`, `docs/backend/sql/001_trabajadores_password_hash.sql` (no ejecutado).

### Archivos eliminados (autorizado: D11, D12)
- `backend/generated/` (regenerado desde el schema real; quitado del índice git con `git rm --cached`).
- `src/controller/` (login, galaxias, hoyo_negro), `src/repositories/` (login, galaxy, hoyo_negro), `src/routes/` (login, galaxias, hoyo_negro), `src/errors/AppError.ts` (movido a `shared/`), `src/test-db.ts` (sustituido por `scripts/probar-db.ts`). Todo recuperable desde git (commit `e818b61`).

### Pruebas
| Prueba | Resultado |
|---|---|
| `npx prisma generate` | OK, 13 modelos reales |
| `npm run typecheck` | OK, 0 errores |
| `npm run db:probar` (SELECT 1) | OK |
| `GET /health` | 200 `{ok:true}` |
| `GET /health/db` | 200 `{ok:true,db:"ok"}` |
| `GET /login`, `GET /hoyo-negro/disponibles` | 404 `RUTA_NO_ENCONTRADA` (rutas viejas retiradas) |
| POST con JSON mal formado | 400 `JSON_INVALIDO` |
| Inspección de solo lectura de la BD | 13 tablas = schema; `trabajadores` sin columna de contraseña; filas: usuarios 1, trabajadores 0, servicios 3, solicitudes 0, horarios 0 |
| `npm audit --omit=dev` | 3 avisos "high" en `effect` (dependencia interna de la CLI de Prisma 7, no del runtime). Sin arreglo compatible: el sugerido baja a Prisma 6. No se actúa |

### Efecto conocido
Las apps Flutter (cliente y trabajador) **no funcionan** contra el backend hasta que se implementen las rutas nuevas (Fases 2–4) y se actualicen sus clientes HTTP. Es consecuencia aceptada de D12.

### Pendiente técnico
- Elegir librería de hash (D8): hoy siguen instaladas `bcrypt` y `bcryptjs`; se resuelve en Fase 2.
- `JWT_*`, `jsonwebtoken`, `cookie-parser`: se añaden en Fase 2.

## Ciclo de las solicitudes sin dinero (2026-11-25, doc `25` v2) — solo BD local · sin commit · sin despliegue · producción sin cambios
| Pieza | Implementado | Probado | Integrado |
|---|---|---|---|
| SQL 004 (permiso `SUPERVISAR_SOLICITUDES`, motivo `VENCIDA`, alias del inmueble en el snapshot, una resolución de servicio por solicitud) | Sí | Ensayo 19/19 en `quelimpiamos_pruebas`; aplicado en `quelimpiamos_dev` con respaldo previo y huella de datos idéntica | Prisma regenerado. **Producción: no** |
| Backend: catálogo, cotización, «Mis inmuebles», crear (invitación o bolsa), aceptar o rechazar, bolsa, cancelar sin cargo, iniciar (ventana de ±30 min), terminar con fotos, confirmar, D54, vencimiento, resolución inmutable, supervisión, avisos | Sí | 33 pruebas nuevas; **166/166** en total; integrales por la IP de la Wi-Fi OK | Con las 2 apps y el panel |
| Panel: solicitudes reales, detalle, «requieren atención», actualización cada 20 s, resolver, página de Permisos, sin botones de intervención | Sí | `tsc` y build OK; lint sin errores nuevos (13 previos) | API probada y **revisado en el navegador con sesión** (propietario de prueba) |
| App del cliente: «Mis inmuebles», cotización del servidor, solo efectivo, colaboradores por fecha, detalle (cada 15 s) con bolsa, invitar, cancelar, confirmar y fotos; avisos reales; sin chat | Sí | `analyze` sin issues; 29/29; APK OK | **Validada por el usuario en su teléfono (2026-11-25)** |
| App del trabajador: disponibles reales (cada 3 s), aceptar o rechazar sin negociación, iniciar, terminar con fotos, cancelar; etiqueta «Solicitud real» o «Demostración»; sin chat en las reales | Sí | `analyze`: 72 info de siempre; **25/25** (E1 de `26` corregido: la prueba ahora espera `acceptOpportunity`); APK OK | **Validada por el usuario en su teléfono (2026-11-25)** |

## Pruebas en el teléfono (2026-11-25, doc `24`) — solo BD local
| Pieza | Implementado | Probado | Integrado |
|---|---|---|---|
| `servidor:local`, `datos:local`, `solicitudes:local` (scripts; sin endpoints ni SQL de esquema; 3 solicitudes ficticias, doc `24` §5) | Sí | Destino verificado; idempotencia comprobada; inicio de sesión y selección manual por la IP de la Wi-Fi desde la PC | APK recompiladas con la IP. Validación manual en el teléfono: **satisfactoria**, informada por el usuario el 2026-11-25 (las dos APK contra el backend local) |

## Fase 3b (2026-11-25) — sin commit · sin despliegue · producción sin cambios
| Pieza | Implementado | Probado | Integrado |
|---|---|---|---|
| Backend: `GET /api/cliente/solicitudes`, `GET /api/trabajador/solicitudes`, `GET /api/cliente/trabajadores` (autorizados; solo lectura; sin SQL) | Sí | 10 pruebas; 133/133 en total | Con las apps: sí |
| App del cliente: historial real, calificar, reportar con fotos, mis reseñas y reportes, avisos, colaboradores con estrellas | Sí | `analyze` sin issues; `flutter test` 22/22; **APK debug OK** | Con el backend real. Validación manual en el teléfono: **satisfactoria**, informada por el usuario el 2026-11-25 (las dos APK contra el backend local) |
| App del trabajador: mis servicios, calificar al cliente, reputación del cliente, reportes, mi reputación | Sí | `analyze`: los 72 info de siempre (0 nuevos); `flutter test`: 18 nuevas OK; **1 prueba del equipo ya fallaba** (`app_state_test`); **APK debug OK** | Con el backend real. Validación manual en el teléfono: **satisfactoria**, informada por el usuario el 2026-11-25 (las dos APK contra el backend local) |

## Fase 3a (2026-11-25) — sin commit · sin despliegue · producción sin cambios
| Pieza | Implementado | Probado | Integrado |
|---|---|---|---|
| BD LOCAL (TiDB 8.5.3 en Docker, doc `22`) con 000 + 002 v10 + 003 v2 | Sí | 168 sentencias aplicadas; los CHECK verificados | Pruebas, demo y desarrollo: **sí**. Producción: **no** (sin autorización) |
| Infraestructura: `DATABASE_TLS` solo para localhost, `bd:local`, `prisma:local`, pruebas y demo LOCALES (ya no tocan el clúster) | Sí | Las 65 pruebas anteriores pasan en local | — |
| Reseñas (`dominio/resenas.ts`, rutas de cliente y trabajador) | Sí | 21 pruebas (`test/resenas.test.ts`) | Panel (moderación): sí. Apps: solo el cliente HTTP |
| Reportes y evidencias (`dominio/reportes.ts`, multipart con multer) | Sí | 19 pruebas (`test/reportes.test.ts`) | Panel: sí. Apps: solo el cliente HTTP |
| Moderación, `MODERAR_CONTENIDO` y auditoría (`dominio/moderacion.ts`, `permisos.ts`, `auditoria.ts`) | Sí | 14 pruebas (`test/moderacion.test.ts`) + 4 estáticas (`test/auditoria-estatica.test.ts`) | Panel: sí, verificado en el navegador |
| Panel: Reseñas (corregir y eliminar), Reportes (página nueva), permisos desde `/permisos/mios` | Sí | `tsc` 0 errores, build OK, navegador contra la demo local | Sí (backend local) |
| Apps: `lib/services/resenas_reportes_api.dart` (cliente y trabajador) | Sí | ~~No compilado~~ → compilado y probado en la 3b | Sí (3b) |
| Asignación inicial al propietario (D63a) | Mecanismo sí | Con cuentas de prueba | **Local:** hecha con la cuenta de prueba del correo de D63a (doc `25`). **Producción:** no realizada (la cuenta no existe) |

- **Pruebas:** `npm test` **123/123** (65 anteriores + 58 de la Fase 3a). Backend typecheck OK. Panel: `tsc` 0, build OK, lint con los 13 errores que ya existían (ninguno nuevo).
- **Lo que cubren:**
  - reglas: 1–5, 500 caracteres, REALIZADO, 168 h, duplicado, el otro rol, publicación inmediata, unicidad tras eliminar, que no bloquee nada;
  - privacidad: el autor no aparece en ninguna respuesta de usuario y la reputación del cliente solo la ve el trabajador invitado o asignado;
  - permisos: 403 sin `MODERAR_CONTENIDO`, el moderador ve al autor, el usuario no edita ni borra, solo el propietario otorga y revoca, sin auto-otorgamiento;
  - reportes: las dos direcciones, antes de finalizar, sin descripción ni fotos, máx. 5, 8 MB, 16 MB, formatos, contenido real, visibilidad, moderación, D57/X5;
  - auditoría: un evento por cambio, antes/después, motivo obligatorio, permisos, sin rutas de edición, CHECK y FK RESTRICT en la BD.
- **Producción:** no se tocó. SQL 002 y 003 v2 **no** aplicados allí. Ninguna BD remota leída ni escrita en esta fase.

## Preparación de la Fase 3a (2026-11-25) — sin commit · la Fase 3a NO empieza
| Pieza | Hecho | Verificado | Pendiente |
|---|---|---|---|
| Panel local → backend local | `appWeb/.env.local` = `http://localhost:3000`; `api.ts` quita las barras finales; `appWeb/.env.example` nuevo | Navegador: peticiones a `:3000` y login 200 con la demo; `tsc` y build OK | `npm run dev` del backend necesita `JWT_SECRET_*` en `backend/.env` (lo hace el usuario); hoy se usa `demo:local` |
| Especificación de reseñas y reportes (`20` v2) | Decisiones del 2026-11-25 incorporadas. **X0 resuelta:** el admin con `MODERAR_CONTENIDO` ve al autor | — | X1–X8 |
| SQL 003 v2 (`21`) + rollback + plantilla del propietario | Preparados | Inspección **solo lectura** de producción y TiDB; revisión estática (sentencias, paréntesis, reversión de cada objeto). **Sin ejecutar en ninguna BD** | Ensayo en un TiDB local, scripts `*-003` al v2, schema Prisma previsto, D64 y documentos, autorización |
| `MODERAR_CONTENIDO` | Mecanismo en el SQL y plantilla bloqueada | — | **D63a**. Ningún permiso asignado a ninguna cuenta (tampoco al ID 1) |

## Cierre de la Fase 2 (2026-11-25) — sin commit · la Fase 3 NO empieza · prevalece sobre las secciones siguientes
| Pieza | Implementado | Probado | Compila | Integrado | Siguiente paso |
|---|---|---|---|---|---|
| **Panel original** (`appWeb`, sin copias temporales) | Sí: 22 errores resueltos (`18` §2) | Sí, en el navegador contra la demo local: login, sesión restaurada, logout, cookie httpOnly, CSRF (`18` §5) | **Sí** (`tsc` 0 errores, `npm run build` OK) | Auth del admin: **sí**. Solicitudes, reseñas, clientes y colaboradores: **no** (sin endpoints) | Fases 3a y 5 |
| `ResenasPage` reactivada + estructura de conexión (`data/resenas.ts`, `ResenasProvider`) | Sí | Compila; vista en el navegador ("pendiente de conexión", **sin datos simulados** y sin peticiones) | Sí | **No**: falta `GET /api/admin/resenas` | Fase 3a (`20` §9) |
| Especificación de reseñas, reportes, moderación y auditoría | Documento `20` (reglas decididas + diseño propuesto + preguntas Q1–Q8) | — | — | — | Tu revisión; SQL dentro del 003 v2 (requiere autorización) |
| Acciones del detalle sin endpoint (asignar, confirmar, finalizar, cancelar) | Diseño conservado; responden "no conectada" | Compila | Sí | No | El equipo decide frente a D24 (`18` §3) |
| Apps Flutter (cliente y trabajador) | Sí | El usuario: `pub get`, `analyze`, `run`, `build apk --debug` OK | Sí (lo informó el usuario) | Compilan y se ejecutan; lista funcional de `19` §4 sin informar punto por punto | — |
| Backend | Sin cambios en este cierre | **65/65** pruebas + typecheck OK (repetidos hoy) | — | — | — |

- **Fase 2: cerrada** en código, compilación y auth integrada (panel probado aquí, apps según lo que informó el usuario). **Abierto y fuera de código:**
  - D63: cuenta del propietario sin confirmar; **ningún permiso asignado**, tampoco a la cuenta demo ID 1;
  - D16: credenciales sin rotar;
  - `VITE_API_URL` en los `.env` locales del panel (`18` §4).
- Producción **no se tocó**. SQL 002, 003 y 003 v2 **no se aplicaron**. La BD de pruebas quedó vacía (0 tablas).

## Verificación previa a la Fase 3 (2026-11-24) — sin commit · la Fase 3 NO empieza
| Pieza | Implementado | Probado | Integrado | Bloqueo / siguiente paso |
|---|---|---|---|---|
| Backend de auth (3 audiencias) + límite de intentos | Sí | Sí | Panel: sí | — |
| Secretos estables (en producción nunca se generan) | Sí: guardas nuevas en la firma de archivos y en la demo | Sí (8 pruebas en procesos aparte) | — | Agregar `JWT_SECRET_*` y `ALMACENAMIENTO_FIRMA_SECRETO` en `.env`/Render |
| Almacenamiento local privado | Sí | Sí (13 pruebas) | **No**: sin endpoints. **No es una función de carga disponible** | Fase 3c / Fase 5 |
| Panel: auth | Sí | Sí, en el navegador (copia de prueba) | Sí | **El panel original no compila**: 22 errores preexistentes + `ResenasPage` (`18`). Necesita autorización del equipo |
| App del cliente: auth | Sí | **No** | **No** | **Sin Flutter SDK aquí**: comandos y lista de verificación en `19` |
| App del trabajador: auth | Sí | **No** | **No** | Igual (`19`) |
| D63 propietario | — | — | — | Candidata: id 1, `ad***@q***********.demo` (cuenta demo; posible contraseña expuesta, D16). **Sin permisos asignados**. Decide el usuario (`09`) |
| D66 / D67 | Decididas y documentadas | — | — | En el SQL 003 v2 (pendiente de OK) |

- `npm test`: **65/65** (15 grupos). `typecheck` OK.
- Producción sin cambios (0/84 y 0/14), BD de pruebas vacía, respaldos 10/10.
- Android: `minSdk = maxOf(flutter.minSdkVersion, 23)` en las dos apps (lo exige `flutter_secure_storage` 10).

## Avance 2026-11-24 (después de la corrección de D5) — sin commit
| Pieza | Implementado | Probado | Integrado |
|---|---|---|---|
| Límite de intentos y bloqueo progresivo | Sí | Sí (6 + 8 pruebas) | Panel: sí (navegador). Apps: implementado, sin compilar |
| Almacenamiento local privado (D5 v2) | Sí | Sí (13 pruebas) | Sin endpoints que lo usen todavía |
| Panel: auth integrada | Sí | Sí, de punta a punta en el navegador | Sí. **Pero el build del panel commiteado falla** por `ResenasPage` (trabajo en curso del equipo, `14` §6) |
| App del cliente: auth integrada | Sí | **No** (sin Flutter SDK) | Pendiente de compilar y probar |
| App del trabajador: auth integrada + dirección + sin contraseña local | Sí | **No** (sin Flutter SDK) | Pendiente |
| Demo local (`demo:local`, `demo:limpiar`) | Sí | Usada en la prueba del panel | Guía `17` |

- `npm test`: **57/57** (12 grupos). `typecheck` OK.
- Producción sin cambios (0/84 y 0/14), BD de pruebas vacía, respaldos 10/10 intactos.
- Dependencias nuevas: `express-rate-limit` (MIT, backend) y `flutter_secure_storage` ^10.3.4 (BSD-3, las dos apps). Ninguna de nube.

## Planificación 2026-11-24 (cierre) — sin código nuevo
- Decisiones D5, D63–D65 y el límite de intentos registradas (`09`).
- Diseño de almacenamiento (`16`), requisitos de integración y diseño del límite de intentos (`14` §4–5), propuesta del 003 v2 (`13` §7) y plan v2 de la Fase 3 con el orden de implementación (`15`).
- Estado sin cambios: Fase 2 **implementada y probada** (29/29) pero **no integrada** con las apps; 002 (43/43) y 003 (23/23) **ensayados, no aplicados**.

## SQL 003 (D60, D61, D62) — ENSAYADO OK (23/23), NO aplicado (2026-11-24)
- Detalle en `13_SQL_003_NOTIFICACIONES_Y_PERMISOS.md`. Requiere el 002 v10. No modifica el 002 (que sigue en 43/43).
- **Implementado y probado (en la BD de ensayo):**
  - claves de evento únicas en las notificaciones;
  - plazo de 24 h guardado en la solicitud;
  - `admin_permisos` con historial;
  - resoluciones atadas al permiso del mismo admin;
  - AJUSTE solo con resolución.
- **Pendiente de integración:**
  - aplicarlo en producción (autorización);
  - el código del backend que lo usa: la tarea periódica y el aviso de la Fase 4, y la resolución con `PERMISO_REQUERIDO` de la Fase 5;
  - D63 (a quién se otorga el permiso).
- Archivos nuevos:
  - `docs/backend/sql/003_*.sql` (SQL y rollback) y `003_schema_prisma_previsto.prisma`;
  - `src/scripts/{verificar-003,ensayo-003}.ts`, `src/scripts/lib/{objetos-003,ensayo-utils}.ts`;
  - scripts `db:verificar-003` y `db:ensayo-003`.
- Producción: `db:verificar-003` → 0/14, bloqueado porque falta el 002 (código 3, como se diseñó).

## Revisión de la Fase 2 (2026-11-24)
- Integración con las apps y el panel, y seguridad: ver `14`. **Implementado y probado en el backend; la integración con las dos apps Flutter está pendiente**: rutas, token y, en la app del trabajador, el campo de dirección. El login del panel ya es compatible; faltan su sesión y su logout.
- Corrección de contrato: `trabajador.rol = "TRABAJADOR"` (lo exige `ApiUser`). `npm test` sigue en 29/29.
- Plan de la Fase 3: `15` (no iniciada).

## Fase 2 — detalle (2026-11-24) — sin commit
Contrato en `06_CONTRATOS_API.md`; estructura en `04`. Funciona con el schema actual (no necesita el SQL 002).

### Archivos creados
- `src/config/auth.ts`
- `src/shared/auth/jwt.ts`, `src/shared/auth/password.ts`, `src/shared/validation/campos.ts`, `src/shared/errors/duplicados.ts`
- `src/modules/cliente/{index.ts, auth/routes.ts, controller.ts, repository.ts, dto.ts, token.ts, guard.ts}`
- `src/modules/trabajador/{index.ts, auth/…}` (mismos archivos)
- `src/modules/admin/{index.ts, auth/…, auth/origen.ts}`
- `test/soporte/{entorno,bd,http}.ts`, `test/auth.test.ts`, `test/importaciones.test.ts`
- `docs/backend/06_CONTRATOS_API.md`

### Archivos modificados
- `src/app.ts`: monta `/api/cliente`, `/api/trabajador`, `/api/admin` y el alias `/api/auth/admin`.
- `package.json` y `package-lock.json`:
  - agrega `jsonwebtoken`, `cookie-parser`, `@types/jsonwebtoken` y `@types/cookie-parser`;
  - quita `bcrypt`;
  - agrega el script `test`.
- `tsconfig.json`: incluye `test`.
- `.env.example`: variables JWT, vigencias, `BCRYPT_ROUNDS` y `PRUEBAS_DATABASE_NAME`.
- Docs 04, 07, 08, 09 y 10.
- **No se tocaron:** el SQL 002 v10, el rollback, el schema previsto, `src/scripts/**` (ensayo y librerías), `prisma/schema.prisma`, `.env` ni `backups/`.

### Pruebas
| Prueba | Resultado |
|---|---|
| `npm run typecheck` (src + test) | OK, 0 errores |
| `npm test`: 29 pruebas en 5 grupos | **29/29 OK** (≈33 s) |
| Cliente (9) | Registro (ignora `rol` del body; bcrypt), validaciones, 409 de correo y teléfono, **registro simultáneo** (uno 201 y otro 409), login por correo y por teléfono con el mismo mensaje exista o no la cuenta, token expirado / alterado / `alg:none`, cambio de contraseña que invalida el token viejo, cuenta suspendida (403), logout |
| Trabajador (4) | Registro propio, 409, login, me, cambio de contraseña, sin contraseña asignada → no entra |
| Admin (6) | Cookie httpOnly + SameSite + Path, sin token en el body, session/me, **alias `/api/auth/admin`**, CSRF (sin Origin u Origin ajeno → 403), un cliente no entra al panel, logout borra la cookie |
| Aislamiento (6) | Token de cada audiencia rechazado en las otras dos; secreto y `aud` verificados por separado; **el rol se verifica en la BD** (token válido con el id de otra clase de cuenta → 401) |
| Importaciones (4) | Ningún módulo importa de otra audiencia; `shared/` no importa de `modules/` |
| Al terminar `npm test` | BD de pruebas con 0 tablas; producción con la misma estructura y datos; `db:verificar-002` → 0/84 |
| `npm run db:ensayo-002` repetido después de los cambios | **43/43 OK** (D59 intacto) |
| Respaldos `backups/` (10 archivos) | Mismo SHA-256 antes y después |
| `npm audit --omit=dev` | Los mismos 3 avisos de `effect` (interno de la CLI de Prisma); ninguno nuevo |

### Pendiente
- Agregar los tres `JWT_SECRET_*` al `.env` (el usuario; hoy no están) para que arranque `npm run dev`.
- Rate limiting de los logins (D10, Fase 6), **antes del deploy**.
- Actualizar `AuthApi` de las apps Flutter y el logout/session del panel (`06`).
- D60–D62 (revisión de D59, en `09`).

## D1 — Contraseña de trabajadores (2026-11-24, autorizado por el usuario)
- `ALTER TABLE trabajadores ADD COLUMN password_hash VARCHAR(255) NULL AFTER correo` **ejecutado en la BD real**.
- `npx prisma db execute --file ...` falló con **P1014** ("la tabla `trabajadores` no existe"): indica que `DATABASE_URL` (solo la usa la CLI de Prisma) apunta a una base distinta de la que usa la app (`DATABASE_HOST`/`DATABASE_NAME`). Se ejecutó entonces por la conexión runtime de la app (la misma donde se verificaron las 13 tablas), con comprobación previa de que la columna no existía.
- Verificado: columna `password_hash`, `varchar(255)`, nullable, después de `correo`; tabla con 0 filas.
- Schema local: campo `password_hash String? @db.VarChar(255)` añadido a `trabajadores`. Es la **única diferencia** con el schema de referencia (`diff` verificado). `prisma validate` OK, `prisma generate` OK, `typecheck` OK, consulta Prisma que selecciona `password_hash` OK.
- Actualización (2026-11-24, después): el usuario corrigió `DATABASE_URL`. Verificado que la CLI de Prisma llega a la misma BD (`queLimpiamos`, con `trabajadores.password_hash`). Nota técnica: en TiDB, `IF(cond, 1, (SELECT 1 UNION SELECT 2))` falla siempre (evalúa la subconsulta), así que no sirve como prueba; para verificar, usar consultas que fallen si falta la tabla o la columna. El equipo de `Que-Limpiamos` no necesita aviso: el usuario indicó que ese proyecto puede quedar desactualizado.

## Propuesta definitiva del SQL 002 (2026-11-24) — NO ejecutada
- Motor verificado (solo lectura): **TiDB Cloud Serverless v8.5.3** (MySQL 8.0.11), FKs activas, transacciones pesimistas, UTC, `utf8mb4_unicode_ci`.
- Revisado el borrador v1 contra los 7 criterios del usuario → v2 en `11_PROPUESTA_CAMBIOS_SCHEMA.md` (§2 lista los cambios). SQL: `sql/002_detalle_solicitud_especialidades_invitaciones.sql`; reversión: `sql/002_rollback.sql`.
- Esquema Prisma previsto: `sql/002_schema_prisma_previsto.prisma` → `prisma validate` OK (sin conexión). El schema activo **no** se modificó.
- Respaldo: `12_RESPALDO_Y_RECUPERACION.md`. Scripts nuevos de solo lectura: `src/scripts/respaldo-db.ts` (`npm run db:respaldo`) y `src/scripts/verificar-002.ts` (`npm run db:verificar-002`). `backups/` añadido a `.gitignore`.
- Pruebas: `typecheck` OK; `db:verificar-002` → 0/22 (no aplicado); `db:respaldo` → 13 tablas, 4 filas (servicios 3, usuarios 1), en `backend/backups/2026-11-24T14-32-57-296Z/` (ignorado por git). **No probado:** restaurar el respaldo (requiere una BD vacía) ni ejecutar el DDL en TiDB (se propone un ensayo en una BD temporal).

## SQL 002 v3 (2026-11-24) — NO ejecutado
- Incorpora: admin sin intervención entre cliente y trabajador, registro y verificación de trabajadores, revisión por documento, archivado de trabajadores, cancelación con cargo (cliente y trabajador, umbral de 24 h), saldo del trabajador, historial de estados y notificaciones propias del trabajador.
- 15 tablas nuevas y columnas nuevas en 6 tablas existentes (todas con 0 filas); `servicios` y `usuarios` no se alteran. `db:verificar-002` actualizado → **0/35** (no aplicado). Rollback actualizado.
- `sql/002_schema_prisma_previsto.prisma` regenerado → `prisma validate` OK (28 modelos, 26 enums). `typecheck` OK.
- No probado: el DDL en TiDB (falta el ensayo) ni la restauración del respaldo.

## SQL 002 v4 (2026-11-24) — NO ejecutado
- Cambios: libro `trabajador_movimientos` (GANANCIAS/DEUDA, inmutable, idempotente), `fecha_hora_fin_estimada` (trabajos encimados), `motivo_cierre` en invitaciones (baja → todas `CANCELADA`), nombres congelados (áreas, especialidades, servicio).
- **Hallazgo:** los `updated_at` existentes ya tenían `ON UPDATE CURRENT_TIMESTAMP` en la BD (Prisma no lo muestra). Se quitó del 002 el `MODIFY` que lo agregaba (y del rollback, que lo habría eliminado). Corregidas las notas de 01, 02, 03 y 04.
- Verificado (solo lectura): la BD trabaja en UTC y Prisma lee y escribe DATETIME en UTC.
- `db:verificar-002` → 0/37, precondición OK. `prisma validate` del schema previsto OK (28 modelos, 28 enums, 8 `@updatedAt`). `typecheck` OK.
- No probado: el DDL en TiDB (ensayo pendiente) ni la restauración del respaldo.

## SQL 002 v5 (2026-11-24) — NO ejecutado en ninguna BD
- Incorpora:
  - duración configurable (`servicio_calculo`, `servicio_calculo_tipo_inmueble`, minutos en los extras, snapshot en la solicitud) y 60 min de traslado;
  - reparto 85/15 y `parametros_negocio`;
  - libro con cuentas POR_COBRAR, DISPONIBLE y DEUDA (compensación al trabajador, retención del 10 %, abono elegido por él, retiros futuros);
  - `solicitud_trabajadores` (bolsa e invitación, sin reinvitar tras rechazar o cancelar);
  - preferencia de mostrar solicitudes fuera de horario;
  - baja voluntaria y administrativa;
  - snapshot del inmueble en la solicitud (se quitó `inmuebles.guardado` y se agregó `archivado_en`).
- Scripts refactorizados con lógica común (`src/scripts/lib/`) y nuevo `db:ensayo-002`. `.ensayo` agregado a `.gitignore`.
- Validado:
  - `typecheck` OK;
  - `prisma validate` del schema previsto OK (30 modelos, 32 enums, 11 `@updatedAt`);
  - `db:verificar-002` en producción → 0/53 y precondición OK;
  - las protecciones del ensayo rechazan producción y `PIXAN`.
- **Ensayo bloqueado:** el usuario de la BD no puede crear bases (error 1044). Producción comprobada intacta. Falta autorización para usar `queLimpiamos_shadow` (vacía) u otra BD de ensayo.

## SQL 002 v6 (2026-11-24) — ENSAYADO OK, NO aplicado en producción
- v6 incorpora:
  - `metodo_pago` (el 15 % en efectivo queda como deuda), `LIBERACION_SALDO`, `COMISION_EFECTIVO`, `COMPENSACION_DESCUENTO`;
  - reglas de cancelación al 100 % para cliente y trabajador;
  - varias franjas por día (se cambia el índice único de `trabajador_horarios`);
  - `trabajador_estado_historial` (bajas y reactivaciones);
  - descuentos (`descuentos`, `descuento_servicios`, `descuento_usos`; la plataforma absorbe la pérdida);
  - notificación `SERVICIO_CANCELADO_POR_PLATAFORMA`. Se quitó `trabajadores.baja_admin_id`.
- Verificación: 60 objetos. Producción → 0/60.
- **Ensayo completo en `queLimpiamos_proyecto`: 29/29 OK** (respaldo, restauración idéntica, 002, introspección = schema previsto, pruebas, rollback idéntico, limpieza, producción intacta). Detalle en `12` §6.
- Hallazgos: producción tiene `CHECK (pisos >= 1)` en `inmuebles`; `updated_at` no sirve para ordenar con precisión.
- `typecheck` OK, `prisma validate` del previsto OK.
- **Siguiente paso:** autorización explícita para aplicar el 002 en producción (`12` §3).

## SQL 002 v7 (2026-11-24) — ENSAYADO OK (31/31), NO aplicado en producción
- v7 agrega:
  - `cliente_adeudos` y `solicitudes.adeudo_cobrado` (adeudo del cliente en efectivo, cobrado en su próximo servicio);
  - `COBRO_ADEUDO_CLIENTE` en el libro;
  - `efectivo_recibido_en`, `trabajador_marco_realizado_en` y `cliente_marco_realizado_en` (REALIZADO con doble confirmación);
  - CHECK `chk_usuario_cliente_telefono` (un cliente siempre tiene teléfono);
  - notificaciones nuevas.
- Verificación: 66 objetos; producción → 0/66.
- Ensayo 31/31 OK. `typecheck` OK. `prisma validate` OK (35 modelos, 40 enums).
- **Siguiente paso:** autorización explícita para aplicar el 002 v7 en producción.

## SQL 002 v10 (2026-11-24) — ENSAYADO OK (43/43), NO aplicado en producción — vigente
- v10 = v9 + D59 (detalle en `11` §0.10):
  - el pago en efectivo lo registra cualquiera de las dos partes, o el sistema (`SISTEMA`) al confirmarse automáticamente;
  - tipo de notificación del trabajador `PAGO_EFECTIVO_PRESUMIDO`.
- Sigue en **84 objetos**; producción → 0/84. `prisma validate` OK (37 modelos, 50 enums).
- Ensayo **43/43 OK** (2026-11-24T21-54). La prueba nueva reproduce la tarea periódica:
  - confirma y presume el pago solo en la solicitud EN_PROCESO y sin reportes;
  - no toca la CONFIRMADO ni la que tiene un reporte abierto;
  - no duplica la comisión si el cliente ya había registrado el pago;
  - si la tarea corre dos veces a la vez, deja una sola comisión;
  - el admin anula la comisión presumida con un AJUSTE tras el reporte "no recibí el efectivo", sin borrar el historial.
- Los 10 archivos de `backups/` (incluido el respaldo original `2026-11-24T14-32-57-296Z/`) tienen el mismo SHA-256 antes y después.
- No quedan decisiones abiertas sobre el 002. **Siguiente paso:** autorización explícita para aplicarlo en producción.

## SQL 002 v9 (2026-11-24) — ENSAYADO OK (42/42), NO aplicado en producción
- v9 agrega (detalle en `11` §0.10):
  - **estado del pago** independiente del servicio: `estado_pago`, `pago_registrado_en` y `pago_registrado_por`. La comisión del 15 % se registra al registrarse el pago, una sola vez. Se quitó `efectivo_recibido_en` y `pago_liberado_en` pasó a llamarse `ganancia_liberada_en`;
  - **reportes** (`solicitud_reportes`) y **resoluciones del admin** (`solicitud_resoluciones`), con evidencia de ambas partes (`evidencias_solicitud.aportada_por` y `reporte_id`) y `trabajador_movimientos.resolucion_id`;
  - garantías del libro ampliadas: `COBRO_ADEUDO_CLIENTE` una vez por solicitud, y un solo `AJUSTE` por movimiento, que siempre debe tener origen;
  - `DIAS_ESPERA_PAGO_ADEUDO = 0`, `realizado_via` gana `RESOLUCION_ADMIN`, y 5 tipos de notificación nuevos.
- Verificación: **84 objetos**; producción → 0/84.
- Ensayo **42/42 OK** a la primera (2026-11-24T21-45). `typecheck` OK. `prisma validate` OK (37 modelos, 50 enums, 14 `@updatedAt`).
- Respaldo original `backups/2026-11-24T14-32-57-296Z/` y los demás respaldos verificados intactos con SHA-256 antes y después del ensayo.
- Hallazgo: el "apartado de reportes" existente es solo un botón sin función en la app del cliente; no había tabla ni endpoint.
- Pendiente D59 (quién registra el pago en efectivo).
- **Siguiente paso:** autorización explícita para aplicar el 002 v9 en producción.

## SQL 002 v8 (2026-11-24) — ENSAYADO OK (40/40), NO aplicado en producción
- v8 agrega (detalle en `11` §0.9):
  - **compensación del trabajador** cuando el cliente no paga: `cliente_adeudos.compensacion_liberada_en` y `compensacion_pagada_por`, y el parámetro `DIAS_ESPERA_PAGO_ADEUDO` (30, provisional);
  - **garantías contra pagos dobles** en `trabajador_movimientos`: columnas generadas `clave_unica_solicitud` y `clave_unica_liberacion` con UNIQUE, y CHECK `chk_mov_liberacion_con_origen`;
  - **identidad:** `identidad_huella` (UNIQUE) e `identidad_registrada_en` en `usuarios` y `trabajadores`; `archivo_eliminado_en` en los dos `documentos_*`;
  - **confirmación del servicio:** `confirmacion_solicitada_en`, `aviso_evidencia_en`, `realizado_en`, `realizado_via` y `pago_liberado_en` en `solicitudes` (la evidencia usa la tabla existente `evidencias_solicitud`), parámetros 30 / 15 / 30 min y 5 tipos de notificación nuevos.
- Verificación: **78 objetos**; producción → 0/78.
- Ensayo **40/40 OK** (2026-11-24T20-47). `typecheck` OK. `prisma validate` OK (35 modelos, 42 enums).
- Hallazgos de las dos primeras corridas, ya corregidos:
  1. TiDB rechaza un CHECK sobre una columna con FK (error 3823): el CHECK ahora usa la columna generada.
  2. El paso 5b comparaba también las columnas nuevas (en NULL) de `usuarios`, la única tabla con filas a la que la v8 agrega columnas. Ahora compara solo las columnas originales. No había ningún dato modificado.
- **Siguiente paso:** autorización explícita para aplicar el 002 v8 en producción.
