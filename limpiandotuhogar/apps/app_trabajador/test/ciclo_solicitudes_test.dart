import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:que_limpiamos_trabajadores/services/api_client.dart';
import 'package:que_limpiamos_trabajadores/services/app_state.dart';
import 'package:que_limpiamos_trabajadores/services/requests_api.dart';

// Ciclo de las solicitudes sin dinero (docs/backend/25 v2) — app del TRABAJADOR. Servidor
// SIMULADO solo en la prueba (http.runWithClient): rutas nuevas (no /hoyo-negro) y lectura de la vista.

http.Response json(int status, Object cuerpo) => http.Response(jsonEncode(cuerpo), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> vista({String relacion = 'INVITADO', String estado = 'PENDIENTE', String? direccion}) => {
      'id': 21, 'estado': estado, 'modo': 'INVITACION', 'relacion': relacion, 'servicio': 'Limpieza regular',
      'fechaProgramada': '2026-12-20T16:00:00.000Z', 'finEstimado': '2026-12-20T19:00:00.000Z', 'duracionMin': 180,
      'inmueble': {'nombre': null, 'tipo': 'DEPARTAMENTO', 'habitaciones': 2, 'banos': 1, 'mediosBanos': 1, 'pisos': 1},
      'areas': ['Cocina', 'Sala'], 'extras': [{'nombre': 'Limpieza de ventanas', 'precio': 300}], 'notas': 'Perro amistoso',
      'precio': 700, 'metodoPago': 'EFECTIVO', 'direccion': direccion, 'cliente': {'nombre': 'Ana Cliente'}, 'gananciaEstimada': 595,
      'marcas': {'trabajadorTerminoEn': null}, 'fotosTerminado': [], 'creadaEn': '2026-12-01T00:00:00.000Z',
      'ventanaInicio': null,
      'acciones': {'puedeAceptar': true, 'puedeRechazar': true, 'puedeIniciar': false, 'motivoNoIniciar': null, 'puedeTerminar': false, 'puedeCancelar': false, 'motivoNoCancelar': null},
    };

void main() {
  final peticiones = <http.BaseRequest>[];
  MockClient servidor(http.Response Function(http.Request r) responder) => MockClient((r) async {
        peticiones.add(r);
        return responder(r);
      });
  setUp(peticiones.clear);

  test('disponibles: usa la ruta nueva y lee invitado/bolsa sin la dirección exacta', () async {
    final lista = await http.runWithClient(RequestsApi.disponibles, () => servidor((r) => json(200, {'verificado': true, 'solicitudes': [vista(), vista(relacion: 'BOLSA')]})));
    expect(peticiones.single.url.path, '/api/trabajador/solicitudes/disponibles');
    expect(lista, hasLength(2));
    final r = lista.first;
    expect(r.disponible, isTrue);
    expect(r.relacion, 'INVITADO');
    expect(r.total, 700);
    expect(r.direccion, isNull, reason: 'la dirección exacta llega solo al estar asignada');
    expect(r.casa.tipo, 'DEPARTAMENTO');
    expect(r.extras.single.nombre, 'Limpieza de ventanas');
  });

  test('aceptar, rechazar, iniciar y cancelar llaman a sus rutas (ninguna obsoleta)', () async {
    await http.runWithClient(() async {
      await RequestsApi.aceptar(21);
      await RequestsApi.rechazar(21);
      await RequestsApi.iniciar(21);
      await RequestsApi.cancelar(21, 'Tuve un imprevisto');
    }, () => servidor((r) => json(200, {'solicitud': vista(relacion: 'ASIGNADO', estado: 'CONFIRMADO', direccion: 'Av. Tulum 200')})));
    expect(peticiones.map((p) => '${p.method} ${p.url.path}').toList(), [
      'POST /api/trabajador/solicitudes/21/aceptar',
      'POST /api/trabajador/solicitudes/21/rechazar',
      'POST /api/trabajador/solicitudes/21/iniciar',
      'POST /api/trabajador/solicitudes/21/cancelar',
    ]);
    expect(peticiones.any((p) => p.url.path.contains('hoyo-negro') || p.url.path.contains('galaxias')), isFalse);
  });

  test('aceptar cuando otro ya la tomó: el 409 llega con su código', () async {
    Object? error;
    try {
      await http.runWithClient(() => RequestsApi.aceptar(21), () => servidor((r) => json(409, {'mensaje': 'Otro colaborador ya tomó esta solicitud', 'codigo': 'SOLICITUD_YA_TOMADA'})));
    } catch (e) {
      error = e;
    }
    expect((error as ApiException).codigo, 'SOLICITUD_YA_TOMADA');
  });

  test('terminar: exige al menos 1 foto y manda multipart con el campo "fotos"', () async {
    await expectLater(RequestsApi.terminar(21, const []), throwsA(isA<ApiException>()));
    await http.runWithClient(
      () => RequestsApi.terminar(21, [(nombre: 'a.jpg', bytes: [0xFF, 0xD8, 0xFF, 1]), (nombre: 'b.jpg', bytes: [0xFF, 0xD8, 0xFF, 2])]),
      () => MockClient.streaming((r, cuerpo) async {
        peticiones.add(r);
        final texto = utf8.decode(await cuerpo.toBytes(), allowMalformed: true);
        expect(r.headers['content-type'], startsWith('multipart/form-data'));
        expect('name="fotos"'.allMatches(texto).length, 2);
        return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'solicitud': vista(relacion: 'ASIGNADO', estado: 'EN_PROCESO')}))), 200, headers: {'content-type': 'application/json'});
      }),
    );
    expect(peticiones.single.url.path, '/api/trabajador/solicitudes/21/terminar');
  });

  test('asignadas: solo las que tiene ASIGNADAS (no las invitaciones)', () async {
    final lista = await http.runWithClient(RequestsApi.asignadas, () => servidor((r) => json(200, {'solicitudes': [vista(), vista(relacion: 'ASIGNADO', estado: 'CONFIRMADO', direccion: 'Av. Tulum 200')]})));
    expect(lista.single.relacion, 'ASIGNADO');
    expect(lista.single.direccion, 'Av. Tulum 200');
  });

  test('las solicitudes de demostración no se tratan como reales', () {
    final s = AppState();
    final demo = s.requests.first;
    expect(s.isRemote(demo), isFalse);
    expect(s.canPropose(demo).reason, isNot(contains('QueLimpiamos')));
  });
}
