# 03 — Plan de migración (propuesta para aprobación)

- **Fecha:** 2026-11-24 · **Fase:** 0 (plan; nada ejecutado)
- **Alcance de escritura:** solo `que-limpiamos-3/limpiandotuhogar/backend` y `que-limpiamos-3/docs/`. `Que-Limpiamos/` es solo lectura.

## 1. Arquitectura objetivo

```
backend/src/
  server.ts                  ← arranque, PORT de entorno, cierre ordenado (SIGTERM) + prisma.$disconnect
  app.ts                     ← express.json (límite), cookie-parser, CORS, trust proxy, /health, montaje de módulos, 404, errores
  config/
    env.ts                   ← lectura y validación de variables al arrancar (falla rápido)
    prisma.ts                ← adapter MariaDB + singleton (de A)
  shared/                    ← SOLO utilidades transversales, sin lógica de audiencia
    errors/AppError.ts, errors/prismaErrors.ts (P2002/P2003/P2025)
    http/asyncHandler.ts, http/respuestas.ts, http/paginacion.ts
    auth/jwt.ts              ← firmar/verificar con { secreto, audiencia, issuer } como parámetros
    auth/password.ts         ← hash/compare
    validation/              ← helpers de validación (texto, correo, teléfono 10 dígitos, enteros, fechas)
  middleware/error.middleware.ts, notFound
  modules/
    cliente/
      auth/   (routes, controller, repository, dto, guard requireCliente)
      perfil/ inmuebles/ servicios/ solicitudes/ resenas/ notificaciones/
      index.ts               ← Router montado en /api/cliente
    trabajador/
      auth/ perfil/ horarios/ servicios/ solicitudes/ evidencias/
      index.ts               ← /api/trabajador
    admin/
      auth/ (cookie) clientes/ trabajadores/ servicios/ solicitudes/ documentos/ estadisticas/
      index.ts               ← /api/admin
  scripts/ probar-db.ts
```

### Reglas de importación
- `modules/cliente/**` no importa de `modules/trabajador/**` ni `modules/admin/**` (y viceversa).
- Todo módulo puede importar de `shared/**` y `config/**`.
- `shared/**` no importa de `modules/**`.
- Cada audiencia tiene su propio guard; ningún guard acepta tokens de otra audiencia (secreto y `aud` distintos).
- Se verificará con un script de comprobación (`grep`) en CI/QA; opcionalmente ESLint `no-restricted-imports` (D10).

### Formato de respuesta y error
- Error: `{ "mensaje": string, "codigo"?: string }` con status HTTP correcto (404 para rutas inexistentes). Las apps Flutter ya leen `mensaje`.
- Listas paginadas: `{ "datos": [...], "pagina": n, "porPagina": n, "total": n }`.
- IDs numéricos en JSON (las apps esperan `int`); el panel espera strings → el módulo admin conserva su mapeo actual.

## 2. Fases

### Fase 1 — Fundación (sin endpoints de negocio)
1. Copiar `Que-Limpiamos/backend/prisma/schema.prisma` a `backend/prisma/schema.prisma` **sin modificarlo** (sustituye al provisional).
2. Borrar y regenerar `generated/` con `prisma generate` (nunca editar a mano); añadir `generated` a `.gitignore` y sacarlo del índice git (D11).
3. `package.json`: declarar `dotenv`, `jsonwebtoken`, `cookie-parser` (+ tipos), quitar el campo `prisma.schema` erróneo, mover `prisma`/`tsx` a `dependencies`, scripts `dev`, `start`, `typecheck`, `postinstall: prisma generate`, `db:probar`; `engines.node`.
4. `tsconfig.json` alineado con B (`noEmit`, `types: ["node"]`, `include` src/generated/prisma.config.ts) + `noUncheckedIndexedAccess`.
5. `config/env.ts`, `app.ts`, `server.ts`, errores, 404 real, `/health` (+ `/health/db` opcional con `SELECT 1`).
6. Crear `.env.example` completo (solo nombres y valores de ejemplo).
7. Retirar rutas provisionales (`/login`, `/signup`, `/galaxias`, `/hoyo-negro`) — **requiere decidir D12** (romper apps ahora o mantener compatibilidad temporal).
8. Verificación: `typecheck` OK, arranque local, `/health`, `SELECT 1` contra la BD real (solo lectura).

### Fase 2 — Auth por audiencia
- `shared/auth/jwt.ts` con `aud` (`cliente`/`trabajador`/`admin`), `iss`, `sub`, expiración; secretos separados `JWT_SECRET_CLIENTE`, `JWT_SECRET_TRABAJADOR`, `JWT_SECRET_ADMIN`.
- Guards: verifican firma, expiración, audiencia, rol, existencia y estado de la cuenta en BD en cada petición; dejan el actor en `res.locals`.
- Cliente: registro, login, me, logout (D9), cambio de contraseña.
- Trabajador: login + me — **bloqueado por D1**.
- Admin: login, session/me, logout (cookie httpOnly, `secure`+`sameSite=none` en producción).
- Pruebas de aislamiento cruzado (token de cliente en rutas de trabajador/admin → 401, etc.).

### Fase 3 — Cliente
Perfil, inmuebles (CRUD propio), catálogo de servicios activos, solicitudes (crear con precio calculado en servidor, listar propias, detalle, cancelar), reseñas, notificaciones, documentos INE (si D5), recuperación de contraseña (si D6).

### Fase 4 — Trabajador
Perfil, horarios, servicios (especialidades), solicitudes disponibles/aceptación atómica (si D2 lo permite), mis solicitudes, transiciones `CONFIRMADO→EN_PROCESO→REALIZADO`, evidencias (D5).

### Fase 5 — Admin
Clientes (+ verificación INE), trabajadores (alta, edición, estado, horarios, especialidades, documentos, alta de credenciales según D1), servicios (CRUD + activar/inactivar), solicitudes (listado con filtros/paginación, asignación, estados), estadísticas simples (conteos por estado). Mantener contratos actuales del panel.

### Fase 6 — Transversal
Almacenamiento persistente (D5), notificaciones, rate limiting en logins (D10), logs, tests automatizados (D10), documentación de API.

### Fase 7 — QA y deploy
Typecheck, tests, aislamiento, CORS, variables, health, build y checklist de Render. No se declara deploy funcionando sin verificarlo.

## 3. Cambios requeridos en frontends (a documentar en `06_CONTRATOS_API.md`)
- Apps Flutter: nuevas rutas con prefijo; enviar `Authorization: Bearer`; persistir token; quitar `cliente_id`/`trabajador_id`/`rol` del body; adaptar modelos (`estrellas`→`cliente`, `galaxias`→`inmueble`, `seleccion`→campos reales, estados reales); flujo de solicitud debe elegir un `servicio_id` del catálogo y crear/usar un inmueble propio.
- Panel web: corregir default `VITE_API_URL` (`http://localhost/3000`), hacer que `apiFetch` lance error en `!respuesta.ok`, quitar la contraseña demo de `configuracion.ts`, conectar clientes/trabajadores/catálogo reales; rutas de auth según D7.

## 4. Riesgos
| Riesgo | Impacto | Mitigación |
|---|---|---|
| Trabajadores sin credenciales en BD | Bloquea toda la audiencia trabajador | Decisión D1 antes de Fase 2 |
| Credenciales en historial git de `Que-Limpiamos` | Acceso no autorizado a la BD | Rotar contraseña BD y secretos JWT |
| Apps Flutter dependen de rutas provisionales | Se rompen al migrar | D12 + actualizar apps en paralelo |
| Pérdida de datos de `seleccion` (notas, extras, áreas) | Menos información en la solicitud | D3 |
| Archivos en disco en Render | Se pierden en cada deploy/reinicio | Almacenamiento externo (D5) |
| `updated_at` | Resuelto: la BD ya lo actualiza (`ON UPDATE CURRENT_TIMESTAMP`) y Prisma llevará `@updatedAt` | — |
| BD sin historial de migraciones | `migrate deploy` no aplica nada / riesgo de drift | No usar migrate; cualquier cambio de schema se hace con SQL revisado y autorizado + `db pull` |
| Polling cada 3 s de la app trabajador | Carga en BD/Render | Paginación + intervalo mayor; evaluar después |
