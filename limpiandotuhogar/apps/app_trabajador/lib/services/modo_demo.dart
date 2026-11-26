/// Modo demostración (sin backend): muestra la tarjeta "Cuenta de prueba" y
/// permite las sesiones solo locales. APAGADO por defecto: las compilaciones
/// normales no lo incluyen. Para encenderlo:
///   flutter run --dart-define=MODO_DEMO=true
const bool modoDemo = bool.fromEnvironment('MODO_DEMO');
