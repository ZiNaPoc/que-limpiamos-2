# 27 — Continuidad del sprint final (2026-11-25, 1.ª sesión)

## Estado real
- **Repositorio:** `ZiNaPoc/que-limpiamos-2` (es el `origin` de esta copia; no es que-comemos). Rama de despliegue **`deploy/quelimpiamos-demo`**, publicada en GitHub; `main` sin tocar.
- **Backend:** 166 pruebas + 5 nuevas (`test/plataforma.test.ts`).
  - Listo para Render: `prisma generate` ya no exige `DATABASE_URL`.
  - Transacciones con `timeout` de 20 s: sin esto, la aceptación simultánea daba 500 contra TiDB Cloud. Corregido y probado (3/3 dan 200 y 409).
- **TiDB Cloud:**
  - la cuenta **no puede crear bases**;
  - la histórica **`queLimpiamos` NO se tocó** (esquema viejo, 3 servicios, 1 usuario);
  - la **demo** es **`queLimpiamos_proyecto`** (vacía y autorizada como BD de pruebas el 2026-11-24). Se construyó con `npm run nube:demo -- preparar` (000 + 002 v10 + 003 v2 + 004: 39 tablas y 22 CHECK) y se sembró con `npm run datos:nube`. Credenciales en `backend/.local/cuentas-demo-nube.json`.
- **Simulación de Render en la PC** (`backend/.local/simular-render.cjs`, puerto 3100, modo producción, BD de la nube):
  - `/health` y `/health/db` OK;
  - pruebas integrales por la API OK: permisos, inmuebles, cotización, invitación, rechazo, bolsa, cancelaciones, iniciar, terminar con fotos, confirmar.
- **Panel:**
  - Inicio, Clientes, Colaboradores y Catálogo ya usan **datos reales** (rutas nuevas `/api/admin/resumen`, `/clientes`, `/trabajadores` y `/catalogo` con crear, editar y activar o desactivar);
  - se borraron los contextos y datos de demostración;
  - `tsc` y build OK; lint **3 errores, todos preexistentes** (antes 13: los otros 10 estaban en los archivos de demo borrados);
  - **sin revisar todavía en el navegador**.
- **Render:** **NO creado aún.** El panel de Render pide iniciar sesión: lo hace el usuario en el navegador integrado.

## Datos para crear el servicio en Render (lo hace el usuario; el asistente no escribe secretos)
- **Web Service nuevo:** `quelimpiamos-api`. No tocar el de que-comemos.
- **Repositorio y rama:** `ZiNaPoc/que-limpiamos-2`, rama `deploy/quelimpiamos-demo`.
- **Root Directory:** `limpiandotuhogar/backend` · **Runtime:** Node.
- **Build Command:** `npm ci` (el `postinstall` genera Prisma) · **Start Command:** `npm start`.
- **Health Check Path:** `/health` · **Plan:** Free.
- **Variables:**
  - las de `backend/.local/render-variables.env`: secretos nuevos, `NODE_ENV=production` y `DATABASE_NAME=queLimpiamos_proyecto`;
  - más `DATABASE_HOST`, `DATABASE_USER` y `DATABASE_PASSWORD` de TiDB Cloud (los de `backend/.env`);
  - **no** hace falta `DATABASE_URL`.
- Cuando exista la URL `https://quelimpiamos-api.onrender.com` (o la que asigne Render), añadir el origen del panel a `CORS_ORIGINS` si se publica.
- **TiDB Cloud:** si la red está restringida, permitir las IP de salida de Render (en Render → Settings → Outbound IPs).

## Pendiente (en orden)
1. Usuario: iniciar sesión en Render y crear el servicio con los datos de arriba. Verificar `/health` y `/health/db` en la URL pública.
2. Commit de esta sesión ya publicado en `deploy/quelimpiamos-demo` (si falta, `git push`).
3. Reiniciar el servidor local: `npm run servidor:local` en `backend`. Se detuvo: **revisar que no quede un `node` escuchando en el puerto 3000**.
4. Revisar en el navegador Inicio, Clientes, Colaboradores y Catálogo.
5. App del trabajador: al iniciar sesión real, quitar las solicitudes, el perfil y los avisos simulados (`MockData`), integrar `GET /api/trabajador/notificaciones` y revisar si el registro (`register_screen`) llama a la API.
6. App del cliente: revisar el perfil, que muestra datos de la sesión; el perfil completo quedó para una fase posterior según el doc `09`.
7. Recompilar las dos APK con `--dart-define=API_URL=https://<url-render>` (HTTPS, sin IP local) y probar.
8. Dudas registradas:
   - verificar trabajadores nuevos desde el panel exige revisar sus documentos (fase de documentos), así que hoy solo las cuentas de prueba están verificadas;
   - el catálogo no deja auditoría en `moderacion_eventos` (sus entidades no lo incluyen).

## Comandos
- **Nube:** `npm run nube:demo -- estado` · `npm run datos:nube`.
- **Local:** `npm run servidor:local` · `npm test`.
- **Panel:** `npm run dev` en `appWeb`.
- **APK:** `flutter build apk --debug --dart-define=API_URL=...` (Flutter en `C:\Users\lolil\flutter\bin`).
- **No tocar:** el reporte abierto de la S3 (solicitud 3 en la BD local).
