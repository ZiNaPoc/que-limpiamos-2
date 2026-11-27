# 00 — Auditoría inicial (Fase 0, solo lectura)

- **Fecha:** 2026-11-24
- **Fase:** 0 — Auditoría de solo lectura
- **Objetivo:** inventariar y diagnosticar ambos backends antes de cualquier cambio.
- **Archivos modificados:** ninguno de código. Solo se crearon los documentos de `docs/backend/`.
- **Archivos eliminados:** ninguno.

## 1. Ubicación verificada

| Proyecto | Ruta real | Git |
|---|---|---|
| A — trabajo | `limpieza/que-limpiamos-3/limpiandotuhogar/backend` | repo `que-limpiamos-3` (remoto `ZiNaPoc/que-limpiamos-2`, rama `main`) |
| B — fuente de verdad | `limpieza/Que-Limpiamos/backend` | repo `Que-Limpiamos` (remoto `ZiNaPoc/Que-Limpiamos`) |

> Nota: dentro de `que-limpiamos-3` el backend está en la subcarpeta `limpiandotuhogar/backend`, no en la raíz. Estos documentos viven en `que-limpiamos-3/docs/backend/` como se pidió.

Otros proyectos dentro de `que-limpiamos-3/limpiandotuhogar/` (consumidores del backend):
- `apps/app_contratador_diseno_que_limpiamos/app_contratador` — Flutter, app del **cliente**.
- `apps/app_trabajador` — Flutter, app del **trabajador**.
- `appWeb` — React + Vite, **panel de administración** (idéntico a `Que-Limpiamos/appWeb/src`; `diff -rq` sin diferencias).

## 2. Inventario del backend A (`que-limpiamos-3`)

```
backend/
  package.json, package-lock.json, tsconfig.json, prisma.config.ts, .gitignore, .env (no leído)
  prisma/schema.prisma            ← schema PROVISIONAL (estrellas / galaxias / hoyo_negro)
  generated/prisma/...            ← cliente generado del schema provisional, VERSIONADO EN GIT
  src/
    server.ts, app.ts, test-db.ts
    config/prisma.ts              ← adapter MariaDB + singleton global
    errors/AppError.ts
    middleware/error.middleware.ts
    controller/   login, galaxias, hoyo_negro
    repositories/ login, galaxy, hoyo_negro
    routes/       login, galaxias, hoyo_negro
```

### Endpoints actuales (A)

| Método | Ruta | Auth | Qué hace |
|---|---|---|---|
| GET | `/health` | — | `{status:"ok"}` |
| POST | `/login` | — | Login de `estrellas` por correo; devuelve `{estrella}` **sin token** |
| POST | `/signup` | — | Registro; **el rol lo elige el cliente en el body** (CLIENTE/TRABAJADOR) |
| GET | `/galaxias` | — | Lista **todos** los inmuebles de todos |
| GET | `/galaxias/:id` | — | Un inmueble |
| POST | `/galaxias` | — | Crea inmueble sin dueño |
| GET | `/hoyo-negro?cliente_id=&trabajador_id=` | — | Lista solicitudes filtrando por IDs del query |
| GET | `/hoyo-negro/disponibles` | — | Solicitudes `DISPONIBLE` |
| GET | `/hoyo-negro/:id` | — | Detalle |
| POST | `/hoyo-negro` | — | Crea solicitud con `cliente_id` del body |
| PATCH | `/hoyo-negro/:id/aceptar` | — | Acepta con `trabajador_id` del body (atómico con `updateMany where estado=DISPONIBLE`) |

### Diagnóstico de A
- **Sin autenticación real:** no hay JWT, cookies ni middleware. Toda identidad viene del body/query → cualquiera puede actuar como cualquier cliente o trabajador.
- `signup` permite auto-asignarse rol `TRABAJADOR` (el propio código lo marca "SOLO PARA LA DEMO").
- Lógica útil a conservar: validaciones de signup (correo, teléfono, longitud de contraseña), traducción de errores Prisma `P2002`/`P2003`, aceptación atómica con `updateMany` + condición de estado, `requireEnv` y singleton de Prisma, `AppError` + middleware de errores.
- Mezcla estilos de error: unos controllers responden `{error}` directo y otros usan `AppError` → `{mensaje, error}`.
- `package.json`: falta script `start`/`build`; `"prisma.schema": "src/prisma/schema.prisma"` apunta a una ruta que **no existe** (prisma.config.ts manda, pero es confuso); `dotenv` se importa y **no está declarado** (llega transitivo, v17); conviven `bcrypt` **y** `bcryptjs` (solo se usa `bcryptjs`).
- `tsconfig.json`: plantilla por defecto, `jsx: react-jsx`, `types: []`, `declaration: true`, sin `outDir` ni `noEmit` → un `tsc` sin flags emitiría `.js` junto a los `.ts`.
- `.gitignore` no ignora `generated/` (QL sí lo ignora).
- `rutaNoEncontrada` responde **400** en vez de 404.
- Type-check: `npx tsc --noEmit` → **sin errores**.

## 3. Inventario del backend B (`Que-Limpiamos/backend`)

```
backend/
  package.json (scripts dev/start/postinstall=prisma generate/migrate:deploy)
  prisma/schema.prisma            ← SCHEMA REAL (12 modelos, 10 enums). Sin carpeta migrations/
  prisma.config.ts                ← DATABASE_URL + SHADOW_DATABASE_URL
  generated/ (ignorado en git)
  src/
    app.ts (cookie-parser, /api/auth, /api/admin/solicitudes), server.ts
    config/prisma.ts, config/storage.ts (UPLOADS_DIR en disco local)
    controllers/ auth (admin), solicitudes (admin), clientes.ts (VACÍO), trabajadores.ts (VACÍO)
    middleware/ auth (requireAdmin, cookie), cliente (requireCliente, Bearer), error, upload (multer)
    repository/ auth, solicitudes
    routes/ auth, solicitudes, clientes.ts (VACÍO), trabajadores.ts (VACÍO)
    scripts/ generarHash.ts, probarDb.ts
    types/express.d.ts
```

