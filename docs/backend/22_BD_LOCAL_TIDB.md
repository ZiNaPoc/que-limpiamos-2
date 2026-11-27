# 22 — BD LOCAL de desarrollo y pruebas (TiDB 8.5.3 en Docker)

- **Fecha:** 2026-11-25 · **Desde la Fase 3a**, las migraciones, las pruebas y la demo usan **solo** esta BD local. El clúster remoto (producción `queLimpiamos` y `queLimpiamos_proyecto`) **no se lee ni se escribe**.
- **Motor:** `pingcap/tidb:v8.5.3`, la misma versión que producción (que es Serverless). Contenedor `quelimpiamos-tidb`, publicado **solo** en `127.0.0.1:4000`, usuario `root` sin contraseña, solo local.
- **Esquema:** se arma únicamente con archivos del repositorio:
  1. `docs/backend/sql/000_estructura_produccion.sql`: las 13 tablas de producción, **sin datos**, extraídas del respaldo lógico del 2026-11-24;
  2. el 002 v10;
  3. el 003 v2.

## 1. Comandos (desde `limpiandotuhogar/backend`)
| Comando | Qué hace |
|---|---|
| `npm run bd:local -- iniciar` | Crea o arranca el contenedor (la primera vez descarga la imagen oficial) y verifica que sea el TiDB local |
| `npm run bd:local -- preparar` | Crea `quelimpiamos_dev` con 000 + 002 + 003 v2 (`--recrear` la rehace) |
| `npm run bd:local -- estado` | Versión, BD del proyecto y CHECK activos por tabla |
| `npm run prisma:local` | `prisma db pull` contra `quelimpiamos_dev`, marca las columnas generadas con `@ignore` y regenera el cliente |
| `npm test` | Pruebas contra `quelimpiamos_pruebas`: el esquema se construye solo y se rehace si cambian los SQL; las filas se borran entre archivos |
| `npm run demo:local [-- --con-moderacion]` | Demo en `quelimpiamos_demo`, que **se borra al detener**. Con `--con-moderacion` crea una propietaria y un moderador **de prueba** en esa BD efímera |
| `npm run demo:limpiar` | Borra `quelimpiamos_demo` si la demo se cerró de golpe |
| `npm run permisos:asignar-propietario -- --correo <correo>` | Asignación inicial auditada al propietario en `quelimpiamos_dev` (solo si la cuenta existe como ADMIN activa) |

## 2. Cómo se garantiza que es LOCAL
- `usarBdLocal()` fija host `127.0.0.1`, puerto 4000, `root` y `DATABASE_TLS=false` **en el proceso**. No modifica `.env` ni `DATABASE_URL`.
- `config/env.ts` solo permite `DATABASE_TLS=false` y una contraseña vacía si el host es `127.0.0.1`/`localhost`.
- Antes de cualquier cambio, `verificarQueEsLocal()` exige que el servidor diga `TiDB` y **no** `serverless`.
- Solo se aceptan tres nombres de BD: `quelimpiamos_dev`, `quelimpiamos_pruebas` y `quelimpiamos_demo`.

## 3. Detalle de TiDB que hay que saber
Los CHECK solo se crean si la conexión ya tiene `tidb_enable_check_constraint = ON`. Es una variable global, y cada conexión la lee al abrirse. Con ella apagada, TiDB **descarta los CHECK sin avisar**. Por eso `activarChecksLocales()` la activa y la construcción usa una conexión **nueva**. Para verlos: `information_schema.TIDB_CHECK_CONSTRAINTS`.

## 4. Docker Desktop en Windows (problema encontrado)
Si el equipo se apaga sin cerrar Docker Desktop, quedan **sockets viejos de 0 bytes** que impiden arrancar ("The file cannot be accessed by the system"):
- `%LOCALAPPDATA%\Docker\run\dockerInference`
- `%LOCALAPPDATA%\Docker\run\userAnalyticsOtlpHttp.sock`
- `%LOCALAPPDATA%\docker-secrets-engine\engine.sock`

Windows no puede borrarlos. Se borran desde WSL con Docker Desktop cerrado (con autorización del usuario):
```powershell
wsl.exe -d Ubuntu -- rm -f "/mnt/c/Users/<usuario>/AppData/Local/Docker/run/dockerInference" "/mnt/c/Users/<usuario>/AppData/Local/Docker/run/userAnalyticsOtlpHttp.sock" "/mnt/c/Users/<usuario>/AppData/Local/docker-secrets-engine/engine.sock"
```
No hace falta "Reset to factory defaults".

## 5. Panel contra el backend local
`appWeb/.env.local` tiene `VITE_API_URL=http://localhost:3000` (ignorado por git; plantilla en `appWeb/.env.example`). Para verlo todo:
1. `npm run bd:local -- iniciar`
2. `npm run demo:local -- --con-moderacion`
3. en `appWeb`: `npm run dev`
