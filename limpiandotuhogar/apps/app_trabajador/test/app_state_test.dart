import 'package:flutter_test/flutter_test.dart';
import 'package:que_limpiamos_trabajadores/models/service_request.dart';
import 'package:que_limpiamos_trabajadores/services/app_state.dart';
import 'package:que_limpiamos_trabajadores/services/formatters.dart';
import 'package:que_limpiamos_trabajadores/services/validators.dart';

/// Pruebas de la lógica local (sin interfaz ni almacenamiento).
void main() {
  // Martes a las 10:00 para que el horario de prueba (L–S 8–19) sea estable.
  final fixedNow = DateTime(2026, 11, 3, 10);
  AppState newState() => AppState(clock: () => fixedNow);

  group('Flujo completo de una solicitud', () {
    test('aceptar → proponer → acuerdo → confirmar → iniciar → finalizar', () {
      final s = newState();
      final r = s.byId('r1')!;
      expect(r.status, RequestStatus.disponible);
      final availableBefore = s.availableRequests.length;

      expect(s.acceptOpportunity('r1'), isNull);
      expect(r.status, RequestStatus.enNegociacion);
      expect(s.availableRequests.length, availableBefore - 1);
      expect(s.negotiatingRequests.contains(r), isTrue);

      expect(s.sendProposal('r1', 520, 'Incluye ventanas'), isNull);
      expect(r.status, RequestStatus.pendiente);
      expect(r.proposal!.version, 1);

      // Editar mientras está pendiente.
      expect(s.sendProposal('r1', 540, ''), isNull);
      expect(r.proposal!.version, 2);

      s.simulateClientResponse('r1', SimulatedResponse.acepta);
      expect(r.status, RequestStatus.aceptada);
      expect(r.agreedPrice, 540);

      expect(s.confirmService('r1'), isNull);
      expect(r.status, RequestStatus.confirmada);
      expect(s.agendaRequests.contains(r), isTrue);

      // El servicio es en 2 días: aún no puede iniciarse.
      expect(s.canStart(r).allowed, isFalse);
    });

    test('el servicio de hoy se inicia y finaliza, y suma ingresos', () {
      final s = newState();
      final before = s.totalEarnings;
      expect(s.startJob('r8'), isNull);
      expect(s.byId('r8')!.status, RequestStatus.enCurso);
      expect(s.startJob('r9'), isNotNull,
          reason: 'No se permiten dos servicios en curso');
      expect(s.finishJob('r8'), isNull);
      expect(s.byId('r8')!.status, RequestStatus.finalizada);
      expect(s.totalEarnings, before + 550);
      expect(s.rateClient('r8', 5, 'Excelente'), isNull);
      expect(s.canRate(s.byId('r8')!).allowed, isFalse);
    });

    test('contraoferta aceptada genera acuerdo', () {
      final s = newState();
      expect(s.acceptCounterOffer('r6'), isNull);
      final r = s.byId('r6')!;
      expect(r.status, RequestStatus.aceptada);
      expect(r.agreedPrice, 760);
    });
  });

  group('Reglas de negocio', () {
    test('sin disponibilidad no se puede aceptar', () {
      final s = newState()..setOnline(false);
      expect(s.canAccept(s.byId('r2')!).allowed, isFalse);
      expect(s.acceptOpportunity('r2'), isNotNull);
    });

    test('no se puede proponer sin aceptar primero', () {
      final s = newState();
      expect(s.canPropose(s.byId('r2')!).allowed, isFalse);
    });

    test('rechazar quita la solicitud de las disponibles', () {
      final s = newState();
      s.rejectRequest('r2', 'fuera de mi zona');
      expect(s.byId('r2')!.status, RequestStatus.rechazada);
      expect(s.availableRequests.any((r) => r.id == 'r2'), isFalse);
      expect(s.closedRequests.any((r) => r.id == 'r2'), isTrue);
    });

    test('las notificaciones se marcan como leídas', () {
      final s = newState();
      expect(s.unreadCount, greaterThan(0));
      s.markAllNotificationsRead();
      expect(s.unreadCount, 0);
    });
  });

  group('Formato y validación', () {
    test('montos', () {
      expect(Fmt.money(4500, decimals: true), r'$4,500.00');
      expect(Fmt.money(450), r'$450');
      expect(Fmt.range(450, 550), r'$450–550');
    });

    test('validadores', () {
      expect(Validators.email('demo@quelimpiamos.mx'), isNull);
      expect(Validators.email('demo@'), isNotNull);
      expect(Validators.phone('998 111 2233'), isNull);
      expect(Validators.password('abc'), isNotNull);
      expect(Validators.password('Demo1234'), isNull);
    });
  });
}
