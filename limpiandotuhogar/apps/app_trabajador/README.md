# ¿Qué limpiamos? · App de trabajadores (Flutter)

Aplicación móvil para colaboradores de **¿Qué limpiamos?**: recibir solicitudes, negociar el precio, confirmar servicios, gestionar la agenda, revisar ingresos y administrar el perfil.

**Todo funciona desde el frontend**, con datos simulados y persistencia local (`shared_preferences`). No hay backend, API, base de datos remota, autenticación real ni sincronización con la app de clientes.

---

## 1. Contenido del proyecto

```
que_limpiamos_trabajadores/
├── pubspec.yaml
├── analysis_options.yaml
├── assets/
│   ├── images/logo.png            ← logotipo oficial con fondo transparente
│   ├── images/logo_original.png   ← archivo original sin modificar
│   ├── images/spaces/*.jpg        ← fotos ilustradas de los espacios (datos simulados)
│   └── fonts/Poppins-*.ttf        ← tipografía (licencia OFL)
├── android/app/src/main/
│   ├── AndroidManifest.xml        ← nombre de la app, orientación vertical
│   └── res/mipmap-*/ic_launcher.png  ← ícono con el logotipo
├── lib/
│   ├── main.dart · app.dart
│   ├── theme/       app_colors.dart (paleta) · app_theme.dart (tipografía, radios, sombras)
│   ├── models/      service_request.dart · worker_profile.dart · app_notification.dart
│   ├── data/        mock_data.dart (clientes, solicitudes, historial, notificaciones)
│   ├── services/    app_state.dart (reglas de negocio) · storage · validadores · formatos
│   ├── navigation/  app_routes.dart (transiciones)
│   ├── widgets/     componentes reutilizables (botones, campos, tarjetas, modales…)
│   └── screens/     todas las pantallas
└── test/            pruebas de la lógica y de arranque
```

### Pantallas implementadas

| Mockup | Pantalla | Archivo |
|---|---|---|
| 1 | Splash animado | `splash_screen.dart` |
| 2 | Bienvenida | `welcome_screen.dart` |
| 3 | Iniciar sesión | `login_screen.dart` |
| 4 | Recuperar contraseña | `forgot_password_screen.dart` |
| 5 | Crear cuenta (2 pasos + INE) | `register_screen.dart` |
| 6 | Inicio «Tu día de hoy» | `home_screen.dart` |
| 7 | Solicitudes (filtros) | `requests_screen.dart` |
| 8–10 | Detalle con carrusel Precio / Espacio / Servicio | `request_detail_screen.dart` + `request_actions.dart` |
| 11 | Modal perfil del cliente | `widgets/client_profile_dialog.dart` |
| 12 | Chat con el cliente | `chat_screen.dart` |
| 13 | Agenda | `agenda_screen.dart` |
| 14 | Historial | `history_screen.dart` |
| 15 | Calificar cliente | `rate_client_screen.dart` |
| 16 | Mi perfil | `profile_screen.dart` |
| — | Disponibilidad y horario | `availability_screen.dart` |
| — | Ingresos y actividad | `earnings_screen.dart` |
| — | Notificaciones | `notifications_screen.dart` |

### Flujo de estados de una solicitud

```
Disponible ──Aceptar oportunidad──▶ En negociación ──Enviar propuesta──▶ Pendiente
                                        ▲      │                            │
                                        │      └──Aceptar contraoferta──┐   │ (respuesta del cliente*)
                            contraoferta*                               ▼   ▼
                                        └────────────────────────── Aceptada (hay acuerdo)
                                                                        │ Confirmar servicio
                                                                        ▼
                                              Confirmada ──Iniciar──▶ En curso ──Finalizar──▶ Finalizada
Cualquier etapa previa al servicio → Rechazada / Cancelada
```

\* Como no existe conexión con la app de clientes, en una propuesta **Pendiente** aparece el enlace **«Simular respuesta del cliente (demo)»**, que solo cambia los datos en el dispositivo para poder probar todo el flujo.

Reglas visibles en la interfaz: no se puede aceptar con la disponibilidad desactivada, no se puede proponer sin aceptar primero, no se pueden confirmar servicios que se empalman, un servicio solo se inicia el día programado y solo puede haber uno en curso. La dirección exacta y el teléfono completo del cliente se muestran solo cuando corresponde.

### Paleta

Los 15 colores de la paleta entregada están en `lib/theme/app_colors.dart` con nombre propio. Para cumplir el contraste mínimo de lectura (WCAG AA), los textos y botones principales usan tonos profundos del mismo matiz que `#7296A4` (`#50707C`, `#46626C`, `#28383E`), y advertencia/error usan dos tonos funcionales suaves. Ningún archivo usa colores fuera de `AppColors`.

---

## 2. Requisitos previos

- **Flutter 3.24 o superior** (Dart 3.5+). Comprueba con `flutter --version`.
- **Android Studio** (para el SDK de Android y el emulador) y **Visual Studio Code** con las extensiones *Flutter* y *Dart*.
- JDK 17 (incluido en Android Studio).

## 3. Configuración de Flutter y Dart

```bash
flutter doctor            # revisa que Flutter, Android SDK y licencias estén listos
flutter doctor --android-licenses   # acepta las licencias si lo pide
```

## 4. Preparar el proyecto (solo la primera vez)

Este repositorio incluye el código, los recursos, el `AndroidManifest.xml` y los íconos. Los demás archivos de la plataforma Android (Gradle, `MainActivity`) los genera Flutter para que coincidan con tu versión instalada. Desde la carpeta del proyecto:

