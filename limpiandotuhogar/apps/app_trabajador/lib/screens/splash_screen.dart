import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/modo_demo.dart';
import '../services/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/wave_background.dart';
import 'main_shell.dart';
import 'welcome_screen.dart';

/// Pantalla de carga con el logotipo y ondas en movimiento suave.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _waves = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2300), _goNext);
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    final state = AppScope.read(context);
    var loggedIn = state.isLoggedIn;
    if (loggedIn && state.workerId != null) {
      // Cuenta del backend: el token guardado debe seguir siendo válido.
      loggedIn = await Session.instance.restaurar();
      if (!loggedIn) state.logout();
    } else if (loggedIn && !modoDemo) {
      // Sesión solo local (datos de demostración) fuera del modo demo: no vale.
      state.logout();
      loggedIn = false;
    }
    if (!mounted) return;
    AppRoutes.resetTo(
        context, loggedIn ? const MainShell() : const WelcomeScreen());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _waves.dispose();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final logoSize = (size.width * 0.5).clamp(150.0, 240.0).toDouble();
    final scale = CurvedAnimation(parent: _intro, curve: Curves.easeOutBack);
    final fade = CurvedAnimation(
        parent: _intro, curve: const Interval(0.45, 1, curve: Curves.easeOut));

    return Scaffold(
      body: AnimatedBuilder(
        animation: _waves,
        builder: (context, child) => WaveBackground(
          headerHeight: size.height * 0.36,
          bottomWaves: true,
          phase: _waves.value,
          child: child,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween<double>(begin: 0.6, end: 1).animate(scale),
                child: AppLogo(size: logoSize, hero: true),
              ),
              const SizedBox(height: 22),
              FadeTransition(
                opacity: fade,
                child: Column(
                  children: [
                    Text('¿Qué limpiamos?',
                        style: AppText.display.copyWith(fontSize: 28)),
                    const SizedBox(height: 4),
                    Text('Colaboradores',
                        style: AppText.subtitle
                            .copyWith(color: AppColors.inkSoft)),
                    const SizedBox(height: 26),
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
