import '../screens/service_request_data.dart';
import 'ciclo_api.dart';

/// Envío de la solicitud al backend (docs/backend/25 v2).
///
/// Antes se usaban las rutas obsoletas `/galaxias` y `/hoyo-negro` (no existen en el backend
/// actual, D12). Ahora: `POST /api/cliente/solicitudes`. La identidad sale del token, el precio
/// lo calcula el servidor y el inmueble se copia en la solicitud.
class SolicitudApi {
  SolicitudApi._();

  /// Devuelve el id de la solicitud creada. Lanza [ApiException] con el mensaje del servidor
  /// (p. ej. IDENTIDAD_NO_VERIFICADA si la INE no está aprobada).
  static Future<int> crear(ServiceRequestData req) => CicloApi.crear(req);
}
