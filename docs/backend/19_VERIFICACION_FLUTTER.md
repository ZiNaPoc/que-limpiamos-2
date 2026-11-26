# 19 — Compilar y verificar las apps Flutter (cliente y trabajador)

- **Estado (actualizado el 2026-11-25):** **verificadas por el usuario en su equipo.** Cliente y trabajador pasan `flutter pub get`, `flutter analyze` (0 errores; el trabajador tiene 72 avisos de nivel *info*, que no requieren correcciones cosméticas), `flutter run` y `flutter build apk --debug`. Este equipo sigue sin Flutter SDK, así que esos resultados son los que informó el usuario.
- *Estado anterior:* implementada, sin compilar. La guía se conserva para repetir la verificación.
- **Versiones de Flutter necesarias:**
  - app del **trabajador**: Dart ≥ 3.5, o sea Flutter ≥ 3.24;
  - app del **cliente**: usa `flutter_lints ^6`, que pide Dart ≥ 3.8, o sea Flutter ≥ 3.32.

  Compruébala con:
  ```powershell
  flutter --version
  ```
- **Cambios de Android que hicimos:** `minSdk = maxOf(flutter.minSdkVersion, 23)`, porque `flutter_secure_storage` 10 exige Android 6.0. Las dos apps ya permitían HTTP sin cifrar (`usesCleartextTraffic`) y tenían el permiso de Internet.

## 1. Backend para la prueba (sin tocar producción)
En una terminal, desde `limpiandotuhogar\backend`:
```powershell
npm run demo:local
```
Deja esa terminal abierta. Las cuentas de prueba están en `backend\.local\cuentas-demo.json` (contraseñas nuevas en cada arranque).

## 2. App del cliente
```powershell
cd C:\Users\lolil\Documents\limpieza\que-limpiamos-3\limpiandotuhogar\apps\app_contratador_diseno_que_limpiamos\app_contratador
```
```powershell
flutter pub get
```
```powershell
flutter analyze
```
Con el emulador de Android abierto:
```powershell
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```

## 3. App del trabajador
```powershell
cd C:\Users\lolil\Documents\limpieza\que-limpiamos-3\limpiandotuhogar\apps\app_trabajador
```
```powershell
flutter pub get
```
```powershell
flutter analyze
```
```powershell
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```
Para ver la tarjeta "Cuenta de prueba", agrega `--dart-define=MODO_DEMO=true` al comando anterior. En un celular real, cambia `10.0.2.2` por la IP de tu PC (misma red Wi-Fi).

## 4. Qué debe pasar (marca cada punto)
| # | Paso | Resultado esperado | Cliente | Trabajador |
|---|---|---|---|---|
| 1 | `flutter pub get` | Sin errores | ☐ | ☐ |
| 2 | `flutter analyze` | **0 errores**. Los avisos que ya existían se anotan aparte | ☐ | ☐ |
| 3 | Registro de una cuenta nueva (trabajador: con **dirección**) | Entra a la pantalla principal | ☐ | ☐ |
| 4 | Cerrar la app y volver a abrirla | Entra directo, sin pedir la contraseña (sesión restaurada con `GET /me`) | ☐ | ☐ |
| 5 | Cerrar sesión en el perfil, y luego reabrir | Vuelve a la bienvenida, y al reabrir sigue ahí | ☐ | ☐ |
| 6 | Iniciar sesión con la cuenta de `cuentas-demo.json` (el cliente también puede usar su teléfono) | Entra | ☐ | ☐ |
| 7 | 6 intentos con contraseña incorrecta | Al 7.º: "Demasiados intentos. Intenta de nuevo en 1 minuto." | ☐ | ☐ |
| 8 | Con la sesión abierta, detener la demo (Ctrl+C) y arrancarla de nuevo (secretos nuevos) | La siguiente petición da 401 y la app vuelve a la bienvenida | ☐ | ☐ |
| 9 | Sin `MODO_DEMO` | No aparece la tarjeta "Cuenta de prueba" | — | ☐ |

Cuando lo corras, compárteme la salida de `flutter analyze` y qué puntos fallaron: con eso corrijo y se da por integrada.

## 5. Qué NO probar todavía
Solicitudes, avisos, agenda y pagos usan aún las rutas viejas del backend. Fallarán hasta las Fases 3 (cliente) y 4 (trabajador).
