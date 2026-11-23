import 'package:flutter_test/flutter_test.dart';

import 'package:app_contratador/data/service_catalog.dart';
import 'package:app_contratador/main.dart';

void main() {
  testWidgets('El splash muestra la marca y pasa a la bienvenida',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('¿Qué limpiamos?'), findsOneWidget);

    // El splash espera 3 s y luego abre la bienvenida.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Crear cuenta'), findsOneWidget);
  });

  test('money da formato con separador de miles', () {
    expect(money(400), r'$400');
    expect(money(1250), r'$1,250');
  });

  test('La búsqueda ignora acentos y mayúsculas', () {
    expect(ServiceCatalog.search('PROFUNDA').length, 1);
    expect(ServiceCatalog.search('remodelacion').single.title,
        'Limpieza post-obra');
    expect(ServiceCatalog.search(''), isEmpty);
  });
}
