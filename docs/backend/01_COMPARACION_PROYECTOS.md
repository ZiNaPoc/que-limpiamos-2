# 01 — Comparación de proyectos

- **Fecha:** 2026-11-24 · **Fase:** 0
- **Archivos analizados:** `prisma/schema.prisma`, `prisma.config.ts`, `package.json`, `tsconfig.json`, `.gitignore`, `.env.example` y todo `src/` de ambos backends; clientes API de las dos apps Flutter y del panel web.

## 1. Versiones (instaladas en `node_modules`)

| Paquete | A (que-limpiamos-3) | B (Que-Limpiamos) | Nota |
|---|---|---|---|
| Node (máquina) | 24.21.0 | 24.21.0 | Fijar `engines.node` para Render |
| prisma (CLI) | 7.10.1 | 7.10.1 | B lo tiene en `dependencies` (necesario para `postinstall` en Render) |
| @prisma/client | 7.10.1 | 7.10.0 | |
| @prisma/adapter-mariadb | 7.10.1 | 7.10.0 | Driver adapter; mismo método de conexión |
| mariadb | 3.5.5 | 3.5.5 | |
| express | 5.3.0 | 5.3.0 | |
| typescript | 7.0.2 | 7.0.2 | |
| tsx | 4.23.15 | 4.23.15 | B en `dependencies` (lo usa `start`) |
| dotenv | 17.4.2 (transitivo, no declarado) | 18.0.10 (declarado) | |
| hash | bcryptjs 3.0.3 (usado) + bcrypt 6.0.0 (sin uso) | bcrypt 6.0.0 | Hashes bcrypt son compatibles entre ambas libs |
| jsonwebtoken | — | 9.0.3 | |
| cookie-parser | — | 1.4.7 | |
| multer | — | **importado pero no instalado** | |

## 2. Configuración y conexión

| Aspecto | A | B |
|---|---|---|
| Generador | `prisma-client` → `../generated/prisma` | igual |
| Provider | mysql (conecta con adapter MariaDB, TLS 1.2, `rejectUnauthorized`) | igual |
| Puerto BD por defecto | 4000 (validado como entero) | 4000 (sin validar) |
| Singleton Prisma | sí (`globalThis` en dev) | no |
| `prisma.config.ts` | `DATABASE_URL` | `DATABASE_URL` + `SHADOW_DATABASE_URL` |
| Migraciones | no hay carpeta | no hay carpeta (BD creada fuera de Prisma; el schema parece introspección `db pull`) |
| `generated/` en git | **sí** (desactualizado respecto al schema real) | no (ignorado) |
| Scripts | solo `dev` | `dev`, `start` (tsx), `postinstall` (prisma generate), `migrate:deploy` |
| cookie-parser | no | sí |
| CORS | `CORS_ORIGINS` (lista por comas), `credentials:true` | igual |
| Health | `/health` → `{status:"ok"}` | `/health` → `{ok:true}` (antes de CORS) |
| 404 | responde 400 | responde 400 |
| Formato de error | `{mensaje, error}` | `{mensaje}` |

## 3. Variables de entorno (solo nombres)

| Variable | A | B | Propósito |
|---|---|---|---|
| `DATABASE_HOST` | ✔ | ✔ | Adapter en runtime |
| `DATABASE_PORT` | ✔ | ✔ | Adapter en runtime |
| `DATABASE_USER` | ✔ | ✔ | Adapter en runtime |
| `DATABASE_PASSWORD` | ✔ | ✔ | Adapter en runtime |
| `DATABASE_NAME` | ✔ | ✔ | Adapter en runtime |
| `DATABASE_URL` | ✔ | ✔ | Solo CLI de Prisma (`prisma.config.ts`). **Duplica** los 5 anteriores |
| `SHADOW_DATABASE_URL` | — | ✔ | Solo `migrate dev`; innecesaria en producción |
| `PORT` | ✔ | ✔ | Express (Render lo inyecta) |
| `NODE_ENV` | ✔ | ✔ | Cookies `secure`/`sameSite` |
| `CORS_ORIGINS` | ✔ | ✔ | Orígenes permitidos |
| `JWT_SECRET` | — | ✔ | Firma JWT (único para todas las audiencias) |
| `JWT_EXPIRES_IN` | — | ✔ | Expiración |
| `UPLOADS_DIR` | — | usada en código, no en `.env` | Disco local (efímero en Render) |

A no tiene `.env.example`. El `.env.example` de B no lista `JWT_SECRET`/`JWT_EXPIRES_IN`/`UPLOADS_DIR` (solo un comentario `#TOKEN`).

## 4. Comparación de schema

### Modelos

