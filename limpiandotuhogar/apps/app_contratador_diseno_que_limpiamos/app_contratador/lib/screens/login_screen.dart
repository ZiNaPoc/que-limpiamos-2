import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../services/haptics.dart';
import '../services/session.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import 'auth_widgets.dart';
import 'home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _aviso(String mensaje) {
    setState(() => _error = mensaje);
  }

  Future<void> iniciarSesion() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final correo = emailController.text.trim();
    // La contraseña NO se recorta: se guardó tal cual al registrarse.
    final contrasena = passwordController.text;

    if (correo.isEmpty || contrasena.isEmpty) {
      _aviso('Ingresa tu correo y contraseña');
      return;
    }

    setState(() => _loading = true);

    try {
      final user = await AuthApi.login(correo: correo, password: contrasena);
      if (!mounted) return;

      // Esta app es solo para clientes.
      if (user.rol != 'CLIENTE') {
        setState(() => _loading = false);
        _aviso('Esta app es solo para clientes.');
        return;
      }

      Session.instance.start(user);
      Haptics.success(context);
      // Va al inicio y quita Welcome y Login de la pila, para que el botón
      // atrás no regrese a ellas.
      AppRoutes.resetTo(context, HomeScreen(userName: user.nombre));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _aviso(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _aviso('No se pudo conectar con el servidor.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Iniciar sesión',
      subtitle: 'Qué bueno verte de nuevo.',
      footer: AuthFooterLink(
        question: '¿No tienes cuenta?',
        linkLabel: 'Crear cuenta',
        onTap: () => AppRoutes.push(context, const RegisterScreen()),
      ),
      children: [
        AppTextField(
          label: 'Correo electrónico',
          hint: '123@ejemplo.com',
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          prefixIcon: Icons.mail_outline_rounded,
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Contraseña',
          hint: 'Mínimo 8 caracteres',
          controller: passwordController,
          obscure: true,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          prefixIcon: Icons.lock_outline_rounded,
          onSubmitted: (_) => iniciarSesion(),
        ),
        const SizedBox(height: 16),
        AuthError(message: _error),
        AppButton(
          label: 'Iniciar sesión',
          icon: Icons.login_rounded,
          loading: _loading,
          onPressed: iniciarSesion,
        ),
      ],
    );
  }
}
