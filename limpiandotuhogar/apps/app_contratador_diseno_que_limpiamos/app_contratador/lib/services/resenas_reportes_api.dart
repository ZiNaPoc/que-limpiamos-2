import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_client.dart';

// ════════════════════════════════════════════════════════════════════
// Reseñas y reportes — audiencia CLIENTE (Fase 3a, docs/backend/20).
// Cliente HTTP listo; las pantallas se conectan en la Fase 3b, cuando exista
// el historial nuevo de solicitudes. La identidad sale del token: nunca se
// envía el id del usuario.
// ════════════════════════════════════════════════════════════════════

/// Reseña PÚBLICA: solo calificación, comentario y mes/año (sin autor).
class ResenaPublica {
  ResenaPublica.fromJson(Map<String, dynamic> j)
      : puntuacion = j['puntuacion'] as int,
        comentario = j['comentario'] as String?,
        mes = j['mes'] as int,
        anio = j['anio'] as int;

  final int puntuacion;
  final String? comentario;
  final int mes;
  final int anio;
}

/// Promedio de reseñas válidas. `promedio` es null si no hay reseñas.
class Reputacion {
  Reputacion.fromJson(Map<String, dynamic> j)
      : promedio = (j['promedio'] as num?)?.toDouble(),
        cantidad = j['cantidad'] as int;

  final double? promedio;
  final int cantidad;
}

/// Reseña escrita por el propio usuario (su historial).
class ResenaPropia {
  ResenaPropia.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        solicitudId = j['solicitudId'] as int,
        puntuacion = j['puntuacion'] as int,
        comentario = j['comentario'] as String?,
        fecha = DateTime.parse(j['fecha'] as String),
        editadaPorModeracion = j['editadaPorModeracion'] as bool,
        eliminadaPorModeracion = j['eliminadaPorModeracion'] as bool;

  final int id;
  final int solicitudId;
  final int puntuacion;
  final String? comentario;
  final DateTime fecha;
  final bool editadaPorModeracion;
  final bool eliminadaPorModeracion;
}

/// Reporte creado por el propio usuario (solo él y la moderación lo ven).
class ReportePropio {
  ReportePropio.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        solicitudId = j['solicitudId'] as int,
        tipo = j['tipo'] as String,
        descripcion = j['descripcion'] as String?,
        estado = j['estado'] as String,
        fecha = DateTime.parse(j['fecha'] as String),
        eliminadoPorModeracion = j['eliminadoPorModeracion'] as bool,
        evidenciaIds = [
          for (final e in (j['evidencias'] as List)) (e as Map<String, dynamic>)['id'] as int,
        ];

  final int id;
  final int solicitudId;
  final String tipo;
  final String? descripcion;
  final String estado;
  final DateTime fecha;
  final bool eliminadoPorModeracion;
  final List<int> evidenciaIds;
}

/// Foto para un reporte: JPEG, PNG o WebP; el nombre debe tener la extensión
/// que corresponde a su contenido (el backend comprueba el tipo real).
typedef FotoDeReporte = ({String nombre, List<int> bytes});

class ResenasApi {
  ResenasApi._();

  static const int maxComentario = 500;

  /// Califica al trabajador de un servicio REALIZADO (hasta 168 h después).
  static Future<ResenaPropia> calificarTrabajador(int solicitudId, {required int puntuacion, String? comentario}) async {
    final data = await ApiClient.post('/api/cliente/solicitudes/$solicitudId/resena', {
      'puntuacion': puntuacion,
      if (comentario != null && comentario.trim().isNotEmpty) 'comentario': comentario.trim(),
    });
    return ResenaPropia.fromJson((data as Map<String, dynamic>)['resena'] as Map<String, dynamic>);
  }

  static Future<List<ResenaPropia>> misResenas() async {
    final data = await ApiClient.get('/api/cliente/resenas') as Map<String, dynamic>;
    return [for (final r in data['resenas'] as List) ResenaPropia.fromJson(r as Map<String, dynamic>)];
  }

  /// Reseñas (anónimas) y promedio de un trabajador: perfil del trabajador.
  static Future<({Reputacion reputacion, List<ResenaPublica> resenas})> resenasDeTrabajador(int trabajadorId) async {
    final data = await ApiClient.get('/api/cliente/trabajadores/$trabajadorId/resenas') as Map<String, dynamic>;
    return (
      reputacion: Reputacion.fromJson(data['reputacion'] as Map<String, dynamic>),
      resenas: [for (final r in data['resenas'] as List) ResenaPublica.fromJson(r as Map<String, dynamic>)],
    );
  }

