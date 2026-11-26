import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:app_contratador/navigation/app_routes.dart';
import 'package:app_contratador/navigation/navigator_key.dart';
import 'package:app_contratador/screens/splash_screen.dart';
import 'package:app_contratador/screens/welcome_screen.dart';
import 'package:app_contratador/services/api_client.dart';
import 'package:app_contratador/services/session.dart';
import 'package:app_contratador/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // La app se diseñó para orientación vertical.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Si el backend responde 401 a una petición con token (sesión vencida o
  // contraseña cambiada), se borra la sesión y se vuelve a la bienvenida.
  ApiClient.onSesionVencida = () {
    final estabaDentro = Session.instance.isLoggedIn;
    Session.instance.clear();
    if (estabaDentro) {
      navigatorKey.currentState?.pushAndRemoveUntil(
          AppRoutes.fade(const WelcomeScreen()), (route) => false);
    }
  };

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '¿Qué limpiamos?',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('es', 'MX'),
      supportedLocales: const [Locale('es', 'MX'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
    );
  }
}
