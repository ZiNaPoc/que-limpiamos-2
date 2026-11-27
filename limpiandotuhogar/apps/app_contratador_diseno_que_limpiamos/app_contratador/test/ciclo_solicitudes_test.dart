import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_contratador/screens/service_request_data.dart';
import 'package:app_contratador/services/api_client.dart';
import 'package:app_contratador/services/ciclo_api.dart';

// Ciclo de las solicitudes sin dinero (docs/backend/25 v2) — app del cliente. Servidor SIMULADO
// solo en la prueba (http.runWithClient): se comprueba lo que la app ENVÍA y cómo lee lo que recibe.

http.Response json(int status, Object cuerpo) => http.Response(jsonEncode(cuerpo), status, headers: {'content-type': 'application/json; charset=utf-8'});

final catalogo = {
  'servicios': [
    {'id': 30001, 'nombre': 'Limpieza regular', 'descripcion': 'x', 'precioBase': 400, 'duracionMin': 180, 'especialidades': []},
  ],
  'areas': [
    {'id': 1, 'nombre': 'Cocina'},
    {'id': 2, 'nombre': 'Sala'},
  ],
  'extras': [
    {'id': 5, 'nombre': 'Limpieza de ventanas', 'descripcion': null, 'precio': 300, 'duracionMin': 0},
  ],
};

ServiceRequestData pedido({PropertyData property = const PropertyData(type: 'Departamento', rooms: 2, fullBaths: 1, halfBaths: 1, floors: 1, address: 'Av. Tulum 200'), int? colaborador}) => ServiceRequestData(
      serviceTitle: 'Limpieza regular',
      areas: const ['Cocina', 'Sala'],
      extras: const ['Limpieza de ventanas'],
      notes: 'Hay un perro',
      priceMin: 700,
      priceMax: 700,
      property: property,
      date: DateTime(2026, 12, 20),
      time: const TimeOfDay(hour: 10, minute: 0),
      collaboratorId: colaborador,
    );

Map<String, dynamic> detalle({String estado = 'PENDIENTE', Map<String, dynamic>? acciones}) => {
      'id': 9, 'estado': estado, 'modo': 'INVITACION', 'servicio': 'Limpieza regular',
      'fechaProgramada': '2026-12-20T16:00:00.000Z', 'finEstimado': '2026-12-20T19:00:00.000Z', 'duracionMin': 180,
      'inmueble': {'nombre': 'Airbnb Centro', 'tipo': 'DEPARTAMENTO', 'habitaciones': 2, 'banos': 1, 'mediosBanos': 1, 'pisos': 1},
      'areas': ['Cocina'], 'extras': [], 'notas': null, 'precio': 700, 'metodoPago': 'EFECTIVO',
      'marcas': {'trabajadorTerminoEn': null, 'clienteConfirmoEn': null, 'confirmacionSolicitadaEn': null, 'avisoEvidenciaEn': null, 'realizadoEn': null, 'realizadoVia': null},
      'fotosTerminado': [{'id': 44, 'tipoMime': 'image/jpeg', 'tamanoBytes': 10, 'fecha': '2026-12-20T18:00:00.000Z'}],
      'creadaEn': '2026-12-01T00:00:00.000Z', 'direccion': 'Av. Tulum 200', 'trabajador': null,
      'invitaciones': [{'trabajador': {'id': 1, 'nombre': 'Rosa'}, 'estado': 'RECHAZADA', 'motivoCierre': null, 'respondidaEn': '2026-12-02T00:00:00.000Z'}],
      'invitacionRechazada': {'trabajador': 'Rosa'}, 'reporteEnRevision': false,
      'acciones': acciones ?? {'puedeCancelar': true, 'motivoNoCancelar': null, 'puedeEnviarABolsa': true, 'puedeInvitarOtro': true, 'puedeConfirmar': false},
    };

