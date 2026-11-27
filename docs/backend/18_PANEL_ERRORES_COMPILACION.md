# 18 — Panel: los 22 errores de compilación (RESUELTOS en el panel original)

- **Versión 2 · fecha:** 2026-11-25 · **Estado:** **resueltos** en el árbol original de `limpiandotuhogar/appWeb`, sin copias temporales. El usuario autorizó reactivar `ResenasPage` y corregir los problemas de integración y tipado relacionados.
- **Verificado:**
  - `npx tsc -p tsconfig.app.json --noEmit` → **0 errores** (antes 22);
  - `npm run build` (`tsc -b && vite build`) → **compila** (67 módulos, 383 kB de JS);
  - **en el navegador**, contra el backend local (`npm run demo:local`, BD de pruebas), se probaron login, restauración de sesión, logout, cookie httpOnly y CSRF (§5).
- **Reglas que se siguieron:**
  - no se quitó ninguna función para que compile;
  - las acciones sin endpoint conservan su diseño y su dependencia queda documentada (§3);
  - no hay datos inventados.
- Esta versión reemplaza a la 1 (que solo documentaba los errores y una propuesta). La lista original de los 22 errores se conserva en §2, junto a su solución.

## 1. Causa de fondo (sin cambios)
El panel estaba a mitad de una migración: el contexto ya usaba el tipo de la API, **`SolicitudListado`**, pero varios componentes seguían con el tipo de demostración **`Solicitud`**. Además, `ResenasPage` estaba comentada de forma temporal por el equipo, y eso rompía el build.

**Decisión de diseño aplicada:** el panel trabaja con **`SolicitudListado`**, el contrato de la API, en todas partes:
- las reglas de `utils/reglasDeSolicitudes.ts` reciben `SolicitudListado` (`idTrabajador`, `idServicio`, `idCliente`, `fechaCreacion`);
- `obtenerEtapa` y `estaActiva` reutilizan las reglas de la lista (`obtenerEtapaListado`, `estaActivaListado`), que ya cubrían "En proceso" y "Rechazado";
- el detalle usa el tipo nuevo **`SolicitudDetalle`** (`data/tipos.ts`) = `SolicitudListado` + los campos que solo dará el endpoint de detalle (`modoDeEleccion`, `cancelacion`, `evidencias`), todos **opcionales**. Si faltan, la pantalla muestra "Sin dato (pendiente del backend)" en vez de inventarlos;
- `Solicitud` (demo) sigue en `tipos.ts` porque `data/solicitudesDemo.ts` lo usa (ese archivo no lo importa nadie). Se puede retirar cuando el equipo lo decida.

## 2. Los 22 errores y su solución
| # | Archivo:línea (original) | Error | Solución |
|---|---|---|---|
| 1 | `pages/DashboardPage.tsx:10` | `./ResenasPage` no exportaba `ResenasPage` (rompía el build) | **`ResenasPage` reactivada** con el diseño original (indicadores, reputación por colaborador, filtros, lista), conectada a `data/resenas.ts`. Sin endpoint muestra "pendiente de conexión" y no usa datos de ejemplo. Ver `20` §9 |
| 2–4 | `components/solicitudes/DetalleDeSolicitud.tsx:138` | Faltaban `confirmarServicio`, `finalizarServicio` y `cancelarSolicitud` en el contexto | Se **añadieron al contexto** como acciones asíncronas que hoy responden `{ exito: false, mensaje }` **sin llamar al servidor** (§3). Los botones y sus ventanas de confirmación se conservan |
| 5–6 | `DetalleDeSolicitud.tsx:160`, `:186` | `SolicitudListado[]` no era `Solicitud[]` | Reglas migradas a `SolicitudListado` |
| 7 | `DetalleDeSolicitud.tsx:201` | Promesa usada como resultado (faltaba `await`) | `ejecutarAccion` ahora es `async` y espera cada acción |
| 8 | `pages/CatalogoPage.tsx:183` | `idDelServicio` → `idServicio` | Corregido |
| 9–12 | `pages/InicioPage.tsx:313`, `:388`, `:391`, `:397` | `SolicitudListado` frente a `Solicitud` | Tarjetas tipadas con `SolicitudListado`. El cliente y el colaborador se toman de la propia solicitud de la API (`solicitud.cliente.nombre`, `solicitud.trabajador`) en vez de la lista demo |
| 13–14, 20 | `pages/TrabajadoresPage.tsx:89`, `:94`, `:543` | ídem | `TrabajadoresContext` (`editarTrabajador`, `cambiarEstadoDelTrabajador`) recibe `SolicitudListado[]` |
| 15–19 | `TrabajadoresPage.tsx:169`, `:214`, `:220` (×2), `:261` | `reputacion`, `calificaciones` y `calcularReputacion` no existían | La reputación y las "Últimas calificaciones" salen de las **reseñas** (`calcularReputacionDelTrabajador` y `ultimasResenasDelTrabajador` en `data/resenas.ts`). Sin reseñas conectadas se lee "Reseñas sin conectar", **no** "Sin calificaciones": así no se afirma algo que no se sabe |
| 21 | `utils/consultasDeTrabajadores.ts:11` | `Solicitud` importado y sin usar | Quitado. También se quitó el `calcularReputacion` comentado, basado en un campo que la API no tiene; un comentario indica dónde está ahora |
| 22 | `consultasDeTrabajadores.ts:68` | `SolicitudListado` frente a `Solicitud` | Resuelto al migrar `estaActiva` |

## 3. Acciones que conservan su diseño pero dependen del backend
| Acción en el panel | Estado hoy | Dependencia |
|---|---|---|
| Lista de solicitudes (`GET /api/admin/solicitudes`) | El panel la pide; el backend responde **404** y la pantalla muestra "No se pudieron cargar las solicitudes" con "Reintentar" | Endpoint de la **Fase 5** |
| Detalle de una solicitud | **Se volvió a conectar** en `SolicitudesPage`: Inicio, Colaboradores y Reseñas navegan con `idDeSolicitud`, que antes se ignoraba. Se abre si la solicitud está en la lista cargada; si no, se avisa | `modoDeEleccion`, `cancelacion` y `evidencias` llegarán con `GET /api/admin/solicitudes/:id` (Fase 5) |
| Asignar o cambiar colaborador (`PATCH …/asignacion`, código del equipo) | Llama a un endpoint inexistente y muestra el error | **D24 (v3): el admin no asigna.** El equipo debe decidir si se quita el botón |
| Confirmar, finalizar y cancelar desde el panel | Botones conservados; al confirmar muestran "Esta acción todavía no está conectada…" sin llamar al servidor (`SolicitudesProvider.accionSinEndpoint`) | **D24:** el admin no interviene entre cliente y trabajador. **Decisión del equipo:** quitar los botones o definir endpoints. No se quitaron porque la instrucción fue no eliminar funciones |
| Reseñas, reputación y moderación | Pantalla y estructura listas; interruptor `RESENAS_CONECTADAS_AL_BACKEND = false` | **Fase 3a**, especificación en `20` |
| Clientes, colaboradores y catálogo | Siguen con datos de demostración en el navegador (insignia "Datos de demostración") | Fase 5 |

## 4. Otros problemas de integración encontrados y corregidos
- **Peticiones sin sesión:** `main.tsx` montaba un segundo `SolicitudesProvider` además del de `DashboardPage`, y por eso la landing y el login pedían `/api/admin/solicitudes` sin estar autenticados. Se quitó el de `main.tsx`; todos los consumidores están dentro del panel. Comprobado en el navegador: sin sesión solo se pide `/auth/session`.
- **Actualización 2026-11-25 — resuelto:** `appWeb/.env.local` (ignorado por git) ahora tiene `VITE_API_URL=http://localhost:3000` (antes `http://localhost:5173/`, el propio panel con barra final). `appWeb/.env` (también ignorado) apunta al backend desplegado y **no se tocó**: Vite da prioridad a `.env.local`. `api.ts` quita las barras finales y se creó `appWeb/.env.example`. Verificado en el navegador: el panel llama a `http://localhost:3000/api/...` y el login responde 200.
  - **Ojo:** Vite también lee `.env.local` en `npm run build`, así que un build hecho en esta PC apunta al backend local. El build de despliegue debe hacerse sin ese archivo, o con `VITE_API_URL` definida en la plataforma.
  - **Backend local:** puerto **3000** (`PORT` de `backend/.env`; su `CORS_ORIGINS` ya incluye `http://localhost:5173`). `npm run dev` **no arranca** porque `backend/.env` no tiene `JWT_SECRET_*` ("Falta la variable de entorno JWT_SECRET_CLIENTE"). Hoy se levanta con `npm run demo:local`, que usa secretos temporales y la BD de pruebas. Para `npm run dev` hay que agregar los tres secretos (`.env.example`); eso lo hace el usuario.
