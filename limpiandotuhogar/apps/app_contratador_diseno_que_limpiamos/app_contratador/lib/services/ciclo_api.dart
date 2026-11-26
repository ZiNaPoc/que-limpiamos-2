import 'api_client.dart';
import '../screens/service_request_data.dart';

// ════════════════════════════════════════════════════════════════════
// Ciclo de las solicitudes sin dinero — audiencia CLIENTE (docs/backend/25 v2).
//   GET  /api/cliente/catalogo                    servicios, áreas y extras con sus ids
//   POST /api/cliente/cotizaciones                precio y duración del SERVIDOR (no crea nada)
//   POST /api/cliente/solicitudes                 crear (INE verificada; invitación o bolsa)
//   GET  /api/cliente/solicitudes/:id             detalle con las acciones permitidas
//   POST /api/cliente/solicitudes/:id/bolsa · /invitaciones · /cancelar · /confirmar
//   GET  /api/cliente/solicitudes/:id/evidencias/:evidenciaId   URL temporal (60 s)
//   GET|POST /api/cliente/inmuebles · PATCH|DELETE /api/cliente/inmuebles/:id
//   GET  /api/cliente/notificaciones · POST /notificaciones/:id/leida · /notificaciones/leidas
// El precio SIEMPRE lo calcula el servidor (D4). Pago solo en efectivo (D50). Sin chat.
// ════════════════════════════════════════════════════════════════════

/// Catálogo real (ids del servidor). La app conserva sus fotos y textos; aquí solo se
/// traducen los nombres a ids.
class Catalogo {
  Catalogo._(this.servicios, this.areas, this.extras);

  final Map<String, int> servicios;
  final Map<String, int> areas;
  final Map<String, int> extras;

  static Catalogo? _cache;

  static Future<Catalogo> obtener({bool recargar = false}) async {
    if (_cache != null && !recargar) return _cache!;
    final d = await ApiClient.get('/api/cliente/catalogo') as Map<String, dynamic>;
    Map<String, int> mapa(String clave) => {for (final x in d[clave] as List) (x as Map<String, dynamic>)['nombre'] as String: x['id'] as int};
    return _cache = Catalogo._(mapa('servicios'), mapa('areas'), mapa('extras'));
  }

  int servicioId(String nombre) {
    final id = servicios[nombre];
    if (id == null) throw ApiException('El servicio «$nombre» no está disponible por ahora.');
    return id;
  }
}

/// Cuerpo común de la cotización y la solicitud.
Future<Map<String, dynamic>> _pedido(ServiceRequestData req) async {
  final cat = await Catalogo.obtener();
  final fecha = req.scheduledAt;
  if (fecha == null) throw ApiException('Falta elegir la fecha y la hora del servicio.');
  final p = req.property;
  return {
    'servicioId': cat.servicioId(req.serviceTitle),
    'fechaProgramada': fecha.toUtc().toIso8601String(),
    'areaIds': [for (final a in req.areas) if (cat.areas[a] != null) cat.areas[a]!],
    'extraIds': [for (final e in req.extras) if (cat.extras[e] != null) cat.extras[e]!],
    if (req.notes.trim().isNotEmpty) 'notas': req.notes.trim(),
    if (p.inmuebleId != null)
      'inmuebleId': p.inmuebleId
    else
      'inmueble': {
        'tipo': p.apiType,
        'direccion': p.address,
        'habitaciones': p.rooms,
        'banos': p.fullBaths,
        'mediosBanos': p.halfBaths,
        'pisos': p.floors,
        if (p.guardarComo != null) 'guardarComo': p.guardarComo,
      },
  };
}

class Cotizacion {
  Cotizacion.fromJson(Map<String, dynamic> j)
      : total = (j['precio'] as Map<String, dynamic>)['total'] as num,
        base = (j['precio'] as Map<String, dynamic>)['base'] as num,
        extras = (j['precio'] as Map<String, dynamic>)['extras'] as num,
        duracionMin = j['duracionMin'] as int,
        finEstimado = DateTime.parse(j['finEstimado'] as String);

  final num total;
  final num base;
  final num extras;
  final int duracionMin;
  final DateTime finEstimado;
}

/// Foto de «terminado» que subió el colaborador.
class FotoTerminado {
  FotoTerminado.fromJson(Map<String, dynamic> j) : id = j['id'] as int;
  final int id;
}

/// Detalle de una solicitud propia, con lo que el servidor permite hacer.
class DetalleSolicitud {
  DetalleSolicitud.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        estado = j['estado'] as String,
        modo = j['modo'] as String,
        servicio = j['servicio'] as String,
        fechaProgramada = DateTime.parse(j['fechaProgramada'] as String),
        finEstimado = j['finEstimado'] == null ? null : DateTime.parse(j['finEstimado'] as String),
        direccion = j['direccion'] as String,
        inmuebleNombre = (j['inmueble'] as Map<String, dynamic>)['nombre'] as String?,
        precio = j['precio'] as num,
        trabajadorNombre = (j['trabajador'] as Map<String, dynamic>?)?['nombre'] as String?,
        invitadoNombre = [
          for (final i in j['invitaciones'] as List)
            if ((i as Map<String, dynamic>)['estado'] == 'PENDIENTE') (i['trabajador'] as Map<String, dynamic>)['nombre'] as String
        ].firstOrNull,
        rechazadaPor = (j['invitacionRechazada'] as Map<String, dynamic>?)?['trabajador'] as String?,
        reporteEnRevision = j['reporteEnRevision'] as bool,
        trabajadorTerminoEn = ((j['marcas'] as Map<String, dynamic>)['trabajadorTerminoEn']) == null ? null : DateTime.parse((j['marcas'] as Map<String, dynamic>)['trabajadorTerminoEn'] as String),
        realizadoVia = (j['marcas'] as Map<String, dynamic>)['realizadoVia'] as String?,
        fotos = [for (final f in j['fotosTerminado'] as List) FotoTerminado.fromJson(f as Map<String, dynamic>)],
        puedeCancelar = (j['acciones'] as Map<String, dynamic>)['puedeCancelar'] as bool,
        motivoNoCancelar = (j['acciones'] as Map<String, dynamic>)['motivoNoCancelar'] as String?,
        puedeEnviarABolsa = (j['acciones'] as Map<String, dynamic>)['puedeEnviarABolsa'] as bool,
        puedeInvitarOtro = (j['acciones'] as Map<String, dynamic>)['puedeInvitarOtro'] as bool,
        puedeConfirmar = (j['acciones'] as Map<String, dynamic>)['puedeConfirmar'] as bool;

  final int id;
  final String estado;
  final String modo; // INVITACION | BOLSA
  final String servicio;
  final DateTime fechaProgramada;
  final DateTime? finEstimado;
  final String direccion;
  final String? inmuebleNombre;
  final num precio;
  final String? trabajadorNombre;
  final String? invitadoNombre;
  final String? rechazadaPor;
  final bool reporteEnRevision;
  final DateTime? trabajadorTerminoEn;
  final String? realizadoVia;
  final List<FotoTerminado> fotos;
  final bool puedeCancelar;
  final String? motivoNoCancelar;
  final bool puedeEnviarABolsa;
  final bool puedeInvitarOtro;
  final bool puedeConfirmar;

  bool get activa => const ['PENDIENTE', 'CONFIRMADO', 'EN_PROCESO'].contains(estado);
}

class CicloApi {
  CicloApi._();

  static Future<Cotizacion> cotizar(ServiceRequestData req) async {
    final d = await ApiClient.post('/api/cliente/cotizaciones', await _pedido(req)) as Map<String, dynamic>;
    return Cotizacion.fromJson(d['cotizacion'] as Map<String, dynamic>);
  }

  /// Crea la solicitud. Con colaborador elegido → invitación; sin él → bolsa.
  static Future<int> crear(ServiceRequestData req) async {
    final cuerpo = await _pedido(req);
    if (req.collaboratorId != null) cuerpo['trabajadorId'] = req.collaboratorId;
    final d = await ApiClient.post('/api/cliente/solicitudes', cuerpo) as Map<String, dynamic>;
    return (d['solicitud'] as Map<String, dynamic>)['id'] as int;
  }

  static Future<DetalleSolicitud> detalle(int id) async {
    final d = await ApiClient.get('/api/cliente/solicitudes/$id') as Map<String, dynamic>;
    return DetalleSolicitud.fromJson(d['solicitud'] as Map<String, dynamic>);
  }

  static Future<void> enviarABolsa(int id) => ApiClient.post('/api/cliente/solicitudes/$id/bolsa');
  static Future<void> invitar(int id, int trabajadorId) => ApiClient.post('/api/cliente/solicitudes/$id/invitaciones', {'trabajadorId': trabajadorId});
  static Future<void> cancelar(int id, {String? motivo}) => ApiClient.post('/api/cliente/solicitudes/$id/cancelar', {if (motivo != null && motivo.isNotEmpty) 'motivo': motivo});
  static Future<void> confirmar(int id) => ApiClient.post('/api/cliente/solicitudes/$id/confirmar');

  /// URL absoluta y temporal de una foto de «terminado».
  static Future<String> urlFoto(int id, int fotoId) async {
    final d = await ApiClient.get('/api/cliente/solicitudes/$id/evidencias/$fotoId') as Map<String, dynamic>;
    return '${ApiClient.baseUrl}${d['url']}';
  }
}

// ── Mis inmuebles ──

class Inmueble {
  Inmueble.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        nombre = j['nombre'] as String,
        tipo = j['tipo'] as String,
        direccion = j['direccion'] as String,
        habitaciones = j['habitaciones'] as int,
        banos = j['banos'] as int,
        mediosBanos = j['mediosBanos'] as int,
        pisos = j['pisos'] as int;

  final int id;
  final String nombre;
  final String tipo; // CASA | OFICINA | DEPARTAMENTO
  final String direccion;
  final int habitaciones;
  final int banos;
  final int mediosBanos;
  final int pisos;

  /// Nombre del tipo como lo muestra la app ('Casa', 'Oficina', 'Departamento').
  String get tipoApp => switch (tipo) { 'OFICINA' => 'Oficina', 'DEPARTAMENTO' => 'Departamento', _ => 'Casa' };

  String get resumen => '$tipoApp · $habitaciones hab. · $banos baño${banos == 1 ? '' : 's'}${mediosBanos > 0 ? ' · $mediosBanos medio${mediosBanos == 1 ? '' : 's'}' : ''} · $pisos nivel${pisos == 1 ? '' : 'es'}';
}

class InmueblesApi {
  InmueblesApi._();

  static Future<List<Inmueble>> listar() async {
    final d = await ApiClient.get('/api/cliente/inmuebles') as Map<String, dynamic>;
    return [for (final i in d['inmuebles'] as List) Inmueble.fromJson(i as Map<String, dynamic>)];
  }

  static Map<String, dynamic> _cuerpo(String nombre, PropertyData p) => {
        'nombre': nombre,
        'tipo': p.apiType,
        'direccion': p.address,
        'habitaciones': p.rooms,
        'banos': p.fullBaths,
        'mediosBanos': p.halfBaths,
        'pisos': p.floors,
      };

  static Future<Inmueble> crear(String nombre, PropertyData p) async {
    final d = await ApiClient.post('/api/cliente/inmuebles', _cuerpo(nombre, p)) as Map<String, dynamic>;
    return Inmueble.fromJson(d['inmueble'] as Map<String, dynamic>);
  }

  static Future<Inmueble> editar(int id, String nombre, PropertyData p) async {
    final d = await ApiClient.patch('/api/cliente/inmuebles/$id', _cuerpo(nombre, p)) as Map<String, dynamic>;
    return Inmueble.fromJson(d['inmueble'] as Map<String, dynamic>);
  }

  /// Eliminar = archivar: las solicitudes anteriores conservan su copia.
  static Future<void> eliminar(int id) => ApiClient.delete('/api/cliente/inmuebles/$id');
}

// ── Avisos ──

class Notificacion {
  Notificacion.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        solicitudId = j['solicitudId'] as int?,
        tipo = j['tipo'] as String,
        titulo = j['titulo'] as String,
        mensaje = j['mensaje'] as String,
        leida = j['leida'] as bool,
        fecha = DateTime.parse(j['fecha'] as String);

  final int id;
  final int? solicitudId;
  final String tipo;
  final String titulo;
  final String mensaje;
  final bool leida;
  final DateTime fecha;
}

class NotificacionesApi {
  NotificacionesApi._();

  static Future<(int, List<Notificacion>)> listar() async {
    final d = await ApiClient.get('/api/cliente/notificaciones') as Map<String, dynamic>;
    return (d['noLeidas'] as int, [for (final n in d['notificaciones'] as List) Notificacion.fromJson(n as Map<String, dynamic>)]);
  }

  static Future<void> marcarLeida(int id) => ApiClient.post('/api/cliente/notificaciones/$id/leida');
  static Future<void> marcarTodas() => ApiClient.post('/api/cliente/notificaciones/leidas');
}

/// Mensaje claro para los errores del ciclo (el servidor ya manda el texto; aquí solo se aclaran algunos).
String mensajeDelCiclo(Object e) {
  if (e is ApiException) {
    return switch (e.codigo) {
      'IDENTIDAD_NO_VERIFICADA' => 'Para enviar una solicitud necesitas tener tu identidad (INE) aprobada.',
      'CANCELACION_NO_DISPONIBLE' => e.message,
      _ => e.message,
    };
  }
  return 'No se pudo completar la operación. Intenta de nuevo.';
}
