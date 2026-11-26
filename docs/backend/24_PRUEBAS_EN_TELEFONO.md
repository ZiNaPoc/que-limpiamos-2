# 24 — Pruebas manuales en un teléfono Android contra el backend local

- **Fecha:** 2026-11-25 · Solo para pruebas locales. Producción, TiDB Cloud y `.env` **sin cambios**.
- **Base de datos:** `quelimpiamos_dev` en el TiDB **local** (Docker, `127.0.0.1:4000`). El teléfono **nunca** ve la BD: el puerto 4000 solo escucha en la PC.

## 1. Piezas (nuevas, solo para pruebas locales)
| Pieza | Qué hace |
|---|---|
| `npm run servidor:local` (`src/scripts/servidor-local.ts`) | Arranca el backend contra `quelimpiamos_dev`. **Antes de escuchar** verifica host `127.0.0.1`, puerto `4000`, nombre de la BD, sin TLS y que el servidor sea TiDB local, no Serverless. Escucha **solo** en `127.0.0.1` y en la IP **privada** de la Wi-Fi (no en `0.0.0.0`). Rechaza IP públicas. Se niega a correr con `NODE_ENV=production`. Los datos se **conservan** entre reinicios |
| `npm run datos:local` (`src/scripts/datos-prueba-local.ts`) | Datos de prueba **idempotentes**: solo crea lo que falta y no borra nada. Hace la misma verificación del destino antes de escribir. **No crea solicitudes** |
| `src/scripts/lib/entorno-servidor-local.ts` | Fija la BD local antes de cargar la configuración. Si `.env` no trae los secretos JWT y de firma, los genera **una vez** en `backend/.local/secretos-servidor-local.json`, así las sesiones del teléfono sobreviven a los reinicios. Las fotos van a la carpeta por defecto del backend, `%USERPROFILE%\.quelimpiamos\almacenamiento`, **fuera** del repo (el backend rechaza a propósito una carpeta dentro de git) |
| `src/scripts/lib/destino-local.ts` | La verificación del destino que usan los dos scripts |
| Regla de firewall de Windows **"Que Limpiamos backend local (pruebas)"** | Entrada TCP **3000**, solo perfil **Privado**, solo desde la **subred local** |

`backend/.local/` está en `.gitignore`.

## 2. Datos de prueba (`npm run datos:local`)
- **Especialidades:** Limpieza general, Limpieza profunda y Limpieza post-obra.
- **Servicios activos:** los 3 que muestra la app del cliente, con los mismos nombres, textos y precios (400, 600 y 650). Cada uno tiene su especialidad exigida y su fila de `servicio_calculo`, con incrementos en 0 como en el 002 F3.
- **Áreas y extras:** los inserta el esquema 002 (F1 y F2). El script solo completaría los que faltaran.
- **Cuentas ficticias** (dominio `.test`):
  - `cliente.prueba@quelimpiamos.test`;
  - `trabajador.prueba@quelimpiamos.test`: **ACTIVO y VERIFICADO**, con las 3 especialidades y los 3 servicios, para que aparezca en la selección manual.
- **Contraseñas:** se generan **solo al crear** cada cuenta y quedan en `backend/.local/cuentas-prueba-local.json`. Volver a ejecutar el script **no las cambia**. `--restablecer-claves` genera otras, solo para estas dos cuentas.
- **Horarios:** no se siembran, porque la convención de `dia_semana` sigue pendiente (D17) y ninguna pantalla actual los lee.

## 3. APK para el teléfono
Se compilan con la URL en un `--dart-define` de la compilación, **sin tocar el código** (por defecto queda `10.0.2.2`, la del emulador):
```
flutter build apk --debug --dart-define=API_URL=http://<IP-de-la-PC>:3000
```
Si la IP de la PC cambia (por DHCP o al cambiar de red), hay que recompilar con la nueva.

### Verificado el 2026-11-25 (PC con IP `192.168.0.78`)
- **El servidor** escucha solo en `127.0.0.1:3000` y `192.168.0.78:3000`; por la interfaz de WSL no responde.
- **Desde la PC, por la IP de la Wi-Fi:**
  - el inicio de sesión del cliente y del trabajador de prueba dan 200;
  - la selección manual muestra al trabajador de prueba, con y sin `servicioId` (ids de los servicios: 30001, 30002 y 30003; TiDB no los asigna consecutivos);
  - el historial de los dos está vacío (0 solicitudes);
  - sin sesión da 401;
  - `/hoyo-negro` da 404.
- **CORS:** las apps nativas no envían `Origin`, así que no les aplica. Un `Origin` ajeno no recibe `Access-Control-Allow-Origin`.
- **Las APK** llevan compilado `http://192.168.0.78:3000`. El `10.0.2.2` que aparece dentro del APK debug es solo el código fuente que Flutter guarda para depurar, igual que el comentario con `192.168.1.50`.
- **Datos:** la segunda ejecución de `datos:local` no creó ni cambió nada.

## 4. Crear solicitudes desde la app — RESUELTO (doc `25` v2)
Hasta la Fase 3b, las dos apps usaban las rutas obsoletas `/galaxias` y `/hoyo-negro` (404). Desde el 2026-11-25 usan las rutas del ciclo (`06`, sección "Ciclo de las solicitudes sin dinero"); ver §7. Las solicitudes ficticias de §5 se conservan.

## 5. Solicitudes ficticias (`npm run solicitudes:local`, autorizado el 2026-11-25)
Sirven para probar calificar y reportar mientras no exista la creación real. El script es **idempotente**:
- cada solicitud lleva en `notas` la marca `[prueba-telefono:S1|S2|S3]`, y si ya existe no se crea ni se toca;
- la reseña de S2 solo se crea si no existe.

Verifica el destino como los otros scripts y requiere antes `npm run datos:local`.

| Clave | Id (2026-11-25) | Servicio | Estado | Fechas (UTC) | Calificar | Reportar |
|---|---|---|---|---|---|---|
| S1 | 1 | Limpieza regular | REALIZADO | programada 2026-11-24 18:34; finalizada 22:34 | **Cliente y trabajador**, hasta 2026-12-01 22:34 | Los dos |
| S2 | 2 | Limpieza profunda | REALIZADO | programada 2026-11-23 18:34; finalizada 2026-11-24 00:34 | **Solo el trabajador**, hasta 2026-12-01 00:34. El cliente ya calificó (5 escobas, creada con `crearResena`) | Los dos |
| S3 | 3 | Limpieza post-obra | CONFIRMADO (sin iniciar) | programada 2026-11-25 20:14 | Nadie (no ha finalizado) | Los dos, con fotos desde la app |

**Coherencia con las reglas:**
- REALIZADO se alcanza por **confirmación automática** (D54, `realizado_via = AUTOMATICO`): se pide confirmar en T+30 min y se confirma solo en T+60 min. En ese caso el pago **no se libera**, así que no corresponde ningún movimiento.
- Cada solicitud tiene:
  - historial de estados;
  - la invitación ACEPTADA (selección manual);
  - las especialidades que exige el servicio y algunas áreas;
  - los precios aplicados (precio base y 85 % para el trabajador, según `parametros_negocio`).

**Sin efectos secundarios** (comprobado):
- 0 pagos, adeudos, movimientos, notificaciones, reportes, evidencias, usos de descuento y eventos de moderación;
- `estado_pago = PENDIENTE`, sin pago liberado ni `reporte_pago_hasta` (por eso "No recibí el pago" se rechaza, como debe).

**Verificado por la API, por la IP de la Wi-Fi:**
- cada cuenta ve las 3 solicitudes en su historial, con las indicaciones de calificar y reportar de la tabla;
- el servidor rechaza calificar S2 otra vez como cliente (409 `RESENA_DUPLICADA`) y calificar S3 (409 `SERVICIO_NO_FINALIZADO`), sin crear nada.

**Plazo:** las de S1 y S2 vencen el 2026-12-01. Después ya no se podrá calificar. Para tenerlas otra vez dentro del plazo habría que crear solicitudes nuevas: el script no modifica las que ya creó.