- *(Texto anterior)* **`VITE_API_URL` en los `.env` locales del equipo** (`appWeb/.env` y `.env.local`, ignorados por git; **no se leyó su valor**): con ellos, el panel enviaba las peticiones a su propio origen (`http://localhost:5173//api/...`), y como no hay proxy en Vite, el backend nunca las recibía. Para la prueba se arrancó Vite con `VITE_API_URL=http://localhost:3000` en el entorno del proceso, que tiene prioridad sobre `.env`, **sin modificar** esos archivos. **Acción del equipo:** revisar ese valor (en local debe ser `http://localhost:3000` o quitarse para usar el predeterminado).

## 5. Prueba en el navegador (panel original, backend local, BD de pruebas)
| Paso | Resultado |
|---|---|
| Abrir el panel sin sesión | Landing; `GET /auth/session` → 401; ninguna otra petición |
| Login con la cuenta admin de la demo | `POST /api/admin/auth/login` 200 → panel ("Bienvenido de nuevo") |
| Cookie | `document.cookie` vacío: `ql_admin` **no** es visible desde JavaScript |
| Reseñas | "Pendiente de conexión con el backend", sin datos y **sin** peticiones a `/api/admin/resenas` |
| Solicitudes | Mensaje de error claro (404 de la Fase 5) con "Reintentar" |
| Colaboradores (ficha) | Reputación: "Pendiente: reseñas sin conectar al backend (Fase 3a)" |
| Recargar con la sesión activa | `GET /auth/session` 200. El botón dice "Mi panel" y abre el panel **sin** pedir la contraseña |
| Logout | `POST /logout` 204. Al recargar, `/session` → 401 y el botón vuelve a "Acceder" |
| CSRF y cookie (por HTTP) | login con Origin ajeno o sin Origin → 403; con el Origin del panel → 200 y cookie `HttpOnly; SameSite=Lax; Max-Age=28800`; el token **no** va en el JSON; logout con Origin ajeno → 403 (la sesión sigue); con el del panel → 204 y la cookie se borra |

**Observación menor:** el navegador marca el `POST /logout` (204) como `ERR_ABORTED`. El servidor sí cierra la sesión: la recarga siguiente da 401. Probablemente se debe a que la pantalla cambia mientras termina la petición. No afecta el funcionamiento.

## 6. Lo que queda (no bloquea la compilación)
- **Lint:** `npx eslint src` da **13 errores que ya existían**, en archivos del equipo:
  - `react-refresh/only-export-components` en `CatalogoContext`, `ClientesContext` y `TrabajadoresContext`;
  - `react-hooks/refs` en `AvisoTemporal` y `useAtrapaFoco`;
  - `no-useless-assignment` en `MenuLateral`.

  **0 errores** en los archivos nuevos (`data/resenas.ts`, `ResenasContext.ts`, `ResenasProvider.tsx`, `pages/ResenasPage.tsx`). El build no ejecuta el lint.
- `InicioPage` no distingue entre "0 solicitudes" y "no se pudieron cargar" (sin la Fase 5 muestra 0). Se sugiere mostrar el `errorCarga` del contexto, igual que Solicitudes.
- El panel no tiene ejecutor de pruebas automáticas: su verificación es `tsc`, el build y la prueba en el navegador.
