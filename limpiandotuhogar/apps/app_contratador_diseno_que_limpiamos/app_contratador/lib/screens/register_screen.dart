import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../services/haptics.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import 'auth_widgets.dart';
import 'home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  void _aviso(String mensaje) {
    setState(() => _error = mensaje);
  }

  void _subirIne() {
    // TODO: elegir foto (image_picker). Fuera del MVP.
    showToast(context, 'La carga de la INE estará disponible pronto.',
        icon: Icons.badge_outlined);
  }

  Future<void> crearCuenta() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final nombre = nameController.text.trim();
    final telefono = phoneController.text.trim();
    final correo = emailController.text.trim();
    final contrasena = passwordController.text;
    final confirmar = confirmController.text;

    if (nombre.isEmpty ||
        telefono.isEmpty ||
        correo.isEmpty ||
        contrasena.isEmpty ||
        confirmar.isEmpty) {
      _aviso('Completa todos los campos');
      return;
    }
    if (telefono.length != 10) {
      _aviso('El número telefónico debe tener 10 dígitos');
      return;
    }
    if (!correo.contains('@') || !correo.contains('.')) {
      _aviso('Escribe un correo válido');
      return;
    }
    if (contrasena.length < 8) {
      _aviso('La contraseña debe tener mínimo 8 caracteres');
      return;
    }
    if (contrasena != confirmar) {
      _aviso('Las contraseñas no coinciden');
      return;
    }

    setState(() => _loading = true);

    try {
      final sesion = await AuthApi.registro(
        nombre: nombre,
        correo: correo,
        telefono: telefono,
        password: contrasena,
      );
      if (!mounted) return;
      final user = sesion.usuario;

      await Session.instance.start(sesion);
      if (!mounted) return;
      Haptics.success(context);

      // Va al inicio y quita Welcome, Login y Registro de la pila,
      // para que el botón atrás no regrese a ellas.
      AppRoutes.resetTo(context, HomeScreen(userName: user.nombre));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      // 409 = correo o teléfono ya registrado; el mensaje viene del backend.
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
      title: 'Crear cuenta',
      subtitle: 'Ingrese su información personal.',
      logoSize: 72,
      headerFactor: 0.26,
      children: [
        AppTextField(
          label: 'Nombre',
          hint: 'Tu nombre',
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          prefixIcon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Número telefónico',
          hint: '10 dígitos',
          controller: phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          prefixIcon: Icons.phone_outlined,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Correo electrónico',
          hint: '123@ejemplo.com',
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          prefixIcon: Icons.mail_outline_rounded,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Contraseña',
          hint: 'Mínimo 8 caracteres',
          controller: passwordController,
          obscure: true,
          textInputAction: TextInputAction.next,
          prefixIcon: Icons.lock_outline_rounded,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Confirmar contraseña',
          hint: 'Repite tu contraseña',
          controller: confirmController,
          obscure: true,
          textInputAction: TextInputAction.done,
          prefixIcon: Icons.lock_reset_rounded,
          onSubmitted: (_) => crearCuenta(),
        ),
        const SizedBox(height: 22),
        Text('Identificación oficial (INE)', style: AppText.subtitle),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: UploadBox(label: 'Subir frente', onTap: _subirIne),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: UploadBox(label: 'Subir reverso', onTap: _subirIne),
            ),
          ],
        ),
        const SizedBox(height: 22),
        AuthError(message: _error),
        AppButton(
          label: 'Crear cuenta',
          loading: _loading,
          onPressed: crearCuenta,
        ),
      ],
    );
  }
}
