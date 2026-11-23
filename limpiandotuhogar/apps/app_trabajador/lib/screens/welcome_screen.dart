import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/wave_background.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Bienvenida: acceso a iniciar sesión o crear cuenta.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = AppSpacing.screen(context);
    final logoSize = (size.width * 0.46).clamp(140.0, 220.0).toDouble();

    return Scaffold(
      body: WaveBackground(
        headerHeight: size.height * 0.40,
        bottomWaves: true,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: pad + 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      SizedBox(height: size.height * 0.06),
                      AppLogo(size: logoSize, hero: true),
                      const SizedBox(height: 18),
                      Text('¿Qué limpiamos?',
                          textAlign: TextAlign.center,
                          style: AppText.display.copyWith(fontSize: 32)),
                      const SizedBox(height: 6),
                      Text(
                        'Recibe solicitudes, propone tu precio y organiza tus servicios de limpieza.',
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: 26),
                      const FadeSlideIn(
                        delay: Duration(milliseconds: 200),
                        child: _Highlights(),
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 320),
                        child: AppButton(
                          label: 'Iniciar sesión',
                          variant: AppButtonVariant.soft,
                          onPressed: () =>
                              AppRoutes.push(context, const LoginScreen()),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 420),
                        child: AppButton(
                          label: 'Crear cuenta',
                          variant: AppButtonVariant.outline,
                          onPressed: () =>
                              AppRoutes.push(context, const RegisterScreen()),
                        ),
                      ),
                      SizedBox(height: size.height * 0.09),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.notifications_active_outlined, 'Solicitudes\ncerca de ti'),
      (Icons.payments_outlined, 'Tú decides\ntu precio'),
      (Icons.event_note_outlined, 'Agenda\norganizada'),
    ];
    return Row(
      children: items
          .map((e) => Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.soft,
                      ),
                      child: Icon(e.$1, color: AppColors.primaryStrong),
                    ),
                    const SizedBox(height: 8),
                    Text(e.$2,
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(
                            color: AppColors.inkSoft,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
