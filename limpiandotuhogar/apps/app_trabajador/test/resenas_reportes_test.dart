import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:que_limpiamos_trabajadores/screens/servicios_resenas_screens.dart';
import 'package:que_limpiamos_trabajadores/services/app_scope.dart';
import 'package:que_limpiamos_trabajadores/services/app_state.dart';
import 'package:que_limpiamos_trabajadores/services/api_client.dart';
import 'package:que_limpiamos_trabajadores/services/historial_api.dart';
import 'package:que_limpiamos_trabajadores/services/resenas_reportes_api.dart';
import 'package:que_limpiamos_trabajadores/services/validaciones_contenido.dart';

// Fase 3b — app del trabajador: validación local, cliente HTTP (servidor simulado SOLO en la
// prueba, vía http.runWithClient) y la pantalla de calificar al cliente.

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
List<int> deTamano(int n) => [0xFF, 0xD8, 0xFF, ...List.filled(n - 3, 0)];
http.Response json(int status, Object cuerpo) => http.Response(jsonEncode(cuerpo), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> resena() => {
      'id': 1, 'solicitudId': 4, 'calificaA': 'CLIENTE', 'puntuacion': 5, 'comentario': null,
      'fecha': '2026-11-25T12:00:00.000Z', 'editadaPorModeracion': false, 'eliminadaPorModeracion': false,
    };

void main() {
  setUp(() {
    ApiClient.token = 'token-trabajador';
    ApiClient.onSesionVencida = null;
  });

  group('Validación local', () {
    test('reseña válida, sin comentario, comentario largo y fuera de rango', () {
      expect(validarResena(puntuacion: 5, comentario: 'Puntual'), isNull);
      expect(validarResena(puntuacion: 2), isNull);
      expect(validarResena(puntuacion: 4, comentario: 'x' * 501), isNotNull);
      expect(validarResena(puntuacion: 0), isNotNull);
    });
    test('fotos: exceso, tamaño, total y tipo', () {
      expect(validarFotos(List.generate(6, (_) => jpeg)), isNotNull);
      expect(validarFotos([deTamano(8000001)]), contains('8 MB'));
      expect(validarFotos([deTamano(7000000), deTamano(7000000), deTamano(2000001)]), contains('16 MB'));
      expect(validarFotos([ascii.encode('%PDF-1.4')]), contains('JPEG'));
      expect(validarFotos([jpeg]), isNull);
    });
  });

  group('Cliente HTTP', () {
    test('calificar al cliente: ruta del trabajador y token', () async {
      final r = await http.runWithClient(() => ResenasApi.calificarCliente(4, puntuacion: 5), () => MockClient((req) async {
            expect(req.url.path, '/api/trabajador/solicitudes/4/resena');
            expect(req.headers['Authorization'], 'Bearer token-trabajador');
            expect(jsonDecode(req.body), {'puntuacion': 5});
            return json(201, {'resena': resena()});
          }));
      expect(r.puntuacion, 5);
    });

    test('reputación del cliente NO autorizada (403): error con mensaje claro, sin datos', () async {
      try {
        await http.runWithClient(() => ResenasApi.reputacionDelCliente(4), () => MockClient((_) async => json(403, {'mensaje': 'x', 'codigo': 'REPUTACION_NO_AUTORIZADA'})));
        fail('debió fallar');
      } on ApiException catch (e) {
        expect(e.statusCode, 403);
        expect(mensajeDeError(e), contains('invitado o asignado'));
      }
    });

    test('reputación del cliente autorizada y reseñas recibidas (anónimas)', () async {
      final rep = await http.runWithClient(() => ResenasApi.reputacionDelCliente(4), () => MockClient((_) async => json(200, {'reputacion': {'promedio': 4.5, 'cantidad': 2}})));
      expect(rep.promedio, 4.5);
      final recibidas = await http.runWithClient(() => ResenasApi.resenasRecibidas(), () => MockClient((_) async => json(200, {
            'reputacion': {'promedio': null, 'cantidad': 0},
            'resenas': [],
          })));
      expect(recibidas.reputacion.promedio, isNull);
      expect(recibidas.resenas, isEmpty);
    });

    test('historial vacío y con una invitación', () async {
      expect(await http.runWithClient(() => HistorialApi.misSolicitudes(), () => MockClient((_) async => json(200, {'solicitudes': []}))), isEmpty);
      final lista = await http.runWithClient(() => HistorialApi.misSolicitudes(), () => MockClient((_) async => json(200, {
            'solicitudes': [
              {
                'id': 4, 'estado': 'PENDIENTE', 'relacion': 'INVITADO', 'invitacion': 'PENDIENTE', 'fechaProgramada': '2026-11-26T10:00:00.000Z',
                'realizadoEn': null, 'servicio': 'Limpieza general', 'cliente': {'nombre': 'Ana'}, 'miResena': null, 'calificarHasta': null,
                'puedeCalificar': false, 'puedeReportar': false, 'puedeVerReputacionCliente': true,
              }
            ]
          })));
      expect(lista.single.asignado, isFalse);
      expect(lista.single.puedeReportar, isFalse);
    });

    test('reporte con foto (multipart) y sesión expirada', () async {
      late http.MultipartRequest enviado;
      await http.runWithClient(
          () => ReportesApi.reportar(4, tipo: 'PAGO_EN_DISPUTA', fotos: [(nombre: 'evidencia-1.jpg', bytes: jpeg)]),
          () => MockClient.streaming((req, _) async {
                enviado = req as http.MultipartRequest;
                final cuerpo = jsonEncode({'reporte': {'id': 1, 'solicitudId': 4, 'tipo': 'PAGO_EN_DISPUTA', 'descripcion': null, 'estado': 'ABIERTO', 'fecha': '2026-11-25T12:00:00.000Z', 'eliminadoPorModeracion': false, 'evidencias': [{'id': 9, 'tipoMime': 'image/jpeg', 'tamanoBytes': 7}]}});
                return http.StreamedResponse(Stream.value(utf8.encode(cuerpo)), 201);
              }));
      expect(enviado.url.path, '/api/trabajador/solicitudes/4/reportes');
      expect(enviado.files.single.filename, 'evidencia-1.jpg');
      var avisos = 0;
      ApiClient.onSesionVencida = () => avisos++;
      await expectLater(http.runWithClient(() => ReportesApi.misReportes(), () => MockClient((_) async => json(401, {'mensaje': 'x', 'codigo': 'SESION_EXPIRADA'}))), throwsA(isA<ApiException>()));
      expect(avisos, 1);
    });
  });

  group('Pantalla de calificar al cliente', () {
    Future<void> elegirYEnviar(WidgetTester tester, {bool doble = false}) async {
      // Como en la app: la pantalla vive bajo AppScope (Haptics lee las preferencias del usuario).
      await tester.pumpWidget(AppScope(state: AppState(), child: const MaterialApp(home: CalificarClienteScreen(solicitudId: 4, clienteNombre: 'Ana'))));
      final escoba = find.byIcon(Icons.cleaning_services_outlined).last;
      await tester.ensureVisible(escoba);
      await tester.pump();
      await tester.tap(escoba);
      await tester.pump();
      final boton = find.text('Enviar calificación');
      await tester.ensureVisible(boton);
      await tester.tap(boton);
      if (doble) await tester.tap(boton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('doble envío: una sola petición', (tester) async {
      var peticiones = 0;
      await http.runWithClient(() => elegirYEnviar(tester, doble: true), () => MockClient((_) async {
            peticiones++;
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return json(201, {'resena': resena()});
          }));
      await tester.pumpAndSettle();
      expect(peticiones, 1);
    });

    testWidgets('servicio no elegible: aviso visible', (tester) async {
      await http.runWithClient(() => elegirYEnviar(tester), () => MockClient((_) async => json(409, {'mensaje': 'x', 'codigo': 'SERVICIO_NO_FINALIZADO'})));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('servicio finalizado'), findsOneWidget);
    });
  });
}
