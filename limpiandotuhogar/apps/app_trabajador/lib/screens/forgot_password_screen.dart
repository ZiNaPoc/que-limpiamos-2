import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/validators.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/screen_header.dart';
import '../widgets/wave_background.dart';

/// Recuperación de contraseña (simulada: no se envían correos).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _cooldownSeconds = 30;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);
  bool _loading = false;
  bool _sent = false;
  int _sentCount = 0;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    // Se consulta localmente, pero por seguridad el mensaje es el mismo
    // exista o no la cuenta.
    AppScope.read(context).requestPasswordReset(_email.text);
    setState(() {
      _loading = false;
      _sent = true;
      _sentCount++;
    });
    _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = AppSpacing.screen(context) + 8;

    return Scaffold(
      body: WaveBackground(
        headerHeight: size.height * 0.40,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeader(
                  title: 'Recuperar contraseña',
                  subtitle:
                      'Te enviaremos un enlace a tu correo para crear una nueva contraseña.',
                  subtitleStyle:
                      AppText.subtitle.copyWith(color: AppColors.inkSoft),
                  onBack: () => Navigator.of(context).maybePop(),
                  logoSize: 72,
                  heroLogo: true,
                ),
                SizedBox(height: size.height * 0.07),
                AppTextField(
                  label: 'Correo electrónico',
                  hint: 'abcde@ejemplo.com',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.mail_outline_rounded,
                  validator: Validators.email,
                  onSubmitted: (_) => _sent ? null : _send(),
                ),
                const SizedBox(height: 22),
                AnimatedSwitcher(
                  duration: AppDurations.slow,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SizeTransition(sizeFactor: a, child: child),
                  ),
                  child: _sent
                      ? _SentCard(
                          key: ValueKey(_sentCount),
                          email: _email.text.trim(),
                          count: _sentCount,
                        )
                      : AppButton(
                          key: const ValueKey('send'),
                          label: 'Enviar enlace',
                          loading: _loading,
                          onPressed: _send,
                        ),
                ),
                if (_sent) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppLinkButton(
                      label: _cooldown > 0
                          ? 'Enviar otro enlace en $_cooldown s'
                          : 'Enviar otro enlace',
                      onPressed: _cooldown > 0 || _loading ? null : _send,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppButton(
                    label: 'Volver a iniciar sesión',
                    variant: AppButtonVariant.outline,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SentCard extends StatelessWidget {
  const _SentCard({super.key, required this.email, required this.count});

  final String email;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutBack,
            builder: (context, v, child) =>
                Transform.scale(scale: v, child: child),
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: AppColors.mint, shape: BoxShape.circle),
              child: const Icon(Icons.mark_email_read_outlined,
                  color: AppColors.successFg, size: 30),
            ),
          ),
          const SizedBox(height: 12),
          Text(count > 1 ? 'Enlace reenviado' : 'Revisa tu correo',
              style: AppText.heading),
          const SizedBox(height: 6),
          Text(
            'Si $email está registrado, recibirás un enlace para restablecer tu contraseña.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: 10),
          const NoticeBox(
            icon: Icons.science_outlined,
            message:
                'Versión de demostración: el envío es simulado y no se manda ningún correo.',
          ),
        ],
      ),
    );
  }
}
