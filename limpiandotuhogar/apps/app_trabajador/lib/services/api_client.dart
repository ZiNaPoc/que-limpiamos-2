import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// Registro de peticiones solo en modo depuración (nunca en la app publicada).
  static const bool _debug = kDebugMode;

  /// Token de la sesión (lo pone Session). Se envía como `Authorization: Bearer`.
  static String? token;

  /// Se llama cuando una petición CON token responde 401: la sesión venció o
  /// la contraseña cambió. La app borra la sesión y vuelve a la bienvenida.
  static void Function()? onSesionVencida;

  static Future<dynamic> get(String path) => _request('GET', path);

  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
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
    final conToken = token != null;
    final headers = {
      'Content-Type': 'application/json',
      if (conToken) 'Authorization': 'Bearer $token',
    };

    _log('[api] → $method $uri ${body == null ? '' : _redact(body)}');

    try {
      final response = await (switch (method) {
        'POST' => http.post(uri, headers: headers, body: jsonEncode(body ?? {})),
        'PATCH' => http.patch(uri, headers: headers, body: jsonEncode(body)),
        _ => http.get(uri, headers: headers),
      })
          .timeout(_timeout);

      _log('[api] ← ${response.statusCode} $method $path ${_short(_sinToken(response.body))}');

      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      // El backend responde { mensaje, codigo }.
      final message = decoded is Map
          ? (decoded['mensaje'] ?? decoded['error'] ?? decoded['message'])
              ?.toString()
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
      _log('[api] TIMEOUT $method $uri');
      throw ApiException('El servidor tardó demasiado en responder.');
    } on http.ClientException catch (e) {
      _log('[api] ClientException $method $uri: $e');
      throw ApiException('No se pudo conectar con el servidor.');
    } on FormatException catch (e) {
      // Pasa, por ejemplo, cuando el backend devuelve HTML en lugar de JSON.
      _log('[api] FormatException $method $uri: $e');
      throw ApiException('Respuesta inválida del servidor.');
    }
  }

  /// Oculta contraseñas en los logs.
  static Map<String, dynamic> _redact(Map<String, dynamic> body) => {
        for (final e in body.entries)
          e.key: e.key.toLowerCase().contains('password') ? '***' : e.value,
      };

  /// Oculta el token en los logs de las respuestas.
  static String _sinToken(String s) =>
      s.replaceAll(RegExp(r'"token"\s*:\s*"[^"]*"'), '"token":"***"');

  /// Recorta respuestas largas para no llenar la consola.
  static String _short(String s) =>
      s.length > 400 ? '${s.substring(0, 400)}…' : s;
}

// ════════════════════════════════════════════════════════════════════
// Auth — /api/trabajador/auth (contrato en docs/backend/06_CONTRATOS_API.md)
// ════════════════════════════════════════════════════════════════════

class ApiUser {
  const ApiUser({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.rol,
    this.telefono,
    this.direccion,
  });

  final int id;
  final String nombre;
  final String correo;
  final String rol; // 'TRABAJADOR'
  final String? telefono;
  final String? direccion;

  factory ApiUser.fromJson(Map<String, dynamic> json) => ApiUser(
        id: json['id'] as int,
        nombre: json['nombre'] as String,
        correo: json['correo'] as String,
        rol: json['rol'] as String,
        telefono: json['telefono'] as String?,
        direccion: json['direccion'] as String?,
      );
}

/// Resultado de iniciar sesión o registrarse: el token y la cuenta.
typedef SesionIniciada = ({String token, ApiUser usuario});

class AuthApi {
  AuthApi._();

  static const _base = '/api/trabajador/auth';

  static SesionIniciada _sesion(dynamic data) => (
        token: data['token'] as String,
        usuario: ApiUser.fromJson(data['trabajador'] as Map<String, dynamic>),
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
    required String direccion,
    required String password,
  }) async {
    final data = await ApiClient.post('$_base/registro', {
      'nombre': nombre.trim(),
      'correo': correo.trim(),
      'telefono': telefono.trim(),
      'direccion': direccion.trim(),
      'password': password,
    });
    return _sesion(data);
  }

  /// Cuenta de la sesión actual (para restaurarla al abrir la app).
  static Future<ApiUser> me() async {
    final data = await ApiClient.get('$_base/me');
    return ApiUser.fromJson(data['trabajador'] as Map<String, dynamic>);
  }

  static Future<void> logout() async {
    await ApiClient.post('$_base/logout');
  }
}
