import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/wave_background.dart';
import 'home_screen.dart';
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

  /// Restauración de la sesión guardada (token en almacenamiento seguro).
  late final Future<bool> _restaurando;

  @override
  void initState() {
    super.initState();
    // Empieza a restaurar la sesión mientras corre la animación.
    _restaurando = Session.instance.restaurar();
    _timer = Timer(const Duration(seconds: 3), _goNext);
  }

  Future<void> _goNext() async {
    final conSesion = await _restaurando;
    if (!mounted) return;
    final usuario = Session.instance.user;
    AppRoutes.resetTo(
      context,
      conSesion && usuario != null
          ? HomeScreen(userName: usuario.nombre)
          : const WelcomeScreen(),
    );
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
                    Text('Limpieza para tu hogar',
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
