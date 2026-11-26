# 07 — Configuración y deploy (diagnóstico preliminar)

- **Fecha:** 2026-11-24 · **Fase:** 0 (diagnóstico; nada configurado aún)

## 1. Problemas actuales que afectan al deploy

| # | Problema | Dónde | Efecto en Render |
|---|---|---|---|
| 1 | No hay script `start` ni `build` | A `package.json` | Render no sabe cómo arrancar |
| 2 | `dotenv` no declarado | A | Puede faltar tras `npm ci` limpio |
| 3 | `prisma` y `tsx` en devDependencies | A | Si Render instala sin dev deps, falla `prisma generate`/arranque |
| 4 | Sin `postinstall: prisma generate` | A | El cliente usado sería el versionado (y desactualizado) |
| 5 | `generated/` versionado en git | A | Cliente obsoleto (schema provisional) llega a producción |
| 6 | `tsconfig` sin `noEmit`/`outDir` | A | Un `tsc` accidental ensucia `src/` |
| 7 | Archivos en disco local (`UPLOADS_DIR`) | B | Disco efímero: se pierden INE/evidencias |
| 8 | `multer` no instalado | B | Typecheck falla |
| 9 | Sin `trust proxy` | A y B | IP real incorrecta (rate limiting) |
| 10 | Un solo `JWT_SECRET` | B | Sin aislamiento criptográfico entre audiencias |
| 11 | Panel: default `VITE_API_URL` con typo | appWeb | Falla si no se define la variable |
| 12 | Sin cierre ordenado (SIGTERM) | A y B | Conexiones abiertas en redeploys |

## 2. Configuración objetivo (a implementar en Fase 1)

**Render (Web Service, Node):**
- Build command: `npm ci && npm run typecheck` (`postinstall` ejecuta `prisma generate`).
- Start command: `npm start` (`tsx src/server.ts`, igual que B; alternativa: compilar a `dist/` — D13).
- Health check path: `/health`.
- Node: fijar con `engines.node` (máquina actual usa 24.x).
- Variables (en el panel de Render, nunca en el repo): ver tabla.

| Variable | Requerida | Uso |
|---|---|---|
| `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_NAME` | Sí (runtime) | Adapter MariaDB con TLS |
| `DATABASE_URL` | Solo CLI Prisma | `prisma.config.ts`. `prisma generate` no conecta, pero `env()` puede exigirla → definirla también en Render o usar valor vacío controlado (verificar en Fase 1) |
| `SHADOW_DATABASE_URL` | No | Solo desarrollo con `migrate dev` (no se usará) |
| `PORT` | Render la inyecta | Express |
| `NODE_ENV` | Sí (`production`) | Cookies `secure` / `sameSite=none` |
| `CORS_ORIGINS` | Sí | Orígenes del panel web separados por coma |
| `JWT_SECRET_CLIENTE`, `JWT_SECRET_TRABAJADOR`, `JWT_SECRET_ADMIN` | **Sí** (Fase 2, implementado) | Un secreto por audiencia, de 32+ caracteres y **distintos** entre sí. Si falta uno o se repite, el servidor **no arranca** |
| `JWT_EXPIRACION_CLIENTE_SEG`, `JWT_EXPIRACION_TRABAJADOR_SEG`, `JWT_EXPIRACION_ADMIN_SEG` | No (7 d / 7 d / 8 h) | Vigencia de la sesión en segundos |
| `BCRYPT_ROUNDS` | No (12) | Costo de bcrypt; mínimo 10 (solo `NODE_ENV=test` permite 4) |
| `NODE_ENV=production` | Sí en Render | Activa la cookie del panel con `Secure` + `SameSite=None` (el panel está en otro dominio) |
| Variables de almacenamiento | Según D5 | Bucket / credenciales |

Las apps móviles no usan CORS (no son navegador); el panel web sí, con cookies cross-site → requiere HTTPS y `sameSite=none; secure`.

## 3. Pendiente de verificar en Fase 1
- Que `prisma generate` funcione en Render con `prisma.config.ts` cuando `DATABASE_URL` no esté disponible en build.
- Que TLS hacia la BD (puerto 4000, `rejectUnauthorized: true`) funcione desde Render.