```bash
flutter create --org com.quelimpiamos --project-name que_limpiamos_trabajadores --platforms android .
```

`flutter create .` **no sobrescribe** archivos existentes: solo agrega los que faltan.

### minSdk (Android 8 = API 26)

Abre `android/app/build.gradle.kts` (o `build.gradle`) y verifica la línea `minSdk`. El valor por defecto `flutter.minSdkVersion` es 21 o 24 según tu versión de Flutter, en ambos casos **menor que 26**, así que la app instala en Android 8.0/8.1 sin cambios. Si prefieres fijarlo explícitamente:

```kotlin
defaultConfig {
    minSdk = 24   // cualquier valor ≤ 26 funciona en Android 8
}
```

Dependencias usadas (ambas oficiales y compatibles con Android 8): `shared_preferences` y `image_picker`.

## 5. Crear el emulador Android 8

1. Android Studio → **Device Manager** → **Create Virtual Device**.
2. Elige un teléfono (p. ej. *Pixel 4*).
3. En *System Image* selecciona **Oreo · API 26 (Android 8.0)** o **API 27 (8.1)**, imagen *x86_64* o *arm64* según tu equipo (descárgala si es necesario).
4. Finaliza y pulsa ▶ para iniciarlo.

## 6. Instalar dependencias

```bash
flutter pub get           # descarga shared_preferences e image_picker
```

## 7. Verificar el dispositivo

```bash
flutter devices           # debe aparecer el emulador, p. ej. «sdk gphone x86 (mobile) • emulator-5554»
flutter emulators         # lista emuladores; flutter emulators --launch <id> para abrir uno
```

## 8. Ejecutar

**Terminal**

```bash
flutter analyze           # revisión estática del código
flutter test              # pruebas de lógica y arranque
flutter run               # compila e instala en el dispositivo seleccionado
flutter run -d emulator-5554   # si hay varios dispositivos
```

Durante `flutter run`: `r` recarga en caliente, `R` reinicia la app, `q` sale.

**Visual Studio Code**: abre la carpeta, elige el emulador en la barra inferior (selector de dispositivo) y pulsa **F5** (*Run → Start Debugging*).

**APK de prueba**

```bash
flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
```

## 9. Errores frecuentes

| Síntoma | Solución |
|---|---|
| `No connected devices` | Inicia el emulador desde Device Manager y vuelve a correr `flutter devices`. |
| `Unable to locate Android SDK` | Instala el SDK desde Android Studio y ejecuta `flutter config --android-sdk <ruta>`. |
| Licencias de Android no aceptadas | `flutter doctor --android-licenses`. |
| `minSdkVersion … cannot be smaller than …` declarada por un paquete | Sube `minSdk` al valor que indique el mensaje (siempre ≤ 26 para estos paquetes). |
| Errores de Gradle o versión de Java | Usa el JDK de Android Studio: `flutter config --jdk-dir "<ruta a jbr>"`, luego `flutter clean` y `flutter pub get`. |
| `Unable to load asset` | Verifica que la carpeta `assets/` está completa y ejecuta `flutter clean && flutter pub get`. |
| La cámara no abre en el emulador | En el AVD, *Edit → Show Advanced Settings → Camera* = *Emulated* o *VirtualScene*; o usa «Elegir de la galería». |
| Datos «raros» después de muchas pruebas | Perfil → **Restablecer demostración**. |
| Faltan archivos de Android | Repite el paso 4 (`flutter create … .`). |

## 10. Cómo comprobar que todo funciona

Cuenta de prueba: **demo@quelimpiamos.mx / Demo1234** (en el login hay un botón «Usar»).

1. **Acceso**: crea una cuenta (valida campos, avanza y regresa entre pasos, sube frente y reverso de INE) o entra con la cuenta de prueba; prueba «¿Olvidaste tu contraseña?» y el reenvío con cuenta regresiva.
2. **Inicio**: cambia la disponibilidad con el interruptor «Activa» y observa cómo cambian el inicio y la pantalla de solicitudes; abre notificaciones, ingresos, calificaciones y accesos rápidos.
3. **Solicitudes**: usa los filtros Todas / Nuevas / Por acordar; abre «Limpieza profunda», desliza el carrusel o toca las pestañas y los puntos; abre fotos y el perfil del cliente (contacto oculto hasta aceptar).
4. **Negociación**: *Aceptar solicitud* → *Enviar propuesta* → *Editar propuesta* → *Simular respuesta del cliente (demo)* (acepta / contraoferta / rechaza) → *Confirmar servicio*. La solicitud desaparece de «Nuevas», pasa a la agenda y se actualiza el inicio.
5. **Contraoferta**: abre «Limpieza de mudanza» y acepta la contraoferta, o envía una nueva propuesta desde el chat («Confirmar precio»).
6. **Chat**: envía mensajes, comparte ubicación (demostración) y envía una foto.
7. **Agenda**: busca, filtra y toca días en la franja; en «Para hoy» inicia el servicio, mira el cronómetro y finalízalo; califica al cliente.
8. **Historial e ingresos**: el servicio finalizado aparece en historial y suma a ingresos; prueba «Calificar» y «Ver calificación».
9. **Perfil**: edita campos con el lápiz, especialidades y foto; guarda; ajusta horario y preferencias (distancia máxima, solo dentro de horario) y observa las solicitudes ocultas.
10. Cierra la app y vuelve a abrirla: la sesión y los cambios se conservan.
