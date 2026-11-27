# 23 — Fase 3b: reseñas y reportes en las apps Flutter

- **Fecha:** 2026-11-25 · **Estado:** **implementada.** Las dos apps compilan (APK debug), pasan `flutter analyze` sin errores ni advertencias, y sus pruebas nuevas pasan. Backend 133/133.
- **Flutter SDK:** `C:\Users\lolil\flutter` (Flutter 3.47.5, Dart 3.13.4). No está en el `PATH`: usar `C:\Users\lolil\flutter\bin\flutter.bat`.
- **Bloqueo inicial (resuelto con autorización del usuario):** las apps no tenían de dónde sacar el id real de una solicitud. Se agregaron **tres endpoints de solo lectura**, sin cambios de SQL.

## 1. Backend (autorizado el 2026-11-25; sin migraciones)
| Endpoint | Qué devuelve | Reglas |
|---|---|---|
| `GET /api/cliente/solicitudes` | Solicitudes del cliente:<br>• `id`, `estado`, fechas, `servicio`, `direccion`;<br>• `trabajador {id, nombre}`;<br>• `miResena`, `calificarHasta`;<br>• `puedeCalificar`, `puedeReportar` | Solo las suyas. Sin correo ni teléfono del trabajador. **No incluye** las reseñas que el cliente recibió (V5) |
| `GET /api/trabajador/solicitudes` | Solicitudes **asignadas** e **invitaciones vigentes** (`PENDIENTE`/`ACEPTADA`):<br>• `relacion`, `invitacion`;<br>• `cliente {nombre}`;<br>• `miResena`;<br>• `puedeCalificar`, `puedeReportar`, `puedeVerReputacionCliente` | Un invitado no califica ni reporta. Sin correo ni teléfono del cliente |
| `GET /api/cliente/trabajadores?servicioId=` | Selección manual: `id`, `nombre`, `especialidades`, `reputacion` | **Decidido:** solo `ACTIVO` y `VERIFICADO`. Con `servicioId`, solo quienes tienen **todas** las especialidades que exige el servicio. El horario se valida al crear la solicitud |

`puedeCalificar` y `puedeReportar` son **indicaciones para la interfaz**: el servidor vuelve a validar todo al calificar o reportar.

Código: `src/dominio/solicitudes.ts`, `src/modules/{cliente,trabajador}/solicitudes/routes.ts`.

Pruebas: `test/solicitudes.test.ts` (10).

## 2. App del cliente
| Pantalla | Qué hace | Endpoint |
|---|---|---|
| **Historial** (`historial_screen.dart`, antes con datos de ejemplo) | Servicios reales:<br>• actual y próximos;<br>• pasadas con su estado;<br>• "Calificar" solo si el servidor lo permite, con la fecha límite;<br>• "Reportar" desde la hora programada;<br>• la calificación ya dada.<br>Estados de carga, vacío y error con reintento | `GET /api/cliente/solicitudes` |
| **Calificar** (`rate_screen.dart`, antes simulada) | 1–5 escobas, comentario de hasta 500 con contador, validación previa. Evita el doble envío. Si el servidor dice que no se puede (finalizado, 168 h, duplicado), lo muestra y deshabilita el botón | `POST …/solicitudes/:id/resena` |
| **Reportar** (`reportar_screen.dart`, nueva) | Tipo, descripción y hasta 5 fotos de la cámara o la galería. Valida el tipo real por los bytes, 8 MB por foto y 16 MB en total al agregar y al enviar. Muestra un error si la foto no se carga y el progreso de envío | `POST …/solicitudes/:id/reportes` (multipart) |
| **Mis reseñas** / **Mis reportes** + detalle con fotos (`mis_resenas_reportes_screen.dart`) | Historial propio (corregida o retirada por moderación); el reporte con su estado y sus fotos por URL temporal | `GET /api/cliente/resenas`, `/reportes`, `/reportes/:id`, `/reportes/:id/evidencias/:id` |
| **Avisos** (`avisos_screen.dart`, antes con la ruta obsoleta `/hoyo-negro`) | Servicios con colaborador. La tarjeta "Califica tu servicio" solo aparece cuando el servidor lo permite (o ya calificaste) | `GET /api/cliente/solicitudes` |
| **Colaboradores** y su perfil (`collaborators_screen.dart`, `collaborator_profile_screen.dart`, antes con datos de ejemplo) | Lista real con **estrellas y promedio**. El perfil muestra las reseñas **anónimas** (calificación, comentario y mes/año) | `GET /api/cliente/trabajadores`, `/trabajadores/:id/resenas` |
| Perfil | Accesos a "Mis reseñas" y "Mis reportes" | — |

