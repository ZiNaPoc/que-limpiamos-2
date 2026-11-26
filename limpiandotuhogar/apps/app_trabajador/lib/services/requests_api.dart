import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'resenas_reportes_api.dart';

// ════════════════════════════════════════════════════════════════════
// Solicitudes REALES del trabajador — ciclo sin dinero (docs/backend/25 v2).
//   GET  /api/trabajador/solicitudes/disponibles   invitaciones pendientes + bolsa en la que es elegible
//   GET  /api/trabajador/solicitudes               asignadas e invitaciones vigentes
//   POST /api/trabajador/solicitudes/:id/aceptar · /rechazar · /iniciar · /cancelar
//   POST /api/trabajador/solicitudes/:id/terminar  multipart, campo "fotos" (1 a 5)
// Sustituye a las rutas obsoletas /galaxias y /hoyo-negro (no existen en el backend, D12).
// Sin negociación: el precio lo calcula QueLimpiamos y el trabajador solo acepta o rechaza.
// ════════════════════════════════════════════════════════════════════

/// Datos del inmueble (copia guardada en la solicitud).
class RemoteHouse {
  const RemoteHouse({
    required this.tipo,
    required this.habitaciones,
    required this.banos,
    required this.mediosBanos,
    required this.pisos,
  });

  final String tipo;
  final int habitaciones;
  final int banos;
  final int mediosBanos;
  final int pisos;

  factory RemoteHouse.fromJson(Map<String, dynamic> j) => RemoteHouse(
        tipo: (j['tipo'] as String?) ?? 'CASA',
        habitaciones: (j['habitaciones'] as int?) ?? 0,
        banos: (j['banos'] as int?) ?? 0,
        mediosBanos: (j['mediosBanos'] as int?) ?? 0,
        pisos: (j['pisos'] as int?) ?? 1,
      );
}

/// Una solicitud real tal como la ve el trabajador (vista del servidor).
class RemoteRequest {
  const RemoteRequest({
    required this.id,
    required this.estado,
    required this.relacion,
    required this.servicio,
    required this.fecha,
    required this.duracionMin,
    required this.total,
    required this.clienteNombre,
    required this.casa,
    required this.areas,
    required this.extras,
    required this.notas,
    required this.direccion,
    required this.trabajadorTerminoEn,
    required this.puedeIniciar,
    required this.motivoNoIniciar,
    required this.puedeCancelar,
    required this.motivoNoCancelar,
  });

  final int id;

  /// Estado del servidor: PENDIENTE, CONFIRMADO, EN_PROCESO, REALIZADO, CANCELADO…
  final String estado;

  /// INVITADO, BOLSA o ASIGNADO.
  final String relacion;
  final String servicio;
  final DateTime fecha;
  final int duracionMin;

  /// Lo que pagará el cliente en efectivo (calculado por el servidor).
  final double total;
  final String clienteNombre;
  final RemoteHouse casa;
  final List<String> areas;
  final List<({String nombre, double precio})> extras;
  final String notas;

  /// Solo si está asignado (antes de aceptar no se ve la dirección exacta).
  final String? direccion;
  final DateTime? trabajadorTerminoEn;
  final bool puedeIniciar;
  final String? motivoNoIniciar;
  final bool puedeCancelar;
  final String? motivoNoCancelar;

  bool get disponible => relacion != 'ASIGNADO' && estado == 'PENDIENTE';

  factory RemoteRequest.fromJson(Map<String, dynamic> j) {
    final acciones = (j['acciones'] as Map<String, dynamic>?) ?? const {};
    final marcas = (j['marcas'] as Map<String, dynamic>?) ?? const {};
    return RemoteRequest(
      id: j['id'] as int,
      estado: j['estado'] as String,
      relacion: (j['relacion'] as String?) ?? 'BOLSA',
      servicio: (j['servicio'] as String?) ?? 'Limpieza',
      fecha: DateTime.parse(j['fechaProgramada'] as String).toLocal(),
      duracionMin: (j['duracionMin'] as int?) ?? 180,
      total: ((j['precio'] as num?) ?? 0).toDouble(),
      clienteNombre: ((j['cliente'] as Map<String, dynamic>?)?['nombre'] as String?) ?? 'Cliente',
      casa: RemoteHouse.fromJson((j['inmueble'] as Map<String, dynamic>?) ?? const {}),
      areas: [for (final a in (j['areas'] as List?) ?? const []) a.toString()],
      extras: [
        for (final e in (j['extras'] as List?) ?? const [])
          (nombre: (e as Map<String, dynamic>)['nombre'] as String, precio: ((e['precio'] as num?) ?? 0).toDouble()),
      ],
      notas: (j['notas'] as String?) ?? '',
      direccion: j['direccion'] as String?,
      trabajadorTerminoEn: marcas['trabajadorTerminoEn'] == null ? null : DateTime.parse(marcas['trabajadorTerminoEn'] as String).toLocal(),
      puedeIniciar: (acciones['puedeIniciar'] as bool?) ?? false,
      motivoNoIniciar: acciones['motivoNoIniciar'] as String?,
      puedeCancelar: (acciones['puedeCancelar'] as bool?) ?? false,
      motivoNoCancelar: acciones['motivoNoCancelar'] as String?,
    );
  }
}

