import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../services/app_scope.dart';
import '../services/haptics.dart';
import '../services/modo_demo.dart';
import '../services/session.dart';
import '../services/validators.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/wave_background.dart';
import 'forgot_password_screen.dart';
import 'main_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _fillDemo() {
    setState(() {
      _email.text = MockData.demoEmail;
      _password.text = MockData.demoPassword;
      _error = null;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);

    try {
      final sesion = await AuthApi.login(
        identificador: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      final user = sesion.usuario;

      await Session.instance.start(sesion);
      if (!mounted) return;
      AppScope.read(context).loginRemote(
        workerId: user.id,
        name: user.nombre,
        email: user.correo,
        phone: '${user.telefono ?? ''}',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      // Cualquier otro error (sin red, JSON inválido, etc.).
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo conectar con el servidor.';
      });
      return;
    }

    if (!mounted) return;
    Haptics.success(context);
    AppRoutes.resetTo(context, const MainShell());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = AppSpacing.screen(context) + 8;
    final logoSize = (size.width * 0.40).clamp(120.0, 190.0).toDouble();

    return Scaffold(
      body: WaveBackground(
        headerHeight: size.height * 0.36,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              pad, MediaQuery.paddingOf(context).top + 8, pad, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: CircleIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: 'Regresar',
                    background: AppColors.fade(Colors.white, 0.7),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                Center(child: AppLogo(size: logoSize, hero: true)),
                const SizedBox(height: 8),
                Text('¿Qué limpiamos?',
                    textAlign: TextAlign.center,
                    style: AppText.display.copyWith(fontSize: 30)),
                Text('Inicia sesión para ver tus solicitudes',
                    textAlign: TextAlign.center, style: AppText.body),
                const SizedBox(height: 26),
                AppTextField(
                  label: 'Correo',
                  hint: 'tu@correo.com',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  prefixIcon: Icons.mail_outline_rounded,
                  validator: Validators.email,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  label: 'Contraseña',
                  hint: 'Tu contraseña',
                  controller: _password,
                  obscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  prefixIcon: Icons.lock_outline_rounded,
                  onSubmitted: (_) => _submit(),
                  validator: (v) =>
                      Validators.notEmpty(v, field: 'La contraseña'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AppLinkButton(
                    label: '¿Olvidaste tu contraseña?',
                    fontSize: 13,
                    onPressed: () => AppRoutes.push(context,
                        ForgotPasswordScreen(initialEmail: _email.text)),
                  ),
                ),
                AnimatedSize(
                  duration: AppDurations.medium,
                  child: _error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NoticeBox.error(message: _error!),
                        ),
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: 'Iniciar sesión',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('¿No tienes cuenta?', style: AppText.bodyStrong),
                    AppLinkButton(
                      label: 'Crear cuenta',
                      onPressed: () => Navigator.of(context).pushReplacement(
                          AppRoutes.fadeSlide(const RegisterScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Solo en modo demo (--dart-define=MODO_DEMO=true): las
                // compilaciones normales no muestran credenciales de prueba.
                if (modoDemo) AppCard(
                  color: AppColors.ice,
                  shadow: false,
                  onTap: _fillDemo,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.science_outlined,
                          color: AppColors.primaryStrong),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cuenta de prueba', style: AppText.label),
                            Text(
                                '${MockData.demoEmail} · ${MockData.demoPassword}',
                                style: AppText.caption),
                          ],
                        ),
                      ),
                      Text('Usar',
                          style: AppText.label
                              .copyWith(color: AppColors.primaryStrong)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