### Validación manual (2026-11-25)
El usuario probó las dos APK en el teléfono contra el backend local e informó que las funciones de la Fase 3b funcionan correctamente: **validación satisfactoria**.
- En la app del trabajador usó «Restablecer demostración» para recargar los datos de prueba. Es el comportamiento esperado.
- Ese botón solo restaura los datos **simulados** de la propia app (solicitudes de la agenda, historial local y perfil) y detiene la consulta de solicitudes disponibles hasta volver a iniciar sesión. No toca el backend.
- Las pantallas de la Fase 3b (mis servicios, calificar, reportar, reputación) leen del backend por su cuenta.

## 6. Quitar todo al terminar
- Firewall:
  ```powershell
  Remove-NetFirewallRule -DisplayName "Que Limpiamos backend local (pruebas)"
  ```
  Se ejecuta como administrador.
- Datos: son de `quelimpiamos_dev`, la BD local. Se pueden dejar, o recrear la BD con `npm run bd:local -- preparar --recrear`, **que borra la BD local de desarrollo**.

## 7. Ciclo de las solicitudes (doc `25` v2, 2026-11-25)
**Cuentas** (credenciales solo en `backend/.local/cuentas-prueba-local.json`):
- cliente ficticio, ahora con la INE VERIFICADA (solo esta cuenta);
- trabajador 1 y trabajador 2 ficticios, activos y verificados;
- propietario de prueba (correo de D63a) y admin1 y admin2: el propietario les otorgó `SUPERVISAR_SOLICITUDES` y `GESTIONAR_INCIDENCIAS_FINANZAS`.

La contraseña del trabajador 1 ya no coincidía con el archivo (cambió después de crearse, por un motivo desconocido) y se restableció solo para esa cuenta con `--restablecer-claves=trabajador`.

**Servidores:**
- `npm run servidor:local`: incluye la tarea periódica, cada minuto;
- panel: `npm run dev -- --port 5173` en `appWeb`.

**APK:** recompiladas con `API_URL=http://192.168.0.78:3000`.

**Pruebas integrales en vivo** (por la IP de la Wi-Fi, servidor real, `quelimpiamos_dev`). Todas OK:
- **Catálogo y cotización:** precio del servidor (400 + 300 = 700).
- **Mis inmuebles:** dos inmuebles guardados; editar uno no cambia la copia de la solicitud.
- **Invitación:** el invitado la ve; rechaza; el cliente ve el rechazo y la envía a la bolsa; quien rechazó ya no la ve; el trabajador 2 la toma.
- **Bolsa:** aceptación simultánea de los 2 trabajadores → 200 y 409.
- **Cancelaciones:** el trabajador cancela con más de 24 h → vuelve a la bolsa; el cliente cancela una PENDIENTE; con menos de 24 h → 409.
- **Traslape:** no se puede invitar a un trabajador con otro servicio que se cruza (la S3 ficticia).
- **Servicio:** iniciar dentro de la ventana; terminar sin fotos → 400; con 2 fotos → OK; el cliente ve las fotos (URL temporal) y confirma → REALIZADO.
- **Reporte:** desde la hora programada; con él, el cliente no puede confirmar (D57); el panel la marca «reporte activo».
- **Resolución:** 2 admins resuelven a la vez → 201 y 409; queda una sola, inmutable.
- **Vencimiento:** la tarea del servidor canceló sola una solicitud vencida, con aviso, sin cargo y con el pago `PENDIENTE`.
- **Permisos:** admin sin permiso → 403; el propietario supervisa sin asignárselo; nadie se otorga un permiso a sí mismo.

**Panel revisado en el navegador** con la sesión del propietario de prueba (doc `25` §11).

**Validación manual en el teléfono (2026-11-25):** el usuario instaló las dos APK (cliente y trabajador) con el ciclo nuevo y las probó. Funcionan correctamente: navegación y funciones disponibles, sin problemas. El reporte de inasistencia abierto de la S3 **se conserva sin tocar**.

D54 (confirmación automática y por evidencia) tarda horas en vivo: se verificó con las pruebas automáticas y el reloj controlado.

**Datos que quedaron** en `quelimpiamos_dev`: solicitudes de prueba 4 a 12, sus avisos, 2 inmuebles y las fotos en `%USERPROFILE%\.quelimpiamos\almacenamiento`.
