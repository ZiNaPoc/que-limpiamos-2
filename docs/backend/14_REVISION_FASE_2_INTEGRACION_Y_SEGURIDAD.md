# 14 — Revisión de la Fase 2: integración con las apps y el panel, y seguridad (JWT)

- **Fecha:** 2026-11-24 · Revisión del código real (backend, apps Flutter y panel), no solo de los documentos.
- Leyenda: **Implementado** = el código existe · **Probado** = lo cubre una prueba automatizada que pasa · **Pendiente de integración** = falta el cambio en el consumidor o en la configuración para que funcione de punta a punta.

## 1. Estado por pieza
| Pieza | Implementado | Probado | Integrado con el consumidor |
|---|---|---|---|
| Auth cliente (`/api/cliente/auth`: registro, login, me, logout, cambiar-password) | Sí | Sí (`npm test`) | **No**: la app del cliente sigue llamando a `/login` y `/signup` |
| Auth trabajador (`/api/trabajador/auth`, mismas rutas) | Sí | Sí | **No**: la app del trabajador igual |
| Auth admin (`/api/admin/auth` + alias `/api/auth/admin`) | Sí | Sí | **Parcial**: el login del panel ya es compatible; falta validar la sesión al abrir y llamar a logout |
| Guards `requireCliente`, `requireTrabajador`, `requireAdmin` | Sí | Sí (aislamiento entre audiencias) | Listos para las rutas de las Fases 3–5 (todavía no hay rutas de negocio) |
| Permiso financiero de admin (D62) | **No**: necesita la tabla `admin_permisos` del SQL 003 | Solo en el ensayo 003 (la consulta que usará el backend) | Después de aplicar 002 + 003 |
| Arranque del servidor con secretos JWT | Sí (falla si faltan o se repiten) | Sí (las pruebas usan secretos propios) | **No**: el `.env` no tiene los `JWT_SECRET_*` (comprobado solo por nombre) |

## 2. Contratos frente a cada consumidor (comprobado leyendo su código)
### App del cliente (`app_contratador/lib/services/api_client.dart`, `session.dart`, `register_screen.dart`)
| Punto | La app hoy | Backend | ¿Coincide? |
|---|---|---|---|
| Rutas | `POST /login`, `POST /signup` | `/api/cliente/auth/login`, `/registro` | **No**: cambiar en `AuthApi` |
| Body del registro | `nombre, correo, telefono, password, rol` | Los mismos (`rol` se ignora) | Sí (quitar `rol`) |
| Respuesta | Lee `data['estrella']` | `{ token, cliente }` | **No**: leer `cliente` |
| Modelo `ApiUser` | `id` (int), `nombre`, `correo`, `rol`, `telefono?` | `cliente` trae esos campos (probado) | Sí |
| Token | No lo guarda ni lo envía; `ApiClient` no manda `Authorization`; `Session` solo vive en memoria | Exige `Authorization: Bearer` | **No**: guardar el token (recomendado `flutter_secure_storage`) y enviarlo |
| Errores | Lee `error`, `mensaje` o `message` | `{ mensaje, codigo }` | Sí |

### App del trabajador (`app_trabajador/lib/services/api_client.dart`, `register_screen.dart`)
| Punto | La app hoy | Backend | ¿Coincide? |
|---|---|---|---|
| Rutas y respuesta | Igual que la del cliente (`/login`, `/signup`, `estrella`) | `/api/trabajador/auth/*`, `{ token, trabajador }` | **No** |
| Registro | Pide nombre, teléfono, correo y contraseña. **No pide dirección** | `direccion` obligatoria (la BD la exige: `NOT NULL`) | **No**: agregar el campo en la pantalla |
| Modelo `ApiUser` | Exige `rol` | **Corregido en el backend:** `trabajador.rol = "TRABAJADOR"` (probado) | Sí |
| Token | No lo guarda ni lo envía (tiene `shared_preferences`, que no es almacenamiento seguro) | Bearer | **No** |

