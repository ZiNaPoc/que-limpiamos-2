# 26 — Informe de cierre de la Fase 3 (2026-11-25) — FASE 3 COMPLETADA (aprobada por el usuario)

- **Estado:** Fase 3 **COMPLETADA** (2026-11-25). El usuario aprobó los 2 puntos de §5: E1 se corrigió y pasa, y el alcance se confirmó (ver §6).
- **Alcance de esta fase:**
  - 3a: reseñas, reportes, moderación y permisos (backend y panel);
  - 3b: reseñas y reportes en las apps;
  - ciclo de las solicitudes sin dinero, con «Mis inmuebles», panel y apps (doc `25` v2).
- **Sin cambios en producción**, sin commits ni despliegues. Datos históricos intactos. El reporte abierto de la S3 **no se tocó**: sigue ABIERTO, sin resolución.

## 1. Qué quedó implementado
| Parte | Contenido | Doc |
|---|---|---|
| 3a — backend y panel | Reseñas en las dos direcciones (1–5, 168 h, una por rol, autor oculto); reportes con fotos privadas; moderación con auditoría inmutable; permisos con propietario y sin auto-otorgamiento; BD local TiDB (000 + 002 v10 + 003 v2) | `20`, `21`, `22` |
| 3b — apps | Historial real, calificar, reportar con fotos, mis reseñas y reportes, reputación del cliente, selección manual con estrellas | `23` |
| Ciclo sin dinero | SQL 004; backend (catálogo, cotización, «Mis inmuebles», invitación o bolsa, aceptar o rechazar, cancelar sin cargo, ventana de inicio ±30 min, terminar con fotos, confirmación, D54, vencimiento con `VENCIDA`, resolución inmutable, supervisión, avisos); panel (supervisión, «requieren atención», resolver, Permisos); las dos apps conectadas | `25` |

## 2. Qué se probó
| Componente | Automático | Manual |
|---|---|---|
| Backend | Typecheck 0 errores; `npm test` **166/166** (33 del ciclo) | Integrales por la IP de la Wi-Fi contra el servidor real: todas OK (`24` §7) |
| SQL 004 | Ensayo **19/19** en `quelimpiamos_pruebas` (incluye el rollback) | En `quelimpiamos_dev`: respaldo previo; 72 de 74 filas históricas idénticas, y las 2 distintas son cambios explicados (`25` §10) |
| Panel | `tsc -b` 0; build OK; lint con los **13 errores de antes** (ninguno nuevo) | Revisado en el navegador con la sesión del propietario de prueba (`25` §11) |
| App del cliente | `analyze` sin issues; `flutter test` **29/29**; APK debug OK | **Validada por el usuario en su teléfono (2026-11-25):** navegación y funciones sin problemas |
| App del trabajador | `analyze` con los **72 info de siempre** (0 errores, 0 advertencias); `flutter test` **25/25** tras corregir E1 (antes 24 OK + 1 que ya fallaba); APK debug OK | **Validada por el usuario en su teléfono (2026-11-25):** navegación y funciones sin problemas |
| Fase 3b | — | Validada por el usuario en el teléfono (2026-11-25) |

**Sin probar en vivo:** D54 (confirmación automática y por evidencia) tarda horas. Lo cubren las pruebas automáticas con el reloj controlado. El vencimiento sí se probó en vivo.

## 3. Errores pendientes
| # | Error | Origen | Impacto | Propuesta |
|---|---|---|---|---|
| E1 | `app_trabajador/test/app_state_test.dart` «Flujo completo… aceptar → proponer…» falla: `Expected: null, Actual: Future<String?>` | **Preexistente:** está así desde el primer commit del repositorio (copia del hackathon). `acceptOpportunity` ya era asíncrona y la prueba no la espera (`await`) | Ninguno en la app: es la **prueba** la que quedó desactualizada; el método funciona (la aceptación se usó en el teléfono) | Hacer la prueba `async` y esperar el resultado (`expect(await s.acceptOpportunity('r1'), isNull)`), sin cambiar lo que verifica. **Requiere tu autorización** (regla: no tocar pruebas sin informar) |
| E2 | Lint del panel: 13 errores | Preexistentes (`CatalogoContext`, `ClientesContext`, `TrabajadoresContext`, `AvisoTemporal`, `useAtrapaFoco`, `MenuLateral`) | No impiden compilar ni el build | Fuera del alcance de la Fase 3 |
| E3 | `analyze` del trabajador: 72 avisos *info* | Preexistentes (estilo) | Ninguno | Fuera del alcance |