class RequestsApi {
  RequestsApi._();

  static List<RemoteRequest> _parseList(dynamic lista, String origen) {
    final out = <RemoteRequest>[];
    for (final e in (lista as List?) ?? const []) {
      try {
        out.add(RemoteRequest.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('[api] $origen: fila ignorada -> $err');
      }
    }
    return out;
  }

  /// Invitaciones pendientes y solicitudes de la bolsa en las que es elegible.
  static Future<List<RemoteRequest>> disponibles() async {
    final data = await ApiClient.get('/api/trabajador/solicitudes/disponibles') as Map<String, dynamic>;
    return _parseList(data['solicitudes'], 'disponibles');
  }

  /// Las que tiene asignadas (para restaurar la agenda y seguir su estado).
  static Future<List<RemoteRequest>> asignadas() async {
    final data = await ApiClient.get('/api/trabajador/solicitudes') as Map<String, dynamic>;
    return _parseList(data['solicitudes'], 'asignadas').where((r) => r.relacion == 'ASIGNADO').toList();
  }

  /// Aceptar. 409 si ya la tomó otro, si se cruza con otro servicio o si ya no está disponible.
  static Future<RemoteRequest> aceptar(int id) async {
    final data = await ApiClient.post('/api/trabajador/solicitudes/$id/aceptar') as Map<String, dynamic>;
    return RemoteRequest.fromJson(data['solicitud'] as Map<String, dynamic>);
  }

  /// Rechazar (definitivo para esa solicitud). Si era invitación, el servidor avisa al cliente.
  static Future<void> rechazar(int id) => ApiClient.post('/api/trabajador/solicitudes/$id/rechazar');

  /// Iniciar: de 30 min antes a 30 min después de la hora programada.
  static Future<RemoteRequest> iniciar(int id) async {
    final data = await ApiClient.post('/api/trabajador/solicitudes/$id/iniciar') as Map<String, dynamic>;
    return RemoteRequest.fromJson(data['solicitud'] as Map<String, dynamic>);
  }

  /// Cancelar sin cargo (confirmada, con 24 h o más). La solicitud vuelve a la bolsa.
  static Future<void> cancelar(int id, String motivo) => ApiClient.post('/api/trabajador/solicitudes/$id/cancelar', {'motivo': motivo});

  /// «Terminado» con 1 a 5 fotos (JPEG, PNG o WebP; 8 MB cada una, 16 MB en total).
  static Future<void> terminar(int id, List<FotoDeReporte> fotos) async {
    if (fotos.isEmpty) throw ApiException('Sube al menos 1 fotografía del trabajo terminado.');
    if (fotos.length > ReportesApi.maxFotos) throw ApiException('Máximo ${ReportesApi.maxFotos} fotografías.');
    if (fotos.any((f) => f.bytes.length > ReportesApi.maxBytesPorFoto)) throw ApiException('Cada fotografía puede pesar como máximo 8 MB.');
    if (fotos.fold<int>(0, (s, f) => s + f.bytes.length) > ReportesApi.maxBytesTotales) throw ApiException('Las fotografías pueden sumar como máximo 16 MB.');
    final request = http.MultipartRequest('POST', Uri.parse('${ApiClient.baseUrl}/api/trabajador/solicitudes/$id/terminar'));
    if (ApiClient.token != null) request.headers['Authorization'] = 'Bearer ${ApiClient.token}';
    for (final f in fotos) {
      request.files.add(http.MultipartFile.fromBytes('fotos', f.bytes, filename: f.nombre));
    }
    await ReportesApi.enviarMultipart(request);
  }
}
