import 'api_client.dart';
import 'resenas_reportes_api.dart';

// ════════════════════════════════════════════════════════════════════
// Historial y selección manual — audiencia CLIENTE (Fase 3b, docs/backend/23).
//   GET /api/cliente/solicitudes
//   GET /api/cliente/trabajadores?servicioId=
// La identidad sale del token: nunca se envía el id del usuario.
// ════════════════════════════════════════════════════════════════════

/// Reseña que el cliente escribió para esa solicitud.
class MiResena {
  MiResena.fromJson(Map<String, dynamic> j)
      : puntuacion = j['puntuacion'] as int,
        comentario = j['comentario'] as String?,
        fecha = DateTime.parse(j['fecha'] as String),
        eliminadaPorModeracion = j['eliminadaPorModeracion'] as bool;

  final int puntuacion;
  final String? comentario;
  final DateTime fecha;
  final bool eliminadaPorModeracion;
}

/// Una solicitud del cliente con lo necesario para calificar o reportar.
class SolicitudCliente {
  SolicitudCliente.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        estado = j['estado'] as String,
        fechaProgramada = DateTime.parse(j['fechaProgramada'] as String),
        realizadoEn = j['realizadoEn'] == null ? null : DateTime.parse(j['realizadoEn'] as String),
        servicio = j['servicio'] as String,
        direccion = j['direccion'] as String,
        trabajadorId = (j['trabajador'] as Map<String, dynamic>?)?['id'] as int?,
        trabajadorNombre = (j['trabajador'] as Map<String, dynamic>?)?['nombre'] as String?,
        miResena = j['miResena'] == null ? null : MiResena.fromJson(j['miResena'] as Map<String, dynamic>),
        calificarHasta = j['calificarHasta'] == null ? null : DateTime.parse(j['calificarHasta'] as String),
        puedeCalificar = j['puedeCalificar'] as bool,
        puedeReportar = j['puedeReportar'] as bool;

  final int id;
  final String estado;
  final DateTime fechaProgramada;
  final DateTime? realizadoEn;
  final String servicio;
  final String direccion;
  final int? trabajadorId;
  final String? trabajadorNombre;
  final MiResena? miResena;
  final DateTime? calificarHasta;

  /// Indicaciones del servidor para la interfaz (el servidor vuelve a validar al enviar).
  final bool puedeCalificar;
  final bool puedeReportar;

  bool get finalizada => estado == 'REALIZADO';
  bool get activa => const ['PENDIENTE', 'CONFIRMADO', 'EN_PROCESO'].contains(estado);
}

/// Trabajador de la selección manual (activo y verificado) con sus estrellas.
class TrabajadorSeleccionable {
  TrabajadorSeleccionable.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nombre = j['nombre'] as String,
        especialidades = [for (final e in j['especialidades'] as List) e as String],
        reputacion = Reputacion.fromJson(j['reputacion'] as Map<String, dynamic>);

  final int id;
  final String nombre;
  final List<String> especialidades;
  final Reputacion reputacion;
}

class HistorialApi {
  HistorialApi._();

  static Future<List<SolicitudCliente>> misSolicitudes() async {
    final data = await ApiClient.get('/api/cliente/solicitudes') as Map<String, dynamic>;
    return [for (final s in data['solicitudes'] as List) SolicitudCliente.fromJson(s as Map<String, dynamic>)];
  }

  /// Con [servicioId] y [fecha], solo los que tienen las especialidades y no tienen otro servicio
  /// que se cruce (docs/backend/25 v2). Al crear la solicitud el servidor vuelve a validarlo.
  static Future<List<TrabajadorSeleccionable>> trabajadores({int? servicioId, DateTime? fecha}) async {
    final q = [if (servicioId != null) 'servicioId=$servicioId', if (fecha != null) 'fecha=${Uri.encodeQueryComponent(fecha.toUtc().toIso8601String())}'];
    final ruta = q.isEmpty ? '/api/cliente/trabajadores' : '/api/cliente/trabajadores?${q.join('&')}';
    final data = await ApiClient.get(ruta) as Map<String, dynamic>;
    return [for (final t in data['trabajadores'] as List) TrabajadorSeleccionable.fromJson(t as Map<String, dynamic>)];
  }
}

/// Etiqueta legible del estado de una solicitud.
String etiquetaDeEstado(String estado) => switch (estado) {
      'PENDIENTE' => 'Pendiente',
      'CONFIRMADO' => 'Confirmada',
      'EN_PROCESO' => 'En proceso',
      'REALIZADO' => 'Finalizada',
      'CANCELADO' => 'Cancelada',
      'RECHAZADO' => 'Rechazada',
      _ => estado,
    };

/// Etiqueta legible del tipo de reporte.
const Map<String, String> kTiposDeReporte = {
  'NO_SE_PUDO_COMPLETAR': 'No se pudo completar',
  'INASISTENCIA': 'Inasistencia',
  'PROBLEMA_UBICACION': 'Problema con la ubicación',
  'UBICACION_FALSA': 'Ubicación falsa',
  'OTRO': 'Otro',
};

const Map<String, String> kEstadosDeReporte = {
  'ABIERTO': 'Abierto',
  'EN_REVISION': 'En revisión',
  'RESUELTO': 'Resuelto',
};

String fechaCorta(DateTime d) {
  final l = d.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(l.day)}/${dos(l.month)}/${l.year} ${dos(l.hour)}:${dos(l.minute)}';
}

const List<String> kMeses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