### Panel (`appWeb/src/pages/LoginPage.tsx`, `App.tsx`, `data/api.ts`)
| Punto | El panel hoy | Backend | ¿Coincide? |
|---|---|---|---|
| Login | `POST /api/auth/admin/login` con `credentials: "include"`, lee `datos.usuario` | Alias implementado, responde `{ usuario }` + cookie | **Sí** (probado) |
| Tipo `Sesion` | `{ id?, nombre, correo, rol? }` | `{ id, nombre, correo, rol }` | Sí |
| Sesión al abrir | Solo lee `sessionStorage`; no consulta al servidor | `GET /api/admin/auth/session` | **No**: consultar al abrir y volver al login ante un 401 |
| Cerrar sesión | Borra `sessionStorage`; **no llama al servidor** (la cookie sigue válida hasta 8 h) | `POST /api/admin/auth/logout` borra la cookie | **No** |
| `apiFetch` | No lanza error si `!respuesta.ok` | — | **Bug del panel** (ya listado en `03` §3) |
| `VITE_API_URL` por defecto | `http://localhost/3000` (mal escrito) | `http://localhost:3000` | **Bug del panel** |
| `data/configuracion.ts` | Contiene una contraseña demo | — | **Quitar** (D16) |

Nada de esto se ejecutó de punta a punta con las apps (no hay secretos en `.env` ni emulador): la compatibilidad se comprobó leyendo el código de los consumidores y con las pruebas HTTP del backend.

## 3. Seguridad — configuración JWT y pendientes
| Tema | Estado | Acción |
|---|---|---|
| Secretos JWT | Uno por audiencia, ≥ 32 caracteres, distintos; sin ellos el servidor no arranca | **Usuario:** agregarlos al `.env` local y a Render (comando en `.env.example`). No reutilizar el `JWT_SECRET` viejo del historial de `Que-Limpiamos` |
| Algoritmo | Solo HS256; `alg: none` rechazado (probado) | — |
| Vigencia y revocación | 7 d apps / 8 h panel. Cambiar la contraseña revoca todo (probado). Suspender la cuenta corta el acceso en la siguiente petición (probado). Logout de app = borrar el token (D9-a) | Si se necesita "cerrar sesión en todos los dispositivos" sin cambiar la contraseña, hará falta una versión de sesión en la BD (cambio de schema futuro) |
| **Rate limiting en logins** | **No existe** | **Antes del deploy.** Propuesta: `express-rate-limit` (dependencia nueva, requiere tu OK), p. ej. 10 intentos por 15 min por IP + correo/teléfono; `trust proxy` ya está configurado para Render |
| CSRF del panel | Origin obligatorio en todo lo que cambia datos (probado) | En Render, `CORS_ORIGINS` = solo el dominio del panel |
| **Cookie entre dominios** | En producción, `Secure; SameSite=None` | **Riesgo:** si el panel y la API están en sitios distintos (p. ej. `*.vercel.app` y `*.onrender.com`), algunos navegadores bloquean esa cookie de terceros. **Recomendación:** panel y API bajo el mismo dominio (`panel.tudominio` / `api.tudominio`) o un proxy `/api` en el host del panel |
| Encabezados de seguridad | Solo `x-powered-by` desactivado | Propuesta: `helmet` (dependencia nueva) o encabezados mínimos a mano |
| Enumeración de cuentas | El login no revela si la cuenta existe (probado); el **registro** sí (409 `CORREO_EN_USO`) | Aceptable por usabilidad; el rate limiting lo mitiga |
| Contraseñas | bcrypt costo 12, mínimo 8 caracteres, máximo 72 bytes | — |
| Credenciales expuestas (D16) | Siguen sin rotar: contraseña de la BD y admin demo del historial de `Que-Limpiamos`, contraseña demo en el panel | **Antes del deploy:** rotar la contraseña de la BD, cambiar la del admin y quitar la del panel |
| Almacenamiento del token en las apps | No se guarda | `flutter_secure_storage` (dependencia Flutter nueva) |
| `npm audit --omit=dev` | 3 avisos de `effect` (dentro de la CLI de Prisma; sin arreglo compatible) | Vigilar actualizaciones de Prisma |
| Registro de intentos fallidos | No hay | Fase 6 (logs) |

