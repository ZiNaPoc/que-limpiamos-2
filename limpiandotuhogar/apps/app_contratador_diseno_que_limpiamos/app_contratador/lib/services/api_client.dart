import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error legible para mostrar en pantalla (NoticeBox, toast, etc.).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.codigo});

  final String message;
  final int? statusCode;

  /// Código del backend (p. ej. CREDENCIALES_INVALIDAS, DEMASIADOS_INTENTOS).
  final String? codigo;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  /// Android emulador: 10.0.2.2 · iOS simulador: localhost · celular real: IP de tu PC.
  /// Se puede cambiar sin tocar código:
  ///   flutter run --dart-define=API_URL=http://192.168.1.50:3000
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const Duration _timeout = Duration(seconds: 12);

  /// Token de la sesión (lo pone Session). Se envía como `Authorization: Bearer`.
  static String? token;

  /// Se llama cuando una petición CON token responde 401: la sesión venció o
  /// la contraseña cambió. Session la limpia y la app vuelve a la bienvenida.
  static void Function()? onSesionVencida;

  static Future<dynamic> get(String path) => _request('GET', path);

  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _request('POST', path, body: body);

  static Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body: body);

  static Future<dynamic> delete(String path) => _request('DELETE', path);

  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final conToken = token != null;
    final headers = {
      'Content-Type': 'application/json',
      if (conToken) 'Authorization': 'Bearer $token',
    };

    try {
      final response = await (switch (method) {
        'POST' => http.post(uri, headers: headers, body: jsonEncode(body ?? {})),
        'PATCH' => http.patch(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => http.delete(uri, headers: headers),
        _ => http.get(uri, headers: headers),
      })
          .timeout(_timeout);

      final decoded =
          response.body.isEmpty ? null : jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      // El backend responde { mensaje, codigo }.
      final message = decoded is Map
          ? (decoded['mensaje'] ?? decoded['error'] ?? decoded['message'])?.toString()
          : null;
      final codigo = decoded is Map ? decoded['codigo']?.toString() : null;

      if (response.statusCode == 401 && conToken) {
        onSesionVencida?.call();
      }
      throw ApiException(
        message ?? 'Error del servidor (${response.statusCode}).',
        statusCode: response.statusCode,
        codigo: codigo,
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

// ════════════════════════════════════════════════════════════════════
// Auth — /api/cliente/auth (contrato en docs/backend/06_CONTRATOS_API.md)
// ════════════════════════════════════════════════════════════════════

class ApiUser {
  const ApiUser({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    this.telefono,
    this.estadoVerificacion,
  });

  final int id;
  final String nombre;
  final String correo;
  final String rol; // 'CLIENTE'
  final String? telefono;

  /// PENDIENTE, VERIFICADO o RECHAZADO (estado de la INE).
  final String? estadoVerificacion;

  factory ApiUser.fromJson(Map<String, dynamic> json) => ApiUser(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        correo: json['correo'] as String,
        rol: json['rol'] as String,
        telefono: json['telefono'] as String?,
        estadoVerificacion: json['estado_verificacion'] as String?,
      );
}

/// Resultado de iniciar sesión o registrarse: el token y la cuenta.
typedef SesionIniciada = ({String token, ApiUser usuario});

class AuthApi {
  AuthApi._();

  static const _base = '/api/cliente/auth';

  static SesionIniciada _sesion(dynamic data) => (
        token: data['token'] as String,
        usuario: ApiUser.fromJson(data['cliente'] as Map<String, dynamic>),
      );

  /// [identificador]: correo o teléfono de 10 dígitos.
  static Future<SesionIniciada> login({
    required String identificador,
    required String password,
  }) async {
    final limpio = identificador.trim();
    final soloDigitos = limpio.replaceAll(RegExp(r'[\s\-()]'), '');
    final esTelefono = RegExp(r'^(\+52)?\d{10}$').hasMatch(soloDigitos);
    final data = await ApiClient.post('$_base/login', {
      if (esTelefono) 'telefono': soloDigitos else 'correo': limpio,
      'password': password,
    });
    return _sesion(data);
  }

  static Future<SesionIniciada> registro({
    required String nombre,
    required String correo,
    required String telefono,
    required String password,
  }) async {
    final data = await ApiClient.post('$_base/registro', {
      'nombre': nombre.trim(),
      'correo': correo.trim(),
      'telefono': telefono.trim(),
      'password': password,
    });
    return _sesion(data);
  }

  /// Cuenta de la sesión actual (para restaurarla al abrir la app).
  static Future<ApiUser> me() async {
    final data = await ApiClient.get('$_base/me');
    return ApiUser.fromJson(data['cliente'] as Map<String, dynamic>);
  }

  static Future<void> logout() async {
    await ApiClient.post('$_base/logout');
  }
}
