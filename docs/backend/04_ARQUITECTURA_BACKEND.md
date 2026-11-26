# 04 — Arquitectura del backend

- **Fecha:** 2026-11-24 · **Fase:** 2 (auth por audiencia) implementada
- **Ruta:** `que-limpiamos-3/limpiandotuhogar/backend`

## Estructura actual (después de la Fase 1)

```
backend/
  prisma/schema.prisma      ← schema real de Que-Limpiamos + `trabajadores.password_hash` (D1, única diferencia)
  prisma.config.ts          ← sin cambios (DATABASE_URL para la CLI)
  generated/                ← generado por `prisma generate` (postinstall). Ignorado en git
  .env.example              ← nombres de variables, sin valores reales
  src/
    server.ts               ← listen(env.port) + cierre ordenado en SIGTERM/SIGINT
    app.ts                  ← trust proxy, /health, /health/db, CORS, express.json(100kb), 404, errores
    config/env.ts           ← lee y valida variables; falla al arrancar si falta una obligatoria
    config/prisma.ts        ← adapter MariaDB (TLS 1.2) + singleton en desarrollo
    middleware/error.middleware.ts ← 404 y manejador global
    shared/errors/AppError.ts       ← error de negocio (status, mensaje, codigo?)
    shared/errors/prismaErrors.ts   ← P2002→409, P2003→400, P2025→404
    scripts/probar-db.ts    ← SELECT 1 (npm run db:probar)
```

### Agregado en la Fase 2
```
src/
  config/auth.ts              ← secretos JWT (uno por audiencia, distintos, 32+ caracteres), vigencias, BCRYPT_ROUNDS, cookie del admin.
                                Separado de env.ts: los scripts de BD no lo cargan y funcionan sin secretos JWT
  shared/auth/jwt.ts          ← firmar/verificar (HS256, aud, iss, sub, pwv) con el secreto como parámetro; leerBearer
  shared/auth/password.ts     ← bcryptjs (D8): hash, verificación con tiempo constante aunque la cuenta no exista,
                                versionDePassword (huella del hash: al cambiar la contraseña los tokens viejos caducan)
  shared/validation/campos.ts ← validación manual: cuerpo objeto, texto, correo, teléfono (10 dígitos), contraseñas
  shared/errors/duplicados.ts ← qué campo chocó en un P2002 (correo/teléfono)
  modules/cliente/    index.ts + auth/{routes,controller,repository,dto,token,guard}.ts   → /api/cliente/auth
  modules/trabajador/ index.ts + auth/{routes,controller,repository,dto,token,guard}.ts   → /api/trabajador/auth
  modules/admin/      index.ts + auth/{routes,controller,repository,dto,token,guard,origen}.ts → /api/admin/auth (+ alias /api/auth/admin)
test/
  soporte/entorno.ts          ← apunta la app a la BD de pruebas ANTES de cargar env.ts; secretos aleatorios; bcrypt 4
  soporte/bd.ts               ← crea en la BD de pruebas (vacía) las tablas de producción SIN datos; al final las borra
                                y comprueba que producción no cambió (estructura y huellas de datos)
  soporte/http.ts             ← levanta la app en 127.0.0.1:<puerto libre> y hace peticiones con fetch
  auth.test.ts                ← 25 pruebas de auth y aislamiento
  importaciones.test.ts       ← 4 pruebas estáticas de las reglas de importación
```
Guards: `requireCliente`, `requireTrabajador` y `requireAdmin` (en `modules/<audiencia>/auth/guard.ts`). Las rutas de negocio de cada audiencia (Fases 3–5) se protegen con su guard y leen la cuenta con `clienteActual(res)`, `trabajadorActual(res)` o `adminActual(res)`.

## Estructura objetivo (Fases 2–5)

```
src/
  shared/auth/jwt.ts, shared/auth/password.ts, shared/validation/*, shared/http/*
  modules/
    cliente/    index.ts (/api/cliente)    auth/ perfil/ inmuebles/ servicios/ solicitudes/ resenas/ notificaciones/
    trabajador/ index.ts (/api/trabajador) auth/ perfil/ horarios/ servicios/ solicitudes/ evidencias/
    admin/      index.ts (/api/admin)      auth/ clientes/ trabajadores/ servicios/ solicitudes/ documentos/
```
Cada recurso: `*.routes.ts`, `*.controller.ts`, `*.repository.ts`, `*.dto.ts` (validación de entrada y forma de salida).

## Reglas
- `modules/<a>` nunca importa de `modules/<b>`. `shared/` y `config/` no importan de `modules/`.
- La identidad sale del token validado (`res.locals.<actor>`), nunca de body/query.
- Respuestas sin `password_hash`: toda salida pasa por un DTO (`dto.ts`) que elige los campos. Las pruebas verifican que ninguna respuesta mencione contraseñas.
- `updated_at`: la BD ya lo actualiza sola (`ON UPDATE CURRENT_TIMESTAMP`, verificado 2026-11-24) y Prisma llevará `@updatedAt` tras el SQL 002. No hace falta ponerlo a mano.
- Transiciones de estado con `updateMany` condicionado al estado previo + comprobación de `count`; `$transaction` si tocan más tablas.

## Contrato de errores
`{ "mensaje": string, "codigo"?: string }`. Códigos usados: `RUTA_NO_ENCONTRADA` (404), `JSON_INVALIDO` (400), `PAYLOAD_GRANDE` (413), `DUPLICADO` (409), `RELACION_INVALIDA` (400), `NO_ENCONTRADO` (404), `ERROR_INTERNO` (500, sin detalles internos) y los de autenticación de `06_CONTRATOS_API.md`.

## Endpoints disponibles hoy
| Método | Ruta | Respuesta |
|---|---|---|
| GET | `/health` | `200 {ok:true}` (no toca la BD) |
| GET | `/health/db` | `200 {ok:true,db:"ok"}` o `503 {ok:false,db:"error"}` |
| POST/GET | `/api/cliente/auth/*`, `/api/trabajador/auth/*`, `/api/admin/auth/*` (alias `/api/auth/admin/*`) | Ver `06_CONTRATOS_API.md` |

Las rutas provisionales (`/login`, `/signup`, `/galaxias`, `/hoyo-negro/*`) **fueron eliminadas** (D12) y responden 404. Sus sustitutos se implementan en las Fases 2–4.
