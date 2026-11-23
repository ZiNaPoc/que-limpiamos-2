import 'package:flutter/material.dart';

/// Sistema de color de ¿Qué limpiamos?
///
/// Los 15 tonos de la paleta oficial se declaran tal cual. Para cumplir el
/// contraste mínimo de lectura (WCAG AA) se usan además tonos profundos del
/// mismo matiz que [primary] (#7296A4) para textos y botones principales, y
/// dos tonos funcionales suaves para advertencia y error.
class AppColors {
  AppColors._();

  // ── Paleta oficial ───────────────────────────────────────────────
  static const Color mist = Color(0xFFE5EBEE);
  static const Color fog = Color(0xFFCDDBE4);
  static const Color periwinkle = Color(0xFFB9C7E0);
  static const Color sky = Color(0xFFABC4D6);
  static const Color snow = Color(0xFFF4FAFC);

  static const Color primary = Color(0xFF7296A4);
  static const Color steel = Color(0xFF9EBECB);
  static const Color frost = Color(0xFFCDDEE5);
  static const Color ice = Color(0xFFE6F0F2);
  static const Color cloud = Color(0xFFEFEFEF);

  static const Color mint = Color(0xFFC5E2C2);
  static const Color sage = Color(0xFFBCDECC);
  static const Color seafoam = Color(0xFFB1D9CF);
  static const Color aqua = Color(0xFFABD7E1);
  static const Color lagoon = Color(0xFF93CAD3);

  // ── Tonos profundos del color principal (texto y acciones) ───────
  /// Botones principales y elementos activos (contraste 5.3:1 con blanco).
  static const Color primaryStrong = Color(0xFF50707C);

  /// Títulos y texto principal.
  static const Color ink = Color(0xFF28383E);

  /// Texto secundario.
  static const Color inkSoft = Color(0xFF46626C);

  /// Texto de apoyo / placeholders.
  static const Color inkMuted = Color(0xFF6A8792);

  // ── Roles ────────────────────────────────────────────────────────
  static const Color background = snow;
  static const Color surface = Colors.white;
  static const Color surfaceAlt = ice;
  static const Color border = fog;
  static const Color divider = mist;
  static const Color disabled = cloud;
  static const Color headerWave = sky;
  static const Color headerWaveBack = steel;

  // ── Estados (fondo suave + texto oscuro del mismo matiz) ─────────
  static const Color successBg = mint;
  static const Color successFg = Color(0xFF2D5629);
  static const Color infoBg = aqua;
  static const Color infoFg = Color(0xFF25535B);
  static const Color negotiationBg = periwinkle;
  static const Color negotiationFg = Color(0xFF2F446A);
  static const Color progressBg = seafoam;
  static const Color progressFg = Color(0xFF2A564B);
  static const Color neutralBg = mist;
  static const Color neutralFg = inkSoft;

  static const Color warningBg = Color(0xFFF4E8CF);
  static const Color warningFg = Color(0xFF6E5419);
  static const Color errorBg = Color(0xFFF3DCDD);
  static const Color errorFg = Color(0xFF8A3A3F);

  /// Devuelve [color] con la opacidad indicada (0–1) sin APIs deprecadas.
  static Color fade(Color color, double opacity) =>
      color.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());
}
