import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Guarda el token de sesión en el almacenamiento SEGURO del sistema
/// (Keychain en iOS, Keystore en Android). Nunca en SharedPreferences.
class TokenStore {
  TokenStore._();

  static const _clave = 'ql_token_cliente';
  static const FlutterSecureStorage _almacen = FlutterSecureStorage();

  static Future<String?> leer() => _almacen.read(key: _clave);

  static Future<void> guardar(String token) =>
      _almacen.write(key: _clave, value: token);

  static Future<void> borrar() => _almacen.delete(key: _clave);
}