## 4. Avance en Fase 1 (2026-11-24)
Resueltos: #1 (scripts `start`/`typecheck`), #2 (`dotenv` declarado), #3 (`prisma`/`tsx` en dependencies), #4 (`postinstall: prisma generate`), #5 (`generated/` fuera de git), #6 (`noEmit`), #9 (`trust proxy`), #12 (cierre ordenado en SIGTERM).
Añadido `/health/db` (SELECT 1, 503 si falla) además de `/health`.
`config/env.ts` hace fallar el arranque si falta `DATABASE_HOST/USER/PASSWORD/NAME`.
Sigue pendiente: #7 almacenamiento (D5), #10 secretos por audiencia (Fase 2), #11 typo de `VITE_API_URL` en el panel, y verificar el build real en Render (Fase 7).

## Actualización 2026-11-24 — límite de intentos, almacenamiento local y demo
| Variable | ¿Obligatoria? | Uso |
|---|---|---|
| `LIMITE_LOGIN_POR_IP`, `LIMITE_REGISTRO_POR_IP`, `LIMITE_PASSWORD_POR_IP` | No (30 / 10 / 10) | Límites por IP (ventanas de 15 min, 1 h y 15 min) |
| `ALMACENAMIENTO_DRIVER` | No (`local`) | Único driver implementado. S3/R2 se agregarán cuando haga falta (`16` §4) |
| `ALMACENAMIENTO_LOCAL_DIR` | No (`<home>/.quelimpiamos/almacenamiento`) | Carpeta privada **fuera del repositorio** (el backend se niega a arrancar si está dentro) |
| `ALMACENAMIENTO_FIRMA_SECRETO` | Recomendada (32+ caracteres) | Firma de las URLs temporales; si falta, se genera una por arranque |
| `ALMACENAMIENTO_MAX_MB` | No (5) | Tamaño máximo por archivo |

⚠ **Render no tiene disco persistente** en el servicio: con el driver local, los archivos que se guarden (cuando existan los endpoints de carga, Fase 3c) **se perderán en cada deploy o reinicio**. Sirve solo para demostraciones; para producción hay que migrar a un almacenamiento compatible con S3 (`16` §4). Los contadores del límite de intentos viven en memoria y también se reinician (aceptable con una sola instancia).

Demo local sin costo: `17_DEMO_LOCAL.md`.

## Secretos: qué pasa al arrancar (comprobado con `test/config.test.ts`)
| Proceso | Si faltan los `JWT_SECRET_*` | Si falta `ALMACENAMIENTO_FIRMA_SECRETO` |
|---|---|---|
| **Servidor** (`npm run dev` / `npm start`, y Render) | **No arranca**: "Falta la variable de entorno JWT_SECRET_CLIENTE". También falla si un secreto tiene menos de 32 caracteres o si dos son iguales. **Nunca los genera** | Desarrollo: genera uno temporal por ejecución. **Producción: no arranca** (obligatorio) |
| **Demo local** (`npm run demo:local`) | Desarrollo: genera secretos **temporales** para esa ejecución. **Producción: falla** (no los genera) | Igual que el servidor |
| **Pruebas** (`npm test`) | Secretos aleatorios propios por ejecución (aisladas a propósito) | Igual |

**Por qué hacen falta secretos estables para conservar las sesiones:** un token solo vale si se verifica con **el mismo secreto** con el que se firmó.
- Si la demo genera secretos nuevos en cada arranque, al reiniciarla todos los tokens anteriores dejan de valer: las apps reciben 401 (`TOKEN_INVALIDO`), borran su sesión y piden iniciar sesión de nuevo; la cookie del panel deja de valer.
- Con los secretos fijos en `.env` (local) o en las variables de Render (producción), las sesiones siguen valiendo después de reiniciar, hasta que vencen (7 días en las apps, 8 h en el panel) o hasta que el usuario cambia su contraseña.
- En producción **nunca** se generan solos. Cambiarlos a propósito, p. ej. al rotarlos (D16), cierra todas las sesiones.
