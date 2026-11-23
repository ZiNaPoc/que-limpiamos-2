/// Validaciones de formularios. Devuelven `null` si el valor es válido.
class Validators {
  Validators._();

  static final RegExp _email =
      RegExp(r'^[\w.+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$');

  static String? notEmpty(String? v, {String field = 'Este campo'}) =>
      (v == null || v.trim().isEmpty) ? '$field es obligatorio.' : null;

  static String? name(String? v) {
    final r = notEmpty(v, field: 'El nombre');
    if (r != null) return r;
    if (v!.trim().length < 2) return 'Escribe al menos 2 letras.';
    if (RegExp(r'[0-9]').hasMatch(v)) return 'El nombre no debe tener números.';
    return null;
  }

  static String? email(String? v) {
    final r = notEmpty(v, field: 'El correo');
    if (r != null) return r;
    if (!_email.hasMatch(v!.trim())) return 'Escribe un correo válido.';
    return null;
  }

  static String? phone(String? v) {
    final r = notEmpty(v, field: 'El número telefónico');
    if (r != null) return r;
    final digits = v!.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) return 'Debe tener 10 dígitos.';
    return null;
  }

  static String? password(String? v) {
    final r = notEmpty(v, field: 'La contraseña');
    if (r != null) return r;
    if (v!.length < 8) return 'Mínimo 8 caracteres.';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v)) {
      return 'Combina letras y números.';
    }
    return null;
  }

  static String? confirm(String? v, String original) {
    final r = notEmpty(v, field: 'La confirmación');
    if (r != null) return r;
    if (v != original) return 'Las contraseñas no coinciden.';
    return null;
  }

  /// Monto de una propuesta económica.
  static String? amount(String? v, {double min = 100, double max = 20000}) {
    final r = notEmpty(v, field: 'El monto');
    if (r != null) return r;
    final value = double.tryParse(v!.replaceAll(',', '').trim());
    if (value == null) return 'Escribe solo números.';
    if (value < min) return 'El monto mínimo es \$${min.toStringAsFixed(0)}.';
    if (value > max) return 'El monto máximo es \$${max.toStringAsFixed(0)}.';
    return null;
  }
}
