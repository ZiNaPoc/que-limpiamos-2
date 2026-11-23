import 'package:flutter_test/flutter_test.dart';
import 'package:que_limpiamos_trabajadores/app.dart';
import 'package:que_limpiamos_trabajadores/services/app_state.dart';

void main() {
  testWidgets('La app arranca y muestra la bienvenida', (tester) async {
    // Sin almacenamiento: se usan solo los datos simulados en memoria.
    await tester.pumpWidget(QueLimpiamosApp(state: AppState()));
    expect(find.text('¿Qué limpiamos?'), findsOneWidget);

    // El splash navega a la bienvenida después de ~2.3 s.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });
}