  /// Estrellas de varios trabajadores a la vez (selección manual).
  static Future<Map<int, Reputacion>> reputacionesDeTrabajadores(List<int> ids) async {
    if (ids.isEmpty) return {};
    final data = await ApiClient.get('/api/cliente/trabajadores/reputacion?ids=${ids.join(',')}') as Map<String, dynamic>;
    final mapa = data['reputaciones'] as Map<String, dynamic>;
    return {for (final e in mapa.entries) int.parse(e.key): Reputacion.fromJson(e.value as Map<String, dynamic>)};
  }
}

class ReportesApi {
  ReportesApi._();

  static const int maxFotos = 5;
  static const int maxBytesPorFoto = 8000000; // 8 MB (1 MB = 1 000 000 bytes)
  static const int maxBytesTotales = 16000000; // 16 MB por reporte

  /// Reporta al trabajador de un servicio (desde la hora programada). Descripción y fotos opcionales.
  static Future<ReportePropio> reportar(int solicitudId, {String? tipo, String? descripcion, List<FotoDeReporte> fotos = const []}) async {
    if (fotos.length > maxFotos) throw ApiException('Un reporte admite como máximo $maxFotos fotografías.');
    final total = fotos.fold<int>(0, (s, f) => s + f.bytes.length);
    if (fotos.any((f) => f.bytes.length > maxBytesPorFoto)) throw ApiException('Cada fotografía puede pesar como máximo 8 MB.');
    if (total > maxBytesTotales) throw ApiException('Las fotografías pueden sumar como máximo 16 MB.');

    final request = http.MultipartRequest('POST', Uri.parse('${ApiClient.baseUrl}/api/cliente/solicitudes/$solicitudId/reportes'));
    if (ApiClient.token != null) request.headers['Authorization'] = 'Bearer ${ApiClient.token}';
    if (tipo != null) request.fields['tipo'] = tipo;
    if (descripcion != null && descripcion.trim().isNotEmpty) request.fields['descripcion'] = descripcion.trim();
    for (final f in fotos) {
      request.files.add(http.MultipartFile.fromBytes('fotos', f.bytes, filename: f.nombre));
    }
    final data = await _enviar(request);
    return ReportePropio.fromJson((data as Map<String, dynamic>)['reporte'] as Map<String, dynamic>);
  }

  static Future<List<ReportePropio>> misReportes() async {
    final data = await ApiClient.get('/api/cliente/reportes') as Map<String, dynamic>;
    return [for (final r in data['reportes'] as List) ReportePropio.fromJson(r as Map<String, dynamic>)];
  }

  static Future<ReportePropio> miReporte(int id) async {
    final data = await ApiClient.get('/api/cliente/reportes/$id') as Map<String, dynamic>;
    return ReportePropio.fromJson(data['reporte'] as Map<String, dynamic>);
  }

  /// URL TEMPORAL (5 min) de una foto de un reporte propio.
  static Future<String> urlDeFoto(int reporteId, int evidenciaId) async {
    final data = await ApiClient.get('/api/cliente/reportes/$reporteId/evidencias/$evidenciaId') as Map<String, dynamic>;
    return '${ApiClient.baseUrl}${data['url']}';
  }

  static Future<dynamic> _enviar(http.MultipartRequest request) async {
    try {
      final respuesta = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 60)));
      final decoded = respuesta.body.isEmpty ? null : jsonDecode(respuesta.body);
      if (respuesta.statusCode >= 200 && respuesta.statusCode < 300) return decoded;
      if (respuesta.statusCode == 401 && ApiClient.token != null) ApiClient.onSesionVencida?.call();
      throw ApiException(
        decoded is Map ? (decoded['mensaje']?.toString() ?? 'Error del servidor (${respuesta.statusCode}).') : 'Error del servidor (${respuesta.statusCode}).',
        statusCode: respuesta.statusCode,
        codigo: decoded is Map ? decoded['codigo']?.toString() : null,
      );
    } on TimeoutException {
      throw ApiException('El servidor tardó demasiado en responder.');
    } on http.ClientException {
      throw ApiException('No se pudo conectar con el servidor.');
    } on FormatException {
      throw ApiException('Respuesta inválida del servidor.');
    }
  }
}