- Servicios: `lib/services/historial_api.dart`, `validaciones_contenido.dart` y `resenas_reportes_api.dart` (este último es el de la Fase 3a, **reutilizado**).
- Dependencia nueva: `image_picker ^1.1.2`, la misma que ya usa la app del trabajador. `Info.plist` de iOS lleva los textos de cámara y galería.

## 3. App del trabajador
Su historial local, que sirve al modo demostración y a las rutas antiguas, **no se tocó**. Se le agregó arriba un acceso a **"Mis servicios"** (datos reales) y los atajos "Mi reputación", "Reseñas que escribí" y "Mis reportes" (`history_screen.dart`).

| Pantalla (`servicios_resenas_screens.dart`) | Endpoint |
|---|---|
| **Mis servicios**: asignados e invitaciones, con "Calificar", "Reportar" y "Reputación del cliente" según lo que permite el servidor | `GET /api/trabajador/solicitudes` |
| **Calificar al cliente**: igual que en el cliente (validación, doble envío, no elegible) | `POST …/solicitudes/:id/resena` |
| **Reportar**: incluye "No recibí el pago" (`PAGO_EN_DISPUTA`, solo dentro del plazo D61; lo valida el servidor) | `POST …/solicitudes/:id/reportes` |
| **Reputación del cliente**: si el servidor responde 403, se muestra el aviso y no hay datos | `GET …/solicitudes/:id/reputacion-cliente` |
| **Mi reputación** (reseñas recibidas, anónimas, con promedio), **Reseñas que escribí**, **Mis reportes** y su detalle con fotos | `GET /api/trabajador/resenas/recibidas`, `/resenas`, `/reportes[/:id]`, evidencias |

## 4. Pruebas y verificación
| Comprobación | App del cliente | App del trabajador |
|---|---|---|
| `flutter pub get` | OK | OK |
| `flutter analyze` | **No issues found** | **72 info, 0 errores, 0 advertencias**: los mismos 72 de antes, ninguno de código nuevo |
| `flutter test` | **22/22** | **18/19**: falla `app_state_test` "Flujo completo…", **del equipo y anterior a esta fase** (espera que `acceptOpportunity` sea síncrono y `app_state.dart` lo hace asíncrono; ninguno de los dos archivos se tocó) |
| `flutter build apk --debug` | **OK** (`app-debug.apk`) | **OK** (`app-debug.apk`) |
| Backend `npm test` | 133/133 (incluye 10 nuevas) y typecheck OK | |

**Escenarios cubiertos por las pruebas nuevas de las apps** (`test/resenas_reportes_test.dart` en las dos):
- reseña válida, sin comentario y con comentario largo (501; 500 sí);
- servicio no elegible (409 con su código → mensaje y botón bloqueado);
- **doble envío** (dos toques → una sola petición);
- error HTTP (500 y sin conexión);
- **sesión expirada** (401 → `onSesionVencida`);
- reporte sin fotos y con fotos (multipart, campo `fotos`, extensión real);
- foto de más de 8 MB, exceso de fotos y más de 16 MB, rechazados **antes** de enviar;
- tipo no permitido;
- historial vacío;
- 403 en la reputación del cliente.

El servidor de estas pruebas es simulado **solo dentro de la prueba** (`http.runWithClient`); las pantallas finales usan la API real.

**Arreglo de una prueba que ya fallaba:** el `widget_test` del splash del cliente fallaba desde la Fase 2, porque la sesión se lee del almacenamiento seguro. Ahora la prueba lo simula vacío.

## 5. Pendiente (fuera de esta fase)
- **Sin ejecutar en un dispositivo o emulador** contra el backend: está compilado y probado con pruebas automáticas, pero no se usó en un teléfono.
- La **creación** de solicitudes en las dos apps sigue usando las rutas obsoletas (`/galaxias`, `/hoyo-negro`): es la siguiente parte de solicitudes y dinero, y requiere sus propios endpoints.
- La lista de colaboradores no tiene horarios (el backend no los entrega en esta lista). El filtro "Mañana/Tarde" solo aparece si existen.
- La prueba `app_state_test` del equipo (ver §4).