| A (provisional) | B (real) | Observación |
|---|---|---|
| `estrellas` | `usuarios` + `trabajadores` | En la BD real clientes/admin y trabajadores son **tablas distintas** |
| `galaxias` | `inmuebles` | Real tiene dueño (`usuario_id`), `alias`, `direccion`, timestamps |
| `hoyo_negro` | `solicitudes` | Real normaliza: `servicio_id`, `inmueble_id`, `direccion_servicio`; sin JSON libre |
| — | `servicios` | Catálogo (no existe en A) |
| — | `trabajador_servicios` | Especialidades N:M (PK compuesta) |
| — | `trabajador_horarios` | Un horario por día (`uq_horario_dia`) |
| — | `documentos_cliente` | INE frente/reverso (único por tipo) |
| — | `documentos_trabajador` | Identificación / comprobante (único por tipo) |
| — | `evidencias_solicitud` | Fotos de evidencia por solicitud |
| — | `notificaciones` | Solo para `usuarios` (no trabajadores) |
| — | `resenas` | Una por solicitud, 2 puntuaciones |
| — | `password_reset_tokens` | Solo para `usuarios` |

### Enums

| A | B |
|---|---|
| `estrellas_rol { CLIENTE, TRABAJADOR }` | `usuarios_rol { CLIENTE, ADMIN }` — **no existe TRABAJADOR** |
| `galaxias_tipo { CASA, OFICINA, DEPARTAMENTO }` | `inmuebles_tipo` (mismos valores) |
| `hoyo_negro.estado` String `DISPONIBLE`/`ACEPTADA` | `solicitudes_estado { PENDIENTE, CONFIRMADO, EN_PROCESO, REALIZADO, CANCELADO, RECHAZADO }` |
| — | `usuarios_estado_cuenta`, `usuarios_estado_verificacion`, `trabajadores_estado`, `servicios_estado`, `documentos_cliente_tipo`, `documentos_trabajador_tipo`, `notificaciones_tipo` |

### Hallazgos críticos del schema real
1. **`trabajadores` no tiene `password_hash`** ni ninguna credencial → con la BD real **un trabajador no puede autenticarse**. Bloqueo para la Fase 2 (ver `09_DECISIONES_PENDIENTES.md` D1).
2. `usuarios_rol` no contempla trabajadores → no se puede "convertir" `estrellas.rol=TRABAJADOR` a `usuarios`.
3. Los `updated_at` aparecen en Prisma con `@default(now())` y sin `@updatedAt`. **Corrección 2026-11-24:** en la BD ya tienen `ON UPDATE CURRENT_TIMESTAMP` (verificado en `information_schema`), así que sí se actualizan; Prisma no muestra esa opción. En el schema llevarán `@updatedAt` (SQL 002).
4. `telefono` es `Char(10)` (A validaba 7–15 dígitos) y es **nullable** en `usuarios`, obligatorio en `trabajadores`.
5. `solicitudes.inmueble_id` es opcional pero `direccion_servicio` y `fecha_hora_programada` son obligatorios.
6. Sin campos para: motivo/actor de cancelación, notas del cliente, extras/áreas, lat/long, modo de elección del colaborador, calificación del trabajador al cliente.
7. `notificaciones` y `password_reset_tokens` solo referencian `usuarios`.
8. `estado_verificacion` de usuarios es nullable con default `PENDIENTE`.

## 5. Tabla de equivalencias (obligatoria)

