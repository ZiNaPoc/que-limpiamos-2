import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'navigation/app_routes.dart';
import 'navigation/navigator_key.dart';
import 'screens/welcome_screen.dart';
import 'services/api_client.dart';
import 'services/session.dart';
import 'services/app_state.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // La app se diseñó para orientación vertical.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final state = AppState(storage: StorageService());
  await state.load();

  ApiClient.onSesionVencida = () {
    final estabaDentro = Session.instance.isLoggedIn;
    Session.instance.clear();
    state.logout();
    if (estabaDentro) {
      navigatorKey.currentState?.pushAndRemoveUntil(
          AppRoutes.fade(const WelcomeScreen()), (route) => false);
    }
  };

  runApp(QueLimpiamosApp(state: state));
}