No hay errores **nuevos** abiertos.

## 4. Pendientes que NO son errores
**Fuera del alcance por decisión del usuario:**
- **Dinero:** pago en efectivo, comisión, cargos y compensaciones, descuentos, adeudos y resolución del pago (doc `15` §2 "3b" original). Decidido: "ciclo sin dinero" (`09`).
- **Documentos e INE:** subida y revisión (doc `15` §2 "3c"). Mientras tanto, el cliente ficticio está verificado solo en local.
- **Horarios:** D17.
- **Otros:** chat, tarjeta (D50) y negociación (pospuestos).

**Del plan original del doc `15` que no se hizo:**
- **Perfil del cliente:** `GET/PATCH /api/cliente/perfil`, con el estado de la INE y el motivo de rechazo (D65). Depende de los documentos (3c).

**Decisiones abiertas** (no bloquean lo local):
- **D63b:** si el propietario recibe también los permisos de incidencias e identidad.
- **D64:** junto con las tablas de documentos del 003 v2.
- **D5a:** proveedor de almacenamiento.
- **D16:** rotación de credenciales.

**Producción:**
- aplicar 002 v10 + 003 v2 + 004 (en ese orden; el 004 con una ventana sin escrituras en `admin_permisos`);
- la cuenta real del propietario (D63a), que no existe en producción.

Todo eso requiere autorización explícita.

**Técnico:**
- el historial del cliente consulta el detalle de cada solicitud una por una (conviene agruparlo antes de producción);
- el bloqueo progresivo de inicios de sesión guarda su estado en la memoria del proceso: se pierde al reiniciar el servidor y no se comparte entre instancias. Hay que revisarlo antes del despliegue (Fase 7). El límite por IP ya usa `express-rate-limit`.

**Notas de los docs anteriores ya superadas:**
- `08` "Fase 3a": "Apps … **No compilado**" → se compiló en la 3b;
- "Asignación inicial al propietario … No realizada" → hecha en local con la cuenta de prueba del correo de D63a (no en producción).

## 5. ¿Se puede considerar terminada la Fase 3?
**Lo implementado y autorizado está completo y validado:** backend, panel y las dos apps funcionan, pasaron las pruebas automáticas y las manuales (en el teléfono y en el navegador), y no hay errores nuevos.

**No se marca COMPLETADA** porque la condición era "si todas las verificaciones están satisfechas", y faltan dos cosas:
1. **E1:** una prueba automática de la app del trabajador sigue fallando. Es preexistente y no afecta a la app, pero no pasa. Propuesta: autorizar la corrección de la prueba (solo el `await`).
2. **Alcance:** confirmar que el **perfil del cliente**, el **dinero** y los **documentos e INE**, que el doc `15` incluía en la Fase 3, pasan formalmente a fases posteriores.

Si apruebas los dos puntos (y E1 queda corregido y en verde), la Fase 3 se marca **COMPLETADA** en `08` y en este documento.

**La siguiente fase del doc `25` no ha empezado.**

## 6. Cierre aprobado (2026-11-25)
El usuario aprobó los dos puntos.

**E1, corregido:**
- en `app_trabajador/test/app_state_test.dart`, las dos llamadas a `acceptOpportunity` ahora se esperan (`await`) y las pruebas son `async`. Lo que verifican no cambió;
- la del «Flujo completo» (línea 20) era la que fallaba;
- la de «sin disponibilidad» (línea 72) pasaba por una razón equivocada, porque una `Future` nunca es nula; ahora comprueba de verdad el mensaje de error.

**Resultado:**
- `flutter test` de la app del trabajador: **25/25**;
- `analyze`: los mismos 72 avisos *info*, sin errores ni advertencias.

**Alcance confirmado:** el perfil del cliente, el dinero y los documentos e INE pasan formalmente a fases posteriores (`09`, sección "Cierre de la Fase 3").

**Estado final de las pruebas:**
- backend 166/166;
- app del cliente 29/29;
- app del trabajador 25/25;
- panel con build OK y lint sin errores nuevos;
- ensayo del SQL 004: 19/19.

**Se mantiene:**
- sin producción, commits ni despliegues;
- datos históricos intactos;
- el reporte abierto de la S3, sin tocar.
