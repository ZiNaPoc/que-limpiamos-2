import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia local sencilla: guarda una instantánea JSON del estado.
class StorageService {
  static const _key = 'que_limpiamos_worker_state_v1';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Map<String, dynamic>? read() {
    final raw = _prefs?.getString(_key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Si la información guardada está dañada se ignora y se usan los datos simulados.
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    await _prefs?.setString(_key, jsonEncode(data));
  }

  Future<void> clear() async {
    await _prefs?.remove(_key);
  }
}
