import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Navegación con transiciones coherentes en toda la app.
class AppRoutes {
  AppRoutes._();

  /// Transición de entrada: desvanecido + desplazamiento lateral corto.
  static Route<T> fadeSlide<T>(Widget page,
      {bool vertical = false, String? name}) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: AppDurations.medium,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final begin = vertical ? const Offset(0, 0.08) : const Offset(0.08, 0);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Transición suave sin desplazamiento (para cambios de módulo completos).
  static Route<T> fade<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 520),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );
  }

  static Future<T?> push<T>(BuildContext context, Widget page,
          {bool vertical = false, String? name}) =>
      Navigator.of(context)
          .push<T>(fadeSlide<T>(page, vertical: vertical, name: name));

  /// Reemplaza toda la pila (p. ej. al iniciar o cerrar sesión).
  static Future<T?> resetTo<T>(BuildContext context, Widget page) =>
      Navigator.of(context)
          .pushAndRemoveUntil<T>(fade<T>(page), (route) => false);
}
