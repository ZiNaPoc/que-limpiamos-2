import 'api_client.dart'; 
import '../screens/service_request_data.dart';

class SolicitudApi {
  SolicitudApi._();

  static const String _rutaGalaxias = '/galaxias';
  static const String _rutaSolicitudes = '/hoyo-negro';

  /// [clienteId] 
  /// Lanza [ApiException] 
  static Future<int?> crear(
    ServiceRequestData req, {
    required int clienteId,
  }) async {
    final scheduled = req.scheduledAt;
    if (scheduled == null) {
      throw ApiException('Falta elegir la fecha y la hora del servicio.');
    }
    final p = req.property;

    
    final galaxia = await ApiClient.post(_rutaGalaxias, {
      'tipo': p.apiType, 
      'habitaciones': p.rooms,
      'banos': p.fullBaths,
      'medios_banos': p.halfBaths,
      'pisos': p.floors,
    });
    final galaxiaId = _extractId(galaxia);
    if (galaxiaId == null) {
      throw ApiException('El servidor no devolvió el id del inmueble.');
    }

    // ── 2) Solicitud ─────────────────────────────────────────────
    final res = await ApiClient.post(_rutaSolicitudes, {
      'cliente_id': clienteId,
      'id_galaxias': galaxiaId,
      'fecha': scheduled.toUtc().toIso8601String(),
      'total': req.priceMin,
      'seleccion': {
        'tipoLimpieza': req.serviceTitle,
        'descripcion': req.notes,
        'notas': req.notes,
        'areas': req.areas,
        'servicioExtra': req.extras.isEmpty ? null : req.extras.join(', '),
        'precioExtra': req.extrasTotal,
        'detallesExtra': req.extras,
        'direccion': p.address,
        'zona': '',
        'metros2': null,
        'duracionHoras': 3, // valor temporal
        if (req.collaborator != null) 'colaborador': req.collaborator,
      },
    });
    return _extractId(res);
  }

  /// Busca un `id` entero en la respuesta, aunque venga anidado
  /// (por ejemplo `{ "galaxia": { "id": 7 } }` o `{ "id": 7 }`).
  static int? _extractId(dynamic data) {
    if (data is Map) {
      final direct = data['id'];
      if (direct is int) return direct;
      if (direct is String) return int.tryParse(direct);
      for (final v in data.values) {
        if (v is Map) {
          final nested = _extractId(v);
          if (nested != null) return nested;
        }
      }
    }
    return null;
  }
}