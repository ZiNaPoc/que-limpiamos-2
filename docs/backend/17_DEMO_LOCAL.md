# 17 — Demo local sin costo (sin tocar producción)

Para mostrar el proyecto en una computadora, sin servicios de pago y **sin escribir en la BD de producción**.

> **Actualización 2026-11-25 (Fase 3a): la demo usa el TiDB LOCAL en Docker (doc `22`), no el clúster.**
> 1. `npm run bd:local -- iniciar`
> 2. `npm run demo:local`. Se crea `quelimpiamos_demo` con 000 + 002 + 003 v2 y **se borra al detener**.
> 3. Con `-- --con-moderacion`, el admin de la demo recibe `MODERAR_CONTENIDO` de una propietaria **de prueba**, solo en esa BD efímera.
>
> Lo que sigue sobre `queLimpiamos_proyecto` es histórico.

## 1. Backend
Desde `limpiandotuhogar/backend` (PowerShell):
```powershell
npm run demo:local
```
- Usa la BD `queLimpiamos_proyecto` (o la que pongas en `DEMO_DATABASE_NAME`; también se acepta `queLimpiamos_dev` si la creas en TiDB, gratis). **Nunca** la de producción.
- Si la BD está vacía, crea las mismas tablas que producción **sin datos**. De producción solo lee la estructura.
- Crea tres cuentas de demostración (admin, cliente y trabajador) con **contraseñas nuevas en cada arranque**. Las guarda en `backend/.local/cuentas-demo.json`, que está ignorado por git; ahí las consultas.
- Si `.env` no tiene `JWT_SECRET_*`, usa secretos temporales de esa sesión.
- **Ctrl+C** detiene la demo. En `queLimpiamos_proyecto` deja la BD **vacía** (la usan `npm test` y los ensayos). Con `--conservar`, o en `queLimpiamos_dev`, conserva los datos.
- Si la cerraste de golpe y quedaron tablas, vacíala con:
  ```powershell
  npm run demo:limpiar
  ```
- La carpeta del almacenamiento local es `<home>/.quelimpiamos/almacenamiento` (privada, fuera del repositorio). **Hoy no hay ninguna función de carga de documentos**: el módulo está probado pero no conectado a endpoints (Fase 3c y Fase 5).

## 2. Panel (admin)
Desde `limpiandotuhogar/appWeb`:
```powershell
npm run dev
```
Abre `http://localhost:5173` y entra con la cuenta admin del archivo de cuentas.

El panel original **compila** (2026-11-25, ver `18`): login, sesión, logout, cookie httpOnly y CSRF se probaron en el navegador contra esta demo.

El panel lee `VITE_API_URL` de `appWeb/.env.local` (`http://localhost:3000`; plantilla en `appWeb/.env.example`). Si tu `.env.local` no la tiene, puedes arrancarlo así (la variable del proceso tiene prioridad):
```powershell
$env:VITE_API_URL = "http://localhost:3000"; npm run dev
```

## 3. Apps Flutter
Guía detallada, con la lista de verificación: `19_VERIFICACION_FLUTTER.md`.

Con Flutter instalado, en cada app:
```powershell
flutter pub get
```
Después, en el emulador de Android (que llega a la PC por `10.0.2.2`), la app del cliente:
```powershell
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```
Y la app del trabajador; `MODO_DEMO=true` es opcional y muestra la tarjeta "Cuenta de prueba":
```powershell
flutter run --dart-define=API_URL=http://10.0.2.2:3000 --dart-define=MODO_DEMO=true
```
En un celular real, usa la IP de la PC en vez de `10.0.2.2` (misma red Wi-Fi). Según los resultados que informó el usuario (2026-11-24), las dos apps pasan `flutter pub get`, `flutter analyze`, `flutter run` y `flutter build apk --debug` (ver `19`).

## 4. Qué se puede demostrar hoy
- Registro, inicio de sesión (con correo o teléfono), sesión que se conserva al reabrir, cierre de sesión y bloqueo temporal tras varios intentos fallidos, en las tres audiencias.
- **Todavía no**: solicitudes, pagos ni reportes. Eso son las Fases 3 a 5 y requieren el SQL 002 + 003 en la BD que se use.
