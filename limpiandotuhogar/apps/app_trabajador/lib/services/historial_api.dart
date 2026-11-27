import 'api_client.dart';

// ════════════════════════════════════════════════════════════════════
// Servicios del trabajador — GET /api/trabajador/solicitudes (Fase 3b, docs/backend/23).
// Asignados e invitaciones vigentes, con lo necesario para calificar, reportar y
// ver la reputación del cliente. La identidad sale del token.
// ════════════════════════════════════════════════════════════════════

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

class SolicitudTrabajador {
  SolicitudTrabajador.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        estado = j['estado'] as String,
        asignado = j['relacion'] == 'ASIGNADO',
        invitacion = j['invitacion'] as String?,
        fechaProgramada = DateTime.parse(j['fechaProgramada'] as String),
        realizadoEn = j['realizadoEn'] == null ? null : DateTime.parse(j['realizadoEn'] as String),
        servicio = j['servicio'] as String,
        clienteNombre = (j['cliente'] as Map<String, dynamic>)['nombre'] as String,
        miResena = j['miResena'] == null ? null : MiResena.fromJson(j['miResena'] as Map<String, dynamic>),
        calificarHasta = j['calificarHasta'] == null ? null : DateTime.parse(j['calificarHasta'] as String),
        puedeCalificar = j['puedeCalificar'] as bool,
        puedeReportar = j['puedeReportar'] as bool,
        puedeVerReputacionCliente = j['puedeVerReputacionCliente'] as bool;

  final int id;
  final String estado;
  final bool asignado;
  final String? invitacion;
  final DateTime fechaProgramada;
  final DateTime? realizadoEn;
  final String servicio;
  final String clienteNombre;
  final MiResena? miResena;
  final DateTime? calificarHasta;

  /// Indicaciones del servidor para la interfaz (el servidor vuelve a validar al enviar).
  final bool puedeCalificar;
  final bool puedeReportar;
  final bool puedeVerReputacionCliente;
}

class HistorialApi {
  HistorialApi._();

  static Future<List<SolicitudTrabajador>> misSolicitudes() async {
    final data = await ApiClient.get('/api/trabajador/solicitudes') as Map<String, dynamic>;
    return [for (final s in data['solicitudes'] as List) SolicitudTrabajador.fromJson(s as Map<String, dynamic>)];
  }
}

String etiquetaDeEstado(String estado) => switch (estado) {
      'PENDIENTE' => 'Pendiente',
      'CONFIRMADO' => 'Confirmada',
      'EN_PROCESO' => 'En proceso',
      'REALIZADO' => 'Finalizada',
      'CANCELADO' => 'Cancelada',
      'RECHAZADO' => 'Rechazada',
      _ => estado,
    };

/// Tipos de reporte del trabajador. PAGO_EN_DISPUTA solo dentro del plazo de reporte del pago (D61).
const Map<String, String> kTiposDeReporte = {
  'NO_SE_PUDO_COMPLETAR': 'No se pudo completar',
  'INASISTENCIA': 'El cliente no estaba',
  'PROBLEMA_UBICACION': 'Problema con la ubicación',
  'UBICACION_FALSA': 'Ubicación falsa',
  'PAGO_EN_DISPUTA': 'No recibí el pago',
  'OTRO': 'Otro',
};

const Map<String, String> kEstadosDeReporte = {'ABIERTO': 'Abierto', 'EN_REVISION': 'En revisión', 'RESUELTO': 'Resuelto'};

String fechaCorta(DateTime d) {
  final l = d.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(l.day)}/${dos(l.month)}/${l.year} ${dos(l.hour)}:${dos(l.minute)}';
}

const List<String> kMeses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
