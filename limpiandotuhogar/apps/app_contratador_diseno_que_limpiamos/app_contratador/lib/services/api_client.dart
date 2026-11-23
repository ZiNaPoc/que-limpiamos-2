import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error legible para mostrar en pantalla (NoticeBox, toast, etc.).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

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

  static Future<dynamic> get(String path) => _request('GET', path);

  static Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: body);

  static Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body: body);

  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {'Content-Type': 'application/json'};

    try {
      final response = await (switch (method) {
        'POST' => http.post(uri, headers: headers, body: jsonEncode(body)),
        'PATCH' => http.patch(uri, headers: headers, body: jsonEncode(body)),
        _ => http.get(uri, headers: headers),
      })
          .timeout(_timeout);

      final decoded =
          response.body.isEmpty ? null : jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      // El backend responde { error: "..." } (o { message: "..." }).
      final message = decoded is Map
          ? (decoded['error'] ?? decoded['mensaje'] ?? decoded['message'])?.toString()
          : null;
      throw ApiException(
        message ?? 'Error del servidor (${response.statusCode}).',
        statusCode: response.statusCode,
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
// Auth
// ════════════════════════════════════════════════════════════════════

class ApiUser {
  const ApiUser({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    this.telefono,
  });

  final int id;
  final String nombre;
  final String correo;
  final String rol; // 'CLIENTE' | 'TRABAJADOR'
  final String? telefono;

  factory ApiUser.fromJson(Map<String, dynamic> json) => ApiUser(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        correo: json['correo'] as String,
        rol: json['rol'] as String,
        telefono: json['telefono'] as String?,
      );
}

class AuthApi {
  AuthApi._();

  static Future<ApiUser> login({
    required String correo,
    required String password,
  }) async {
    final data = await ApiClient.post('/login', {
      'correo': correo.trim(),
      'password': password,
    });
    return ApiUser.fromJson(data['estrella'] as Map<String, dynamic>);
  }

  /// [rol]: 'CLIENTE' (default del backend) o 'TRABAJADOR'.
  static Future<ApiUser> signup({
    required String nombre,
    required String correo,
    required String telefono,
    required String password,
    String? rol,
  }) async {
    final data = await ApiClient.post('/signup', {
      'nombre': nombre.trim(),
      'correo': correo.trim(),
      'telefono': telefono.trim(),
      'password': password,
      if (rol != null) 'rol': rol,
    });
    return ApiUser.fromJson(data['estrella'] as Map<String, dynamic>);
  }
}