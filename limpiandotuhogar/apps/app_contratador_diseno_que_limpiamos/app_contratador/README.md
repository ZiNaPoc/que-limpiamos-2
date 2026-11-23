# app_contratador — ¿Qué limpiamos?

App para clientes conectada al backend (login, registro, solicitudes y avisos),
con el diseño visual de **¿Qué limpiamos?**.

## Ejecutar

```bash
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:3000   # emulador Android
```

En un celular real usa la IP de tu PC en `API_URL`.

## Estructura

| Carpeta | Contenido |
| --- | --- |
| `lib/theme/` | Paleta (`AppColors`), tipografía Poppins, radios, sombras y tema (`AppTheme`). |
| `lib/widgets/` | Componentes del diseño: ondas, botones, campos, tarjetas, avatares orgánicos, diálogos y piezas del flujo «Solicitar». |
| `lib/navigation/` | Transiciones entre pantallas (`AppRoutes`). |
| `lib/data/service_catalog.dart` | Tipos de limpieza, precios base y fotos. |
| `lib/services/` | Conexión con el backend (`ApiClient`, `AuthApi`, `SolicitudApi`) y sesión. |
| `lib/screens/` | Pantallas. |
| `assets/images/`, `assets/fonts/` | Logotipo, fotos de los servicios y fuente Poppins (licencia OFL). |