## 4. Qué requiere la integración de la autenticación (lista de trabajo, sin implementar)
**Condición previa para probarla de punta a punta sin tocar producción:** una **BD de desarrollo** (p. ej. `queLimpiamos_dev`), distinta de producción y de la de pruebas automáticas. La debe crear el usuario, porque nuestra cuenta de BD no puede crear bases. Además, los secretos JWT en `.env`. Registrar cuentas desde las apps escribe en la BD: no debe hacerse contra producción.

### 4.1 App del cliente
| # | Cambio | Archivo |
|---|---|---|
| C1 | Dependencia **`flutter_secure_storage`** (requiere tu OK) para guardar el token | `pubspec.yaml` |
| C2 | `ApiClient`: agregar `Authorization: Bearer <token>`; ante 401 `SESION_EXPIRADA` o `TOKEN_INVALIDO`, cerrar sesión e ir al login; mostrar el `mensaje` de 403 `CUENTA_SUSPENDIDA` y de 429 (con el tiempo de espera) | `services/api_client.dart` |
| C3 | `AuthApi`: rutas `/api/cliente/auth/{login,registro,me,logout,cambiar-password}`; leer `{ token, cliente }` en vez de `estrella`; quitar `rol` | `services/api_client.dart` |
| C4 | `Session`: guardar y borrar el token; **al abrir la app** llamar a `GET /me` para restaurar la sesión; al salir, `POST /logout` y borrar el token | `services/session.dart`, `screens/profile_screen.dart` |
| C5 | Login con correo **o** teléfono (opcional; el backend acepta los dos) | `screens/login_screen.dart` |
| C6 | Estado de verificación y motivo del rechazo (D65) | Fase 3 (necesita los endpoints de documentos) |

### 4.2 App del trabajador
| # | Cambio | Archivo |
|---|---|---|
| T1–T4 | Lo mismo que C1–C4 con `/api/trabajador/auth/*` y `{ token, trabajador }`. `loginRemote` toma `id`, `nombre`, `correo` y `telefono` de `trabajador` | `services/api_client.dart`, `session.dart`, `app_state.dart` |
| T5 | **Registro:** agregar el campo **dirección** (obligatorio en la BD) | `screens/register_screen.dart` |
| T6 | **Quitar el login de demostración** (`AppState.login` con las credenciales de `MockData`) antes de producción | `services/app_state.dart` |
| T7 | La sincronización de solicitudes usa rutas viejas | Fase 4 |

### 4.3 Panel
| # | Cambio | Archivo |
|---|---|---|
| P1 | Al abrir: `GET /api/admin/auth/session`; ante un 401, borrar `sessionStorage` y mostrar el login | `App.tsx` |
| P2 | Cerrar sesión: `POST /api/admin/auth/logout` (con `credentials: "include"`) y después borrar la sesión local | `App.tsx` |
| P3 | `apiFetch`: lanzar un error si `!respuesta.ok` y, ante un 401, cerrar la sesión | `data/api.ts` |
| P4 | Arreglar el valor por defecto de `VITE_API_URL` (`http://localhost:3000`) | `data/api.ts` |
| P5 | Quitar la contraseña demo | `data/configuracion.ts` |
| P6 | Usar `/api/admin/auth/*` y después retirar el alias `/api/auth/admin` | `pages/LoginPage.tsx`, backend `app.ts` |
| P7 | Quitar la **asignación de solicitudes por el admin** (`/api/admin/solicitudes/:id/asignacion`; el admin no interviene, decisión v3). El listado llega en la Fase 5 | `data/SolicitudesProvider.tsx` |

### 4.4 Cómo se probará cada pieza
- **Backend:** ya probado (`npm test`).
- **Apps:**
  - prueba manual guiada contra la BD de desarrollo: registro, login, reapertura de la app, token vencido, logout, cuenta suspendida y bloqueo por intentos;
  - si se agregan, pruebas de widget del `ApiClient` con un servidor simulado.
