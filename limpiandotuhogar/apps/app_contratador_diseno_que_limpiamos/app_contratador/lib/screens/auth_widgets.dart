import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/wave_background.dart';

/// Estructura de Iniciar sesión / Crear cuenta: ondas, botón de regresar,
/// logotipo, título y subtítulo.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
    this.logoSize = 92,
    this.headerFactor = 0.30,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;
  final double logoSize;

  /// Alto de la onda superior como fracción de la pantalla.
  final double headerFactor;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = AppSpacing.screen(context) + 8;

    return Scaffold(
      body: WaveBackground(
        headerHeight: size.height * headerFactor,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              pad, MediaQuery.paddingOf(context).top + 8, pad, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: 'Regresar',
                    background: AppColors.fade(Colors.white, 0.8),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  AppLogo(size: logoSize, hero: true),
                ],
              ),
              SizedBox(height: size.height * 0.04),
              FadeSlideIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.display),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: AppText.subtitle
                            .copyWith(color: AppColors.inkSoft)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ...children,
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «¿No tienes cuenta? Crear cuenta».
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.question,
    required this.linkLabel,
    required this.onTap,
  });

  final String question;
  final String linkLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: AppText.bodyStrong),
        AppLinkButton(label: linkLabel, onPressed: onTap),
      ],
    );
  }
}

/// Mensaje de error bajo el formulario, con animación de aparición.
class AuthError extends StatelessWidget {
  const AuthError({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return AnimatedSize(
      duration: AppDurations.medium,
      child: m == null
          ? const SizedBox(width: double.infinity, height: 8)
          : Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: NoticeBox.error(message: m),
            ),
    );
  }
}

/// Recuadro para subir una foto (frente / reverso de la INE).
class UploadBox extends StatelessWidget {
  const UploadBox({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.15,
      child: Material(
        color: AppColors.ice,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 1.4),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.upload_rounded, color: AppColors.ink, size: 28),
                const SizedBox(height: 6),
                Text(label, style: AppText.label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