### Endpoints actuales (B)

| Método | Ruta | Auth | Qué hace |
|---|---|---|---|
| GET | `/health` | — | `{ok:true}` |
| POST | `/api/auth/admin/login` | — | Login admin (`usuarios.rol=ADMIN`), JWT en cookie `admin_token` |
| GET | `/api/auth/admin/session` | cookie | `{autenticado, rol}` |
| POST | `/api/auth/admin/logout` | — | Borra cookie |
| GET | `/api/admin/solicitudes` | cookie admin | Lista todas las solicitudes (mapeo camelCase para el panel) |
| PATCH | `/api/admin/solicitudes/:id/asignacion` | cookie admin | Asigna/desasigna trabajador (solo si `PENDIENTE`, trabajador `ACTIVO` y con la especialidad) |

### Diagnóstico de B
- Es la referencia de **schema** y del patrón de auth de admin; la lógica de negocio implementada es mínima (2 endpoints admin).
- `requireCliente` existe pero **no se usa** en ninguna ruta.
- **Un único `JWT_SECRET`** para admin y cliente; la separación depende solo del claim `rol` (sin `aud`/`iss`).
- `upload.middleware.ts` importa `multer`, que **no está en package.json ni instalado** → `tsc --noEmit` falla con 2 errores (`TS2307`, `TS2339`). No está montado en ninguna ruta.
- Bug: `fechaProgramada: solicitud.fecha_hora_programada.toISOString` (sin `()`) → el campo desaparece del JSON que recibe el panel.
- Bug: en asignación, código duplicado (`if (valor !== null)` dos veces); `trabajadorId: undefined` se trata como número inválido (correcto por accidente).
- `requireAdmin` no deja al admin en `res.locals` (session no devuelve nombre/correo).
- `storage.ts` guarda en disco local → **efímero en Render**.
- `scripts/generarHash.ts` contiene una contraseña en texto plano (la misma que aparece como "cuenta de demostración" en `appWeb/src/data/configuracion.ts`).
- `start` usa `tsx` en producción (funciona, pero sin build/type-check previo).

## 4. Consumidores (contratos que hoy usan)

| Cliente | Base URL | Endpoints que llama | Auth que envía |
|---|---|---|---|
| App cliente (Flutter) | `--dart-define=API_URL`, default `http://10.0.2.2:3000` | `POST /login`, `POST /signup` (rol CLIENTE), `POST /galaxias`, `POST /hoyo-negro` | Ninguna; guarda el usuario en memoria |
| App trabajador (Flutter) | igual | `POST /login`, `POST /signup` (rol TRABAJADOR), `GET /hoyo-negro/disponibles` (polling cada 3 s), `GET /hoyo-negro?trabajador_id=`, `PATCH /hoyo-negro/:id/aceptar` | Ninguna |
| Panel web (React) | `VITE_API_URL` (default con typo `http://localhost/3000`) | `POST /api/auth/admin/login`, `GET /api/admin/solicitudes`, `PATCH /api/admin/solicitudes/:id/asignacion` | Cookie (`credentials: "include"`) |

- Ambas apps Flutter filtran el rol **en el cliente** (`if (user.rol != 'TRABAJADOR')`) → la separación hoy no existe en servidor.
- El panel web usa datos **demo** para clientes, trabajadores y catálogo (`clientesDemo`, `catalogoDemo`, `trabajadores.ts`); solo solicitudes y login van al backend.
- `apiFetch` del panel **no lanza error en respuestas 4xx/5xx** (solo si el cuerpo no es JSON) → los errores del servidor se tratan como éxito.
- La app trabajador espera las claves provisionales (`estrellas`, `galaxias`, `seleccion`, `estado: DISPONIBLE/ACEPTADA`) → romperá al migrar; requiere cambios de contrato (ver `06_CONTRATOS_API.md`, a crear en Fase 2/3).

## 5. Seguridad y secretos (sin revelar valores)

- `.env` **no** está versionado en `que-limpiamos-3` (verificado con `git ls-files`).
- En el historial de `Que-Limpiamos` **sí** se versionaron `appWeb/.env` y `appWeb/backend/.env` (commits `2835cbb`, `b604353`, `1bee863`, `f1bd8d7`; borrados después en `3c94eb8`/`f05e0c3`). Siguen recuperables del historial. **Recomendación: rotar la contraseña de la base de datos y el `JWT_SECRET`**, y en adelante tratar ese historial como comprometido. (No se comparó si los valores actuales coinciden con los históricos: esa comprobación fue denegada y no se reintentó.)
- Contraseña de la cuenta admin de demostración escrita en texto plano en dos archivos de código (ver §3). Debe cambiarse en la BD y eliminarse del código del panel.

## 6. Pruebas ejecutadas

| Prueba | Resultado |
|---|---|
| `npx tsc --noEmit` en A | OK, 0 errores |
| `npx tsc --noEmit` en B | **Falla**: 2 errores en `upload.middleware.ts` (falta `multer`) |
| `diff -rq` appWeb A vs B | Idénticos |
| `git ls-files` .env en A | No versionados |
| Conexión a BD | **No ejecutada** (fase de solo lectura) |

## 7. Próximos pasos
Ver `01_COMPARACION_PROYECTOS.md`, `02_MAPA_SCHEMA_REAL.md`, `03_PLAN_MIGRACION.md` y `09_DECISIONES_PENDIENTES.md`.
