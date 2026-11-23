import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Medidas, radios, sombras, duraciones y estilos de texto centralizados.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Margen horizontal de pantalla (se reduce en teléfonos compactos).
  static double screen(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360 ? 16 : 22;
}

class AppRadius {
  AppRadius._();
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 26;
  static const double xl = 34;
  static const double pill = 100;
}

class AppDurations {
  AppDurations._();
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 450);
}

class AppShadows {
  AppShadows._();
  static List<BoxShadow> get soft => [
        BoxShadow(
          color: AppColors.fade(AppColors.primaryStrong, 0.10),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get lifted => [
        BoxShadow(
          color: AppColors.fade(AppColors.primaryStrong, 0.18),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];
}

class AppText {
  AppText._();
  static const String family = 'Poppins';

  static const TextStyle display = TextStyle(
      fontFamily: family,
      fontSize: 30,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: AppColors.ink);
  static const TextStyle title = TextStyle(
      fontFamily: family,
      fontSize: 22,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: AppColors.ink);
  static const TextStyle heading = TextStyle(
      fontFamily: family,
      fontSize: 17,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: AppColors.ink);
  static const TextStyle subtitle = TextStyle(
      fontFamily: family,
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w500,
      color: AppColors.ink);
  static const TextStyle body = TextStyle(
      fontFamily: family,
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w400,
      color: AppColors.inkSoft);
  static const TextStyle bodyStrong = TextStyle(
      fontFamily: family,
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: AppColors.ink);
  static const TextStyle caption = TextStyle(
      fontFamily: family,
      fontSize: 12,
      height: 1.35,
      fontWeight: FontWeight.w400,
      color: AppColors.inkMuted);
  static const TextStyle label = TextStyle(
      fontFamily: family,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w500,
      color: AppColors.ink);
  static const TextStyle button = TextStyle(
      fontFamily: family,
      fontSize: 15,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2);
  static const TextStyle overline = TextStyle(
      fontFamily: family,
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: AppColors.inkSoft);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primaryStrong,
      onPrimary: Colors.white,
      secondary: AppColors.lagoon,
      onSecondary: AppColors.ink,
      tertiary: AppColors.periwinkle,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.errorFg,
      onError: Colors.white,
      outline: AppColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppText.family,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: AppText.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primaryStrong),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.primaryStrong,
        selectionColor: AppColors.frost,
        selectionHandleColor: AppColors.primaryStrong,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: AppText.family,
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
    );
  }
}