| Nombre actual en que-limpiamos-3 | Nombre real | Proyecto fuente | Acción | Observaciones |
|---|---|---|---|---|
| modelo `estrellas` (rol CLIENTE) | `usuarios` (rol `CLIENTE`) | B | Reemplazar | |
| modelo `estrellas` (rol TRABAJADOR) | `trabajadores` | B | Reemplazar | Sin credenciales → D1 |
| `estrellas.id` | `usuarios.id` / `trabajadores.id` | B | Renombrar | IDs de tablas distintas pueden coincidir: nunca mezclar audiencias |
| `estrellas.name` | `nombre_completo` (VarChar 120) | B | Renombrar | Límite baja de 255 a 120 |
| `estrellas.phone_number` (VarChar 15) | `telefono` (Char 10) | B | Renombrar + ajustar validación | Opcional en `usuarios` |
| `estrellas.email` | `correo` (VarChar 150) | B | Renombrar | Límite baja de 255 a 150 |
| `estrellas.password` | `usuarios.password_hash` | B | Renombrar | Trabajadores: no existe |
| `estrellas.rol` / `estrellas_rol` | `usuarios.rol` / `usuarios_rol` | B | Reemplazar | Valores `CLIENTE`/`ADMIN` |
| `estrellas.horario` (String libre) | `trabajador_horarios` (dia_semana, hora_inicio, hora_fin) | B | Reemplazar | Tabla normalizada |
| — | `usuarios.estado_cuenta` | B | Nuevo | Validar `ACTIVA` en login y guards |
| — | `trabajadores.estado` | B | Nuevo | Validar `ACTIVO` |
| modelo `galaxias` | `inmuebles` | B | Reemplazar | Ahora pertenece a un cliente |
| `galaxias_tipo` | `inmuebles_tipo` | B | Renombrar | Mismos valores |
| `galaxias.habitaciones/banos/medios_banos/pisos` | mismos nombres (UnsignedTinyInt con defaults) | B | Conservar | Validar 0–255 |
| — | `inmuebles.direccion`, `alias`, `usuario_id` | B | Nuevo | `direccion` obligatoria |
| modelo `hoyo_negro` | `solicitudes` | B | Reemplazar | |
| `hoyo_negro.cliente_id` | `solicitudes.cliente_id` → `usuarios` | B | Conservar nombre | Tomar del token, nunca del body |
| `hoyo_negro.id_galaxias` (obligatorio) | `solicitudes.inmueble_id` (opcional) | B | Renombrar | Validar que el inmueble sea del cliente |
| `hoyo_negro.fecha` (opcional) | `fecha_hora_programada` (obligatorio) | B | Renombrar | |
| `hoyo_negro.seleccion` (Json) | **no existe** | — | Eliminar / decidir | Se pierde: tipoLimpieza, notas, áreas, extras, duración. Ver D3 |
| (tipoLimpieza en JSON) | `solicitudes.servicio_id` → `servicios` | B | Reemplazar | Servicio del catálogo |
| (direccion en JSON) | `solicitudes.direccion_servicio` | B | Reemplazar | |
| `hoyo_negro.total` | `precio_estimado` | B | Renombrar | Calcular en servidor desde `servicios.precio_base` (D4) |
| `hoyo_negro.estado` `DISPONIBLE` | `PENDIENTE` (sin trabajador) | B | Reemplazar | |
| `hoyo_negro.estado` `ACEPTADA` | `PENDIENTE` con trabajador o `CONFIRMADO` | B | Reemplazar | Depende de D2 |
| `hoyo_negro.trabajador_id` (sin FK) | `solicitudes.trabajador_id` FK → `trabajadores` | B | Conservar nombre | Ahora con FK real |
| relación `estrellas` en include | `usuarios` | B | Renombrar | |
| relación `galaxias` en include | `inmuebles` | B | Renombrar | |
| respuesta `{ estrella: {...} }` | `{ cliente }` / `{ trabajador }` / `{ usuario }` | — | Cambiar contrato | Requiere cambio en apps Flutter |
| ruta `POST /login` | `POST /api/cliente/auth/login` y `POST /api/trabajador/auth/login` | — | Separar | |
| ruta `POST /signup` | `POST /api/cliente/auth/registro` | — | Reemplazar | Sin campo `rol` |
| ruta `/galaxias` | `/api/cliente/inmuebles` | — | Reemplazar | Solo del cliente autenticado |
| ruta `/hoyo-negro` (POST) | `POST /api/cliente/solicitudes` | — | Reemplazar | |
| ruta `/hoyo-negro?cliente_id=` | `GET /api/cliente/solicitudes` | — | Reemplazar | ID del token |
| ruta `/hoyo-negro?trabajador_id=` | `GET /api/trabajador/solicitudes` | — | Reemplazar | ID del token |
| ruta `/hoyo-negro/disponibles` | `GET /api/trabajador/solicitudes/disponibles` | — | Depende de D2 | |
| ruta `PATCH /hoyo-negro/:id/aceptar` | `PATCH /api/trabajador/solicitudes/:id/aceptar` | — | Depende de D2 | Conservar patrón atómico |
| ruta `/api/auth/admin/*` (B) | `/api/admin/auth/*` | B | Mover + alias temporal | El panel llama a `/api/auth/admin/login` (D7) |
| carpetas `controller/`, `repositories/` | `src/modules/<audiencia>/<recurso>/` | — | Reestructurar | Ver `03_PLAN_MIGRACION.md` |
| `bcryptjs` + `bcrypt` | una sola librería | — | Unificar | D8 |
| `test-db.ts` | `scripts/probar-db.ts` | A/B | Mover | |

## 6. Lógica: qué se conserva y qué se reescribe

| Funcionalidad | Estado en A | Estado en B | Decisión |
|---|---|---|---|
| Registro cliente | Existe (con rol en body) | — | Conservar validaciones; quitar `rol`; usar `usuarios` |
| Login cliente | Existe sin token | `requireCliente` sin uso | Reescribir con JWT de audiencia cliente |
| Login trabajador | Mismo login genérico | — | **Bloqueado** (D1) |
| Login admin | — | Existe (cookie) | Conservar y endurecer (secreto/aud propios) |
| Session/me admin | — | Básico | Ampliar con datos del admin |
| Logout | — | Admin (borra cookie) | Admin igual; Bearer = descarte en cliente (D9) |
| Inmuebles | `galaxias` sin dueño | — | Reescribir sobre `inmuebles` con dueño |
| Solicitudes cliente | Crear/listar inseguro | — | Reescribir sobre `solicitudes` |
| Disponibles / aceptar (trabajador) | Existe, atómico | — | Conservar patrón; regla de negocio en D2 |
| Asignación admin | — | Existe | Conservar (corregir bugs) |
| Listado admin | — | Existe | Conservar (corregir `toISOString`) |
| Servicios, horarios, especialidades, documentos, evidencias, reseñas, notificaciones, reset de contraseña | — | Solo schema | Implementar en fases 3–6 |
| Manejo de errores | `AppError` + P2002/P2003 | `AppError` | Unificar en uno |
