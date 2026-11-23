import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// Pon en `false` cuando termines de depurar para silenciar los logs.
  static const bool _debug = true;

  static Future<dynamic> get(String path) => _request('GET', path);

  static Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body: body);

  static Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _request('PATCH', path, body: body);

  static void _log(String msg) {
    if (_debug) debugPrint(msg);
  }

  static Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {'Content-Type': 'application/json'};

    _log('[api] → $method $uri ${body == null ? '' : _redact(body)}');

    try {
      final response = await (switch (method) {
        'POST' => http.post(uri, headers: headers, body: jsonEncode(body)),
        'PATCH' => http.patch(uri, headers: headers, body: jsonEncode(body)),
        _ => http.get(uri, headers: headers),
      })
          .timeout(_timeout);

      _log(
          '[api] ← ${response.statusCode} $method $path ${_short(response.body)}');

      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      // El backend responde { error: "..." } (o { message: "..." }).
      final message = decoded is Map
          ? (decoded['error'] ?? decoded['mensaje'] ?? decoded['message'])
              ?.toString()
          : null;
      throw ApiException(
        message ?? 'Error del servidor (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } on TimeoutException {
      _log('[api] TIMEOUT $method $uri');
      throw ApiException('El servidor tardó demasiado en responder.');
    } on http.ClientException catch (e) {
      _log('[api] ClientException $method $uri: $e');
      throw ApiException('No se pudo conectar con el servidor.');
    } on FormatException catch (e) {
      // Pasa, por ejemplo, cuando el backend devuelve HTML ("Cannot POST /x")
      // en lugar de JSON.
      _log('[api] FormatException $method $uri: $e');
      throw ApiException('Respuesta inválida del servidor.');
    }
  }

  /// Oculta la contraseña en los logs.
  static Map<String, dynamic> _redact(Map<String, dynamic> body) => {
        for (final e in body.entries)
          e.key: e.key.toLowerCase().contains('password') ? '***' : e.value,
      };

  /// Recorta respuestas largas para no llenar la consola.
  static String _short(String s) =>
      s.length > 400 ? '${s.substring(0, 400)}…' : s;
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