void main() {
  final peticiones = <http.Request>[];
  MockClient servidor(http.Response Function(http.Request r) responder) => MockClient((r) async {
        peticiones.add(r);
        if (r.url.path == '/api/cliente/catalogo') return json(200, catalogo);
        return responder(r);
      });

  setUp(() => peticiones.clear());

  test('cotizar: manda ids del catálogo, la fecha en UTC y el inmueble capturado; NUNCA un precio', () async {
    final c = await http.runWithClient(() => CicloApi.cotizar(pedido()), () => servidor((r) => json(200, {
          'cotizacion': {'precio': {'base': 400, 'extras': 300, 'total': 700, 'moneda': 'MXN'}, 'duracionMin': 180, 'finEstimado': '2026-12-20T19:00:00.000Z'},
        })));
    expect(c.total, 700);
    expect(c.duracionMin, 180);
    final cuerpo = jsonDecode(peticiones.last.body) as Map<String, dynamic>;
    expect(peticiones.last.url.path, '/api/cliente/cotizaciones');
    expect(cuerpo['servicioId'], 30001);
    expect(cuerpo['areaIds'], [1, 2]);
    expect(cuerpo['extraIds'], [5]);
    expect(cuerpo['fechaProgramada'], DateTime(2026, 12, 20, 10).toUtc().toIso8601String());
    expect((cuerpo['inmueble'] as Map)['tipo'], 'DEPARTAMENTO');
    expect(cuerpo.containsKey('total'), isFalse, reason: 'el precio lo calcula el servidor (D4)');
    expect(cuerpo.containsKey('precio'), isFalse);
  });

  test('crear: con colaborador manda trabajadorId; con inmueble guardado manda inmuebleId; con guardarComo lo pide guardar', () async {
    final guardado = pedido(property: const PropertyData(address: 'x', inmuebleId: 12, alias: 'Casa Playa'), colaborador: 3);
    final id = await http.runWithClient(() => CicloApi.crear(guardado), () => servidor((r) => json(201, {'solicitud': detalle()})));
    expect(id, 9);
    var cuerpo = jsonDecode(peticiones.last.body) as Map<String, dynamic>;
    expect(peticiones.last.url.path, '/api/cliente/solicitudes');
    expect(cuerpo['trabajadorId'], 3);
    expect(cuerpo['inmuebleId'], 12);
    expect(cuerpo.containsKey('inmueble'), isFalse);

    final nuevo = pedido(property: const PropertyData(address: 'Calle Nueva 1', guardarComo: 'Oficina'));
    await http.runWithClient(() => CicloApi.crear(nuevo), () => servidor((r) => json(201, {'solicitud': detalle()})));
    cuerpo = jsonDecode(peticiones.last.body) as Map<String, dynamic>;
    expect(cuerpo.containsKey('trabajadorId'), isFalse, reason: 'sin colaborador → bolsa');
    expect((cuerpo['inmueble'] as Map)['guardarComo'], 'Oficina');
  });

  test('crear sin la INE aprobada: el error del servidor llega con su código', () async {
    Object? error;
    try {
      await http.runWithClient(() => CicloApi.crear(pedido()), () => servidor((r) => json(403, {'mensaje': 'Para enviar una solicitud necesitas tener tu identidad (INE) aprobada.', 'codigo': 'IDENTIDAD_NO_VERIFICADA'})));
    } catch (e) {
      error = e;
    }
    expect(error, isA<ApiException>());
    expect((error as ApiException).codigo, 'IDENTIDAD_NO_VERIFICADA');
    expect(mensajeDelCiclo(error), contains('INE'));
  });

  test('detalle: lee el rechazo, las acciones del servidor y las fotos de «terminado»', () async {
    final d = await http.runWithClient(() => CicloApi.detalle(9), () => servidor((r) => json(200, {'solicitud': detalle()})));
    expect(d.rechazadaPor, 'Rosa');
    expect(d.puedeEnviarABolsa, isTrue);
    expect(d.puedeInvitarOtro, isTrue);
    expect(d.puedeConfirmar, isFalse);
    expect(d.inmuebleNombre, 'Airbnb Centro');
    expect(d.fotos.single.id, 44);
    final sinCancelar = DetalleSolicitud.fromJson(detalle(
      estado: 'CONFIRMADO',
      acciones: {'puedeCancelar': false, 'motivoNoCancelar': 'Con menos de 24 h…', 'puedeEnviarABolsa': false, 'puedeInvitarOtro': false, 'puedeConfirmar': false},
    ));
    expect(sinCancelar.puedeCancelar, isFalse);
    expect(sinCancelar.motivoNoCancelar, startsWith('Con menos de 24 h'));
  });

  test('acciones: bolsa, invitar a otro, cancelar y confirmar usan sus rutas', () async {
    await http.runWithClient(() async {
      await CicloApi.enviarABolsa(9);
      await CicloApi.invitar(9, 4);
      await CicloApi.cancelar(9, motivo: 'Cambio de planes');
      await CicloApi.confirmar(9);
    }, () => servidor((r) => json(200, {'solicitud': detalle()})));
    expect(peticiones.map((p) => '${p.method} ${p.url.path}').toList(), [
      'POST /api/cliente/solicitudes/9/bolsa',
      'POST /api/cliente/solicitudes/9/invitaciones',
      'POST /api/cliente/solicitudes/9/cancelar',
      'POST /api/cliente/solicitudes/9/confirmar',
    ]);
    expect(jsonDecode(peticiones[1].body), {'trabajadorId': 4});
  });

  test('Mis inmuebles: listar, crear (con nombre), editar y eliminar (DELETE)', () async {
    final inm = {'id': 12, 'nombre': 'Casa Playa', 'tipo': 'CASA', 'direccion': 'Zona Hotelera km 12', 'habitaciones': 3, 'banos': 2, 'mediosBanos': 0, 'pisos': 2, 'actualizadoEn': '2026-12-01T00:00:00.000Z'};
    await http.runWithClient(() async {
      final l = await InmueblesApi.listar();
      expect(l.single.nombre, 'Casa Playa');
      expect(l.single.resumen, contains('3 hab.'));
      await InmueblesApi.crear('Oficina', const PropertyData(type: 'Oficina', address: 'Calle 1', floors: 1));
      await InmueblesApi.editar(12, 'Casa Playa 2', const PropertyData(address: 'Zona Hotelera km 12'));
      await InmueblesApi.eliminar(12);
    }, () => servidor((r) => json(200, {'inmuebles': [inm], 'inmueble': inm, 'id': 12, 'eliminado': true})));
    expect(peticiones.map((p) => '${p.method} ${p.url.path}').toList(), ['GET /api/cliente/inmuebles', 'POST /api/cliente/inmuebles', 'PATCH /api/cliente/inmuebles/12', 'DELETE /api/cliente/inmuebles/12']);
    expect((jsonDecode(peticiones[1].body) as Map)['nombre'], 'Oficina');
    expect((jsonDecode(peticiones[1].body) as Map)['tipo'], 'OFICINA');
  });

  test('avisos: lista y no leídos', () async {
    final (noLeidas, lista) = await http.runWithClient(() => NotificacionesApi.listar(), () => servidor((r) => json(200, {
          'noLeidas': 1,
          'notificaciones': [
            {'id': 1, 'solicitudId': 9, 'tipo': 'INVITACION_RECHAZADA', 'titulo': 'Tu invitación fue rechazada', 'mensaje': 'x', 'leida': false, 'fecha': '2026-12-02T00:00:00.000Z'},
          ],
        })));
    expect(noLeidas, 1);
    expect(lista.single.solicitudId, 9);
  });
}
