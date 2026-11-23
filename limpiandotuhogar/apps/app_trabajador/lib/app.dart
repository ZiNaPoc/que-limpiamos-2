import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'services/app_scope.dart';
import 'services/app_state.dart';
import 'theme/app_theme.dart';

class QueLimpiamosApp extends StatelessWidget {
  const QueLimpiamosApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: '¿Qué limpiamos? Trabajadores',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        // Limita el escalado de texto extremo para evitar desbordamientos
        // sin desactivar la accesibilidad.
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(maxScaleFactor: 1.25),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
