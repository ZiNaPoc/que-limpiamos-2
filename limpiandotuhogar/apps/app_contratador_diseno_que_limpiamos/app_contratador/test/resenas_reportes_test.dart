import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_contratador/screens/rate_screen.dart';
import 'package:app_contratador/services/api_client.dart';
import 'package:app_contratador/services/historial_api.dart';
import 'package:app_contratador/services/resenas_reportes_api.dart';
import 'package:app_contratador/services/validaciones_contenido.dart';

// Fase 3b — app del cliente: validación local, cliente HTTP (con un servidor simulado SOLO en la
// prueba, vía http.runWithClient) y la pantalla de calificar.

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]);
final webp = Uint8List.fromList([...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP')]);
List<int> deTamano(int n) => [0xFF, 0xD8, 0xFF, ...List.filled(n - 3, 0)];

http.Response json(int status, Object cuerpo) => http.Response(jsonEncode(cuerpo), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> resenaPropia({String? comentario}) => {
      'id': 7, 'solicitudId': 3, 'calificaA': 'TRABAJADOR', 'puntuacion': 5, 'comentario': comentario,
      'fecha': '2026-11-25T12:00:00.000Z', 'editadaPorModeracion': false, 'eliminadaPorModeracion': false,
    };

void main() {
  setUp(() {
    ApiClient.token = 'token-de-prueba';
    ApiClient.onSesionVencida = null;
  });

  group('Validación local de reseñas', () {
    test('reseña válida y reseña sin comentario', () {
      expect(validarResena(puntuacion: 5, comentario: 'Excelente'), isNull);
      expect(validarResena(puntuacion: 3), isNull);
      expect(validarResena(puntuacion: 1, comentario: '   '), isNull);
    });
    test('calificación fuera de 1–5', () {
      expect(validarResena(puntuacion: 0), isNotNull);
      expect(validarResena(puntuacion: 6), isNotNull);
    });
    test('comentario de más de 500 caracteres (500 exactos sí)', () {
      expect(validarResena(puntuacion: 4, comentario: 'x' * 501), contains('500'));
      expect(validarResena(puntuacion: 4, comentario: 'ñ' * 500), isNull);
    });
  });

  group('Validación local de fotos', () {
    test('tipo real por bytes: JPEG, PNG y WebP; otro tipo no', () {
      expect(extensionReal(jpeg), 'jpg');
      expect(extensionReal(png), 'png');
      expect(extensionReal(webp), 'webp');
      expect(extensionReal(ascii.encode('%PDF-1.4')), isNull);
      expect(validarFotos([ascii.encode('GIF89a')]), contains('JPEG, PNG o WebP'));
    });
    test('sin fotos y con fotos válidas', () {
      expect(validarFotos([]), isNull);
      expect(validarFotos([jpeg, png, webp]), isNull);
    });
    test('más de 5 fotos', () {
      expect(validarFotos(List.generate(6, (_) => jpeg)), contains('5'));
    });
    test('foto de más de 8 MB (8 000 001 bytes); 8 000 000 exactos sí', () {
      expect(validarFotos([deTamano(8000001)]), contains('8 MB'));
      expect(validarFotos([deTamano(8000000)]), isNull);
    });
    test('conjunto de más de 16 MB', () {
      expect(validarFotos([deTamano(7000000), deTamano(7000000), deTamano(2000001)]), contains('16 MB'));
    });
  });

  group('Cliente HTTP contra respuestas del servidor', () {
    test('reseña válida: envía puntuación y comentario y devuelve la reseña propia', () async {
      late Map<String, dynamic> enviado;
      final r = await http.runWithClient(() => ResenasApi.calificarTrabajador(3, puntuacion: 5, comentario: ' Muy bien '), () => MockClient((req) async {
            expect(req.url.path, '/api/cliente/solicitudes/3/resena');
            expect(req.headers['Authorization'], 'Bearer token-de-prueba');
            enviado = jsonDecode(req.body) as Map<String, dynamic>;
            return json(201, {'resena': resenaPropia(comentario: 'Muy bien')});
          }));
      expect(enviado, {'puntuacion': 5, 'comentario': 'Muy bien'});
      expect(r.puntuacion, 5);
    });

    test('reseña sin comentario: no manda el campo', () async {
      late Map<String, dynamic> enviado;
      await http.runWithClient(() => ResenasApi.calificarTrabajador(3, puntuacion: 4), () => MockClient((req) async {
            enviado = jsonDecode(req.body) as Map<String, dynamic>;
            return json(201, {'resena': resenaPropia()});
          }));
      expect(enviado, {'puntuacion': 4});
    });

    test('servicio no elegible: el error del servidor llega con su código y un mensaje claro', () async {
      for (final codigo in ['SERVICIO_NO_FINALIZADO', 'PLAZO_VENCIDO', 'RESENA_DUPLICADA']) {
        try {
          await http.runWithClient(() => ResenasApi.calificarTrabajador(3, puntuacion: 4), () => MockClient((_) async => json(409, {'mensaje': 'x', 'codigo': codigo})));
          fail('debió fallar');
        } on ApiException catch (e) {
          expect(e.codigo, codigo);
          expect(e.statusCode, 409);
          expect(mensajeDeError(e), isNot('x'));
        }
      }
    });

    test('error HTTP genérico (500) y servidor inalcanzable', () async {
      await expectLater(http.runWithClient(() => ResenasApi.misResenas(), () => MockClient((_) async => json(500, {'mensaje': 'Error interno del servidor'}))),
          throwsA(isA<ApiException>().having((e) => e.message, 'mensaje', 'Error interno del servidor')));
      await expectLater(http.runWithClient(() => ResenasApi.misResenas(), () => MockClient((_) async => throw http.ClientException('sin red'))),
          throwsA(isA<ApiException>().having((e) => e.message, 'mensaje', contains('No se pudo conectar'))));
    });

    test('sesión expirada: un 401 con token avisa a la sesión', () async {
      var avisos = 0;
      ApiClient.onSesionVencida = () => avisos++;
      await expectLater(http.runWithClient(() => ResenasApi.misResenas(), () => MockClient((_) async => json(401, {'mensaje': 'Tu sesión expiró', 'codigo': 'SESION_EXPIRADA'}))),
          throwsA(isA<ApiException>()));
      await expectLater(http.runWithClient(() => ReportesApi.reportar(3), () => MockClient((_) async => json(401, {'mensaje': 'x', 'codigo': 'SESION_EXPIRADA'}))),
          throwsA(isA<ApiException>()));
      expect(avisos, 2);
    });

    test('reporte sin fotos y con fotos: multipart con el campo "fotos" y la extensión real', () async {
      final peticiones = <http.MultipartRequest>[];
      Future<http.StreamedResponse> responder(http.BaseRequest req) async {
        peticiones.add(req as http.MultipartRequest);
        final cuerpo = jsonEncode({'reporte': {'id': 1, 'solicitudId': 3, 'tipo': 'OTRO', 'descripcion': null, 'estado': 'ABIERTO', 'fecha': '2026-11-25T12:00:00.000Z', 'eliminadoPorModeracion': false, 'evidencias': []}});
        return http.StreamedResponse(Stream.value(utf8.encode(cuerpo)), 201, headers: {'content-type': 'application/json'});
      }
      await http.runWithClient(() => ReportesApi.reportar(3), () => MockClient.streaming((r, _) => responder(r)));
      await http.runWithClient(
          () => ReportesApi.reportar(3, tipo: 'INASISTENCIA', descripcion: 'No llegó', fotos: [(nombre: 'evidencia-1.jpg', bytes: jpeg), (nombre: 'evidencia-2.png', bytes: png)]),
          () => MockClient.streaming((r, _) => responder(r)));
      expect(peticiones[0].files, isEmpty);
      expect(peticiones[0].url.path, '/api/cliente/solicitudes/3/reportes');
      expect(peticiones[1].fields, {'tipo': 'INASISTENCIA', 'descripcion': 'No llegó'});
      expect(peticiones[1].files.map((f) => '${f.field}:${f.filename}').toList(), ['fotos:evidencia-1.jpg', 'fotos:evidencia-2.png']);
      expect(peticiones[1].headers['Authorization'], 'Bearer token-de-prueba');
    });

    test('exceso de fotos o foto demasiado grande: se rechaza ANTES de enviar', () async {
      var enviadas = 0;
      final cliente = MockClient((_) async {
        enviadas++;
        return json(201, {});
      });
      await expectLater(http.runWithClient(() => ReportesApi.reportar(3, fotos: List.generate(6, (i) => (nombre: 'f$i.jpg', bytes: jpeg))), () => cliente), throwsA(isA<ApiException>()));
      await expectLater(http.runWithClient(() => ReportesApi.reportar(3, fotos: [(nombre: 'g.jpg', bytes: deTamano(8000001))]), () => cliente), throwsA(isA<ApiException>()));
      expect(enviadas, 0);
    });

    test('historial vacío y con solicitudes', () async {
      expect(await http.runWithClient(() => HistorialApi.misSolicitudes(), () => MockClient((_) async => json(200, {'solicitudes': []}))), isEmpty);
      final lista = await http.runWithClient(() => HistorialApi.misSolicitudes(), () => MockClient((_) async => json(200, {
            'solicitudes': [
              {
                'id': 3, 'estado': 'REALIZADO', 'fechaProgramada': '2026-11-24T10:00:00.000Z', 'realizadoEn': '2026-11-24T13:00:00.000Z',
                'servicio': 'Limpieza general', 'direccion': 'Calle 1', 'trabajador': {'id': 9, 'nombre': 'Rosa'}, 'miResena': null,
                'calificarHasta': '2026-12-01T13:00:00.000Z', 'puedeCalificar': true, 'puedeReportar': true,
              }
            ]
          })));
      expect(lista.single.puedeCalificar, isTrue);
      expect(lista.single.trabajadorNombre, 'Rosa');
    });

    test('acceso no autorizado (403): mensaje claro, sin datos', () async {
      try {
        await http.runWithClient(() => ResenasApi.resenasDeTrabajador(9), () => MockClient((_) async => json(403, {'mensaje': 'x', 'codigo': 'PERMISO_REQUERIDO'})));
        fail('debió fallar');
      } on ApiException catch (e) {
        expect(mensajeDeError(e), contains('permiso'));
      }
    });
  });

  group('Pantalla de calificar', () {
    testWidgets('doble envío: dos toques rápidos generan UNA sola petición', (tester) async {
      var peticiones = 0;
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: const CalificarScreen(solicitudId: 3, nombre: 'Rosa')));
        final escoba = find.byIcon(Icons.cleaning_services_outlined).last;
        await tester.ensureVisible(escoba);
        await tester.pump();
        await tester.tap(escoba);
        await tester.pump();
        final boton = find.text('Enviar calificación');
        await tester.ensureVisible(boton);
        await tester.tap(boton);
        await tester.tap(boton, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 100));
      }, () => MockClient((_) async {
            peticiones++;
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return json(201, {'resena': resenaPropia()});
          }));
      await tester.pumpAndSettle();
      expect(peticiones, 1);
    });

    testWidgets('servicio no elegible: muestra el aviso y bloquea el botón', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: const CalificarScreen(solicitudId: 3, nombre: 'Rosa')));
        final escoba = find.byIcon(Icons.cleaning_services_outlined).last;
        await tester.ensureVisible(escoba);
        await tester.pump();
        await tester.tap(escoba);
        await tester.pump();
        final boton = find.text('Enviar calificación');
        await tester.ensureVisible(boton);
        await tester.tap(boton);
        await tester.pump(const Duration(milliseconds: 100));
      }, () => MockClient((_) async => json(409, {'mensaje': 'x', 'codigo': 'PLAZO_VENCIDO'})));
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('ya venció'), findsWidgets);
    });
  });
}
