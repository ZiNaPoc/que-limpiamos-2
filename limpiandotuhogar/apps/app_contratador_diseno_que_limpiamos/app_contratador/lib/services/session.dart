import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'token_store.dart';

/// Sesión del cliente: la cuenta y su token. El token se guarda en el
/// almacenamiento seguro para no pedir la contraseña cada vez que se abre la app.
class Session extends ChangeNotifier {
  Session._();

  static final Session instance = Session._();

  ApiUser? _user;

  ApiUser? get user => _user;
  bool get isLoggedIn => _user != null;

  /// Después de iniciar sesión o registrarse.
  Future<void> start(SesionIniciada sesion) async {
    _user = sesion.usuario;
    ApiClient.token = sesion.token;
    await TokenStore.guardar(sesion.token);
    notifyListeners();
  }

  /// Al abrir la app: si hay token guardado, pregunta al backend si sigue
  /// valiendo. Devuelve true si la sesión quedó restaurada.
  Future<bool> restaurar() async {
    final token = await TokenStore.leer();
    if (token == null) return false;
    ApiClient.token = token;
    try {
      _user = await AuthApi.me();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      // 401 (vencida o contraseña cambiada) o 403 (cuenta suspendida): se borra.
      if (e.statusCode == 401 || e.statusCode == 403) await clear();
      // Sin conexión: se conserva el token para intentarlo la próxima vez.
      ApiClient.token = e.statusCode == null ? token : null;
      return false;
    } catch (_) {
      // Respuesta inesperada: se entra sin sesión (el usuario puede volver a iniciarla).
      ApiClient.token = null;
      return false;
    }
  }

  /// Cierra la sesión. Con [avisarServidor] llama a /logout antes de borrar el token.
  Future<void> clear({bool avisarServidor = false}) async {
    if (avisarServidor && ApiClient.token != null) {
      try {
        await AuthApi.logout();
      } catch (_) {
        // Sin conexión: el token se borra igual en el teléfono.
      }
    }
    _user = null;
    ApiClient.token = null;
    await TokenStore.borrar();
    notifyListeners();
  }
}
