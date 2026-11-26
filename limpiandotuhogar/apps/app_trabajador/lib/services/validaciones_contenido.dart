import 'api_client.dart';

// ════════════════════════════════════════════════════════════════════
// Validación de reseñas y reportes ANTES de enviar (Fase 3b, docs/backend/20).
// Solo evita envíos que el servidor rechazaría de todos modos: el backend
// es la autoridad y vuelve a validar todo (plazo, permisos, duplicados…).
// ════════════════════════════════════════════════════════════════════

const int kMaxComentario = 500;
const int kMaxFotos = 5;
const int kMaxBytesPorFoto = 8000000; // 8 MB (1 MB = 1 000 000 bytes)
const int kMaxBytesTotales = 16000000; // 16 MB por reporte

/// Error de la reseña o null si se puede enviar.
String? validarResena({required int puntuacion, String? comentario}) {
  if (puntuacion < 1 || puntuacion > 5) return 'Elige de 1 a 5 escobas.';
  final texto = (comentario ?? '').trim();
  if (texto.runes.length > kMaxComentario) {
    return 'El comentario admite como máximo $kMaxComentario caracteres.';
  }
  return null;
}

/// Tipo REAL de una imagen según sus primeros bytes: 'jpg', 'png', 'webp' o null.
String? extensionReal(List<int> b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpg';
  if (b.length >= 8 &&
      b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 &&
      b[4] == 0x0D && b[5] == 0x0A && b[6] == 0x1A && b[7] == 0x0A) {
    return 'png';
  }
  if (b.length >= 12 &&
      String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
    return 'webp';
  }
  return null;
}

/// Error del conjunto de fotos o null si se puede enviar (cantidad, tamaño, total y tipo).
String? validarFotos(List<List<int>> fotos) {
  if (fotos.length > kMaxFotos) return 'Puedes adjuntar como máximo $kMaxFotos fotografías.';
  var total = 0;
  for (final f in fotos) {
    if (f.isEmpty) return 'Una de las fotografías está vacía.';
    if (f.length > kMaxBytesPorFoto) return 'Cada fotografía puede pesar como máximo 8 MB.';
    if (extensionReal(f) == null) return 'Solo se admiten fotografías JPEG, PNG o WebP.';
    total += f.length;
  }
  if (total > kMaxBytesTotales) return 'Las fotografías pueden sumar como máximo 16 MB.';
  return null;
}

/// Tamaño legible en MB decimales.
String megas(int bytes) => '${(bytes / 1000000).toStringAsFixed(1)} MB';

/// Mensaje para el usuario a partir del error del servidor (usa su `codigo`).
String mensajeDeError(Object error) {
  if (error is! ApiException) return 'Ocurrió un error inesperado. Intenta de nuevo.';
  switch (error.codigo) {
    case 'RESENA_DUPLICADA':
      return 'Ya calificaste este servicio.';
    case 'PLAZO_VENCIDO':
      return 'El plazo para calificar (7 días desde que terminó el servicio) ya venció.';
    case 'SERVICIO_NO_FINALIZADO':
      return 'Solo puedes calificar un servicio finalizado.';
    case 'NO_ES_PARTE':
      return 'Este servicio no es tuyo.';
    case 'REPORTE_ANTES_DE_HORA':
      return 'Podrás reportar a partir de la hora programada del servicio.';
    case 'SIN_CONTRAPARTE':
      return 'El servicio todavía no tiene a quién reportar.';
    case 'PLAZO_REPORTE_PAGO_VENCIDO':
      return 'El plazo para reportar el pago ya venció o no aplica a este servicio.';
    case 'REPUTACION_NO_AUTORIZADA':
      return 'Solo puedes ver la reputación del cliente si estás invitado o asignado a su servicio.';
    case 'DEMASIADAS_FOTOS':
    case 'FOTO_DEMASIADO_GRANDE':
    case 'REPORTE_DEMASIADO_GRANDE':
    case 'TIPO_NO_PERMITIDO':
    case 'EXTENSION_NO_COINCIDE':
    case 'TIPO_NO_COINCIDE':
    case 'ARCHIVO_DANADO':
      return error.message;
    case 'SESION_EXPIRADA':
    case 'TOKEN_INVALIDO':
    case 'NO_AUTENTICADO':
      return 'Tu sesión terminó. Vuelve a iniciar sesión.';
  }
  if (error.statusCode == 403) return 'No tienes permiso para ver esta información.';
  if (error.statusCode == 404) return 'No encontramos esa información.';
  return error.message;
}