- **Panel:** login, recarga con sesión válida, sesión vencida, logout y CSRF (que un origen ajeno falle).

## 5. Diseño propuesto: límite de intentos y bloqueo progresivo (aprobado; sin implementar todavía)
| Capa | Regla propuesta |
|---|---|
| **Por IP** (abuso general) | `login`: 30 peticiones por 15 min por IP; `registro`: 10 por hora; `cambiar-password`: 10 por 15 min. Respuesta 429 `DEMASIADOS_INTENTOS` con `Retry-After`. Con `express-rate-limit` (dependencia nueva, aprobada con esta decisión). Detrás del proxy de Render ya está `trust proxy` |
| **Por identificador** (fuerza bruta a una cuenta) | Clave = audiencia + correo o teléfono normalizado (y, si la cuenta existe, también su id, para que alternar correo y teléfono no duplique los intentos). **5 fallos gratis**; después, bloqueos de **1, 5, 15, 30 y 60 min** (tope). Se reinicia con un login correcto o tras 24 h sin fallos. **Nunca es permanente** |
| **Sin revelar cuentas** | El bloqueo aplica **igual** a correos o teléfonos que no existen. Se revisa **antes** de comprobar la contraseña: durante un bloqueo, ni la contraseña correcta entra (si no, el bloqueo serviría de oráculo). El mensaje es el mismo exista o no la cuenta: "Demasiados intentos. Intenta de nuevo en N minutos." |
| **Admin** | El mismo mecanismo, más estricto: 3 fallos gratis |
| **Dónde se guardan los contadores** | **En memoria** (Render corre una instancia): sin cambio de schema. Al reiniciar el servidor se pierden, lo que es aceptable. Si algún día hay varias instancias, se pasan a una tabla o a Redis sin cambiar las reglas |
| Registro | Sigue diciendo "correo en uso" (lo necesita la usabilidad); el límite por IP evita usarlo para enumerar en masa |
| Pruebas | Con reloj inyectable: el bloqueo llega al intento 6, crece y vence; el éxito reinicia; un correo inexistente recibe la misma respuesta; nunca pasa de 60 min; la IP también limita |

## 6. Actualización: integración realizada (2026-11-24, después de la corrección de D5) — prevalece sobre §1, §3 y §5
| Pieza | Implementado | Probado | Integrado (funciona con su consumidor) |
|---|---|---|---|
| **Límite de intentos** (por IP + bloqueo progresivo 1 → 5 → 15 → 30 → 60 min, nunca permanente; 3 intentos gratis en el panel y 5 en las apps; misma respuesta exista o no la cuenta) | Sí (`shared/auth/intentos.ts`, `shared/http/limites.ts`, `express-rate-limit`, MIT) | Sí: 6 pruebas del contador + 8 por HTTP | Sí en el panel (probado en el navegador). En las apps, implementado sin compilar |
| **Panel** — login (ruta nueva `/api/admin/auth/login`), sesión validada con el servidor al abrir, logout en el servidor, `apiFetch` que lanza errores y aviso global ante un 401, `VITE_API_URL` corregido, contraseña demo quitada | Sí | **Sí, de punta a punta en el navegador** contra el backend local (BD de pruebas): contraseña mala → mensaje; login → panel; la cookie **no** es visible desde JS; borrar `sessionStorage` y recargar → la sesión vuelve del servidor; logout → `POST /logout` 204, y al recargar ya no hay sesión; 5.º intento → "Demasiados intentos…" | **Sí** (ver la nota sobre el build) |
| **App del cliente** — `/api/cliente/auth/*`, token en `flutter_secure_storage`, `Authorization: Bearer`, restaurar la sesión al abrir (`GET /me`), logout en el servidor, 401 → bienvenida, login con correo o teléfono | Sí | **No**: no hay Flutter SDK en este equipo (`flutter` y `dart` no existen); ni compilado ni ejecutado | **Pendiente**: compilar y probar en emulador (§4.4) |
| **App del trabajador** — lo mismo con `/api/trabajador/auth/*`, **campo dirección** en el registro, la contraseña **ya no se guarda** en el teléfono (`shared_preferences`), registro de depuración solo en debug y **sin el token**, tarjeta "Cuenta de prueba" solo con `--dart-define=MODO_DEMO=true` | Sí | **No** (sin Flutter SDK) | **Pendiente** |
| **Almacenamiento local privado** (D5 v2) | Sí (`shared/almacenamiento/*`, sin dependencias) | Sí: 13 pruebas | Sin consumidor todavía (endpoints de la Fase 3c y la Fase 5) |
| **Demo local** (`npm run demo:local`) | Sí | Usada para la prueba del panel | Guía en `17_DEMO_LOCAL.md` |

**Nota sobre el build del panel:** el código **commiteado** del panel **no compila** (`tsc` con ~25 errores y `vite build` falla), por cambios en curso del equipo **ajenos a esta tarea**:
- `ResenasPage.tsx` está comentado a propósito ("ESPERANDO RESOLUCIÓN… CONSULTAR AL TEAM") y `DashboardPage` lo importa;
- los tipos `SolicitudListado`/`Solicitud` no coinciden;
- `TrabajadoresPage` usa variables que no existen.

No se tocaron. Para la prueba de punta a punta se usó una **copia temporal** del panel con un sustituto de `ResenasPage` solo en esa copia (ya borrada). Mis 4 archivos del panel no tienen errores de tipos. **Para demostrar el panel hace falta que el equipo resuelva `ResenasPage`.**

## 7. Cierre de la Fase 2 (2026-11-25) — prevalece sobre §6 y su nota sobre el build
| Pieza | Implementado | Probado | Compila | Integrado |
|---|---|---|---|---|
| **Panel original** (sin copias temporales): 22 errores resueltos, `ResenasPage` reactivada, reglas migradas a `SolicitudListado`, detalle de solicitud reconectado y peticiones sin sesión eliminadas (`18`) | Sí | Sí, en el navegador contra la demo local: login, sesión restaurada, logout, cookie httpOnly, CSRF por Origin (`18` §5) | **Sí**: `tsc` 0 errores y `npm run build` correcto | **Auth del admin: sí.** Solicitudes, reseñas, clientes y colaboradores: **no** (sin endpoints; Fases 3a y 5) |
| **App del cliente** | Sí | El usuario: `pub get`, `analyze`, `run`, `build apk --debug` OK | Sí (lo informó el usuario) | Compila y se ejecuta (lo informó el usuario). La lista funcional de `19` §4 (registro, sesión restaurada, bloqueo, etc.) no se ha informado punto por punto |
| **App del trabajador** | Sí | Lo mismo; 72 avisos *info*, sin cambios cosméticos | Sí (lo informó el usuario) | Igual que el cliente |
| **Backend** | Sí | **65/65** pruebas y typecheck OK (repetidos el 2026-11-25; el backend no cambió en este cierre) | — | — |
| **Reseñas y reportes** | **Solo la especificación** (`20`) y la estructura del panel | — | — | **Fase 3a** |

**Pendientes que no son de código:**
- **D63:** la cuenta del propietario sigue sin confirmar. **No se asignó ningún permiso**, tampoco a la cuenta demo ID 1.
- **D16:** las credenciales expuestas siguen sin rotar (antes del deploy).
- **`VITE_API_URL`** en los `.env` locales del panel: lo revisa el equipo (`18` §4).
- **D24:** el equipo decide si quita del detalle los botones de asignar, confirmar, finalizar y cancelar (`18` §3).

**Lo que no cambia:**
- `/api/admin/solicitudes` y `/asignacion` siguen sin existir (Fase 5; la asignación por el admin está descartada).
- Las apps siguen usando rutas viejas para solicitudes y avisos (Fases 3 y 4).
- Si al abrir una app no hay conexión, la sesión no se restaura y se vuelve a la bienvenida (el token se conserva para el siguiente intento).
