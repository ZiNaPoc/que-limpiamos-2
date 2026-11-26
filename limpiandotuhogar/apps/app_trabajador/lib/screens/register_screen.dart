import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/mock_data.dart';
import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../services/app_scope.dart';
import '../services/haptics.dart';
import '../services/photo_picker.dart';
import '../services/session.dart';
import '../services/validators.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/screen_header.dart';
import '../widgets/wave_background.dart';
import 'login_screen.dart';
import 'main_shell.dart';

/// Registro en dos pasos: datos personales e identificación oficial (opcional).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  int _step = 0;
  String? _ineFront;
  String? _ineBack;
  final Set<String> _specialties = {};
  bool _terms = false;
  bool _showStep2Errors = false;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      showToast(context, 'Revisa los campos marcados.', error: true);
      return;
    }
    setState(() => _step = 1);
  }

  void _back() {
    if (_step == 1) {
      setState(() => _step = 0);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// La INE es opcional: solo se exige especialidad y términos.
  String? get _step2Error {
    if (_specialties.isEmpty) return 'Elige al menos una especialidad.';
    if (!_terms) return 'Debes aceptar los términos para continuar.';
    return null;
  }

  Future<void> _pickIne(bool front) async {
    final path = await PhotoPicker.pick(context,
        title: front ? 'INE · Frente' : 'INE · Reverso');
    if (path == null || !mounted) return;
    setState(() {
      if (front) {
        _ineFront = path;
      } else {
        _ineBack = path;
      }
    });
  }

  Future<void> _create() async {
    setState(() => _showStep2Errors = true);
    if (_step2Error != null) return;
    setState(() => _loading = true);

    // 1) Crear la cuenta en el backend.
    final ApiUser user;
    try {
      final sesion = await AuthApi.registro(
        nombre: _name.text,
        correo: _email.text,
        telefono: _phone.text,
        direccion: _address.text,
        password: _password.text,
      );
      if (!mounted) return;
      user = sesion.usuario;
      await Session.instance.start(sesion);
      if (!mounted) return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 409 = correo o teléfono repetido: regresamos al paso de datos.
        if (e.statusCode == 409) _step = 0;
      });
      showToast(context, e.message, error: true);
      return;
    }

    // 2) INE y especialidades todavía no existen en la BD:
    //    se siguen guardando localmente como antes.
    //    La INE es opcional: si no se subió, se manda vacía.
    AppScope.read(context).register(
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      // La contraseña vive solo en el backend (bcrypt): no se guarda en el teléfono.
      password: '',
      ineFrontPath: _ineFront ?? '',
      ineBackPath: _ineBack ?? '',
      specialties: _specialties.toList(),
    );
    // 3) Vincular la cuenta del backend y empezar a recibir solicitudes.
    AppScope.read(context).bindRemoteWorker(user.id);

    final hasIne = _ineFront != null && _ineBack != null;

    Haptics.success(context);
    setState(() => _loading = false);
    await showAppDialog<void>(
      context,
      dismissible: false,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: AppColors.mint, shape: BoxShape.circle),
              child: const Icon(Icons.verified_user_outlined,
                  size: 36, color: AppColors.successFg),
            ),
            const SizedBox(height: 14),
            Text('¡Cuenta creada!', style: AppText.title),
            const SizedBox(height: 6),
            Text(
              hasIne
                  ? 'Tu INE quedó «En revisión». Mientras tanto ya puedes recibir solicitudes de clientes.'
                  : 'Ya puedes recibir solicitudes de clientes. Puedes subir tu INE más adelante para verificar tu cuenta.',
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            AppButton(
              label: 'Comenzar',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    AppRoutes.resetTo(context, const MainShell());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = AppSpacing.screen(context) + 4;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _step = 0);
      },
      child: Scaffold(
        body: WaveBackground(
          headerHeight: size.height * 0.34,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScreenHeader(
                  title: '¡Crea tu cuenta!',
                  subtitle: _step == 0
                      ? 'Ingresa tu información personal.'
                      : 'Elige tus especialidades y, si quieres, verifica tu identidad.',
                  subtitleStyle:
                      AppText.subtitle.copyWith(color: AppColors.inkSoft),
                  onBack: _back,
                  logoSize: 70,
                  heroLogo: true,
                ),
                const SizedBox(height: 16),
                _StepIndicator(step: _step),
                const SizedBox(height: 20),
                Form(
                  key: _formKey,
                  child: AnimatedSwitcher(
                    duration: AppDurations.slow,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final forward = child.key == const ValueKey(1);
                      final begin = Offset(forward ? 0.15 : -0.15, 0);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: begin, end: Offset.zero)
                              .animate(animation),
                          child: child,
                        ),
                      );
                    },
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [...previous, if (current != null) current],
                    ),
                    child: _step == 0
                        ? KeyedSubtree(
                            key: const ValueKey(0), child: _personalForm())
                        : KeyedSubtree(
                            key: const ValueKey(1), child: _identityStep()),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('¿Ya tienes cuenta?', style: AppText.bodyStrong),
                    AppLinkButton(
                      label: 'Inicia sesión',
                      onPressed: () => Navigator.of(context).pushReplacement(
                          AppRoutes.fadeSlide(const LoginScreen())),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _personalForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Nombre completo',
          hint: 'Tu nombre y apellidos',
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          validator: Validators.name,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Número telefónico',
          hint: '10 dígitos',
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          validator: Validators.phone,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Correo electrónico',
          hint: '123@ejemplo.com',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          validator: Validators.email,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Dirección',
          hint: 'Calle, número y colonia',
          controller: _address,
          keyboardType: TextInputType.streetAddress,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.fullStreetAddress],
          validator: (v) => (v == null || v.trim().length < 5)
              ? 'Escribe tu dirección (mínimo 5 caracteres).'
              : null,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Contraseña',
          hint: 'Mínimo 8 caracteres',
          controller: _password,
          obscure: true,
          textInputAction: TextInputAction.next,
          validator: Validators.password,
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Confirmar contraseña',
          hint: 'Repite tu contraseña',
          controller: _confirm,
          obscure: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _next(),
          validator: (v) => Validators.confirm(v, _password.text),
        ),
        const SizedBox(height: 22),
        AppButton(
          label: 'Continuar',
          icon: Icons.arrow_forward_rounded,
          onPressed: _next,
        ),
      ],
    );
  }

  Widget _identityStep() {
    final error = _showStep2Errors ? _step2Error : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Identificación oficial (INE) · Opcional',
            textAlign: TextAlign.center, style: AppText.heading),
        const SizedBox(height: 4),
        Text(
            'Puedes subirla ahora o más tarde. Las fotos se guardan solo en este dispositivo.',
            textAlign: TextAlign.center,
            style: AppText.caption),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _UploadTile(
                label: 'Subir frente',
                path: _ineFront,
                onTap: () => _pickIne(true),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _UploadTile(
                label: 'Subir reverso',
                path: _ineBack,
                onTap: () => _pickIne(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text('Especialidades', style: AppText.heading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: MockData.allSpecialties.map((s) {
            final selected = _specialties.contains(s);
            return FilterChip(
              label: Text(s),
              selected: selected,
              showCheckmark: false,
              labelStyle: AppText.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.ink,
              ),
              selectedColor: AppColors.primaryStrong,
              backgroundColor: Colors.white,
              side: BorderSide(
                  color: selected ? AppColors.primaryStrong : AppColors.border),
              shape: const StadiumBorder(),
              onSelected: (v) => setState(() {
                if (v) {
                  _specialties.add(s);
                } else {
                  _specialties.remove(s);
                }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => setState(() => _terms = !_terms),
          child: Row(
            children: [
              Checkbox(
                value: _terms,
                activeColor: AppColors.primaryStrong,
                onChanged: (v) => setState(() => _terms = v ?? false),
              ),
              Expanded(
                child: Text(
                  'Acepto los términos de uso y el aviso de privacidad.',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: AppDurations.medium,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: NoticeBox.warning(message: error),
                ),
        ),
        const SizedBox(height: 16),
        AppButton(label: 'Crear cuenta', loading: _loading, onPressed: _create),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Regresar a mis datos'),
          style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
        ),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Datos personales', 'Identificación'];
    return Row(
      children: List.generate(labels.length, (i) {
        final done = i <= step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 0 ? 8 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: AppDurations.slow,
                  curve: Curves.easeOutCubic,
                  height: 6,
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.primaryStrong
                        : AppColors.fade(Colors.white, 0.8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${i + 1}. ${labels[i]}',
                    style: AppText.caption.copyWith(
                      fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                      color: done ? AppColors.ink : AppColors.inkMuted,
                    )),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile(
      {required this.label, required this.path, required this.onTap});

  final String label;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = path;
    return AspectRatio(
      aspectRatio: 1.25,
      child: Material(
        color: AppColors.fade(AppColors.aqua, 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedSwitcher(
            duration: AppDurations.medium,
            child: p == null
                ? Container(
                    key: const ValueKey('empty'),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.lagoon, width: 1.4),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.upload_rounded,
                            color: AppColors.ink, size: 28),
                        const SizedBox(height: 6),
                        Text(label, style: AppText.label),
                      ],
                    ),
                  )
                : Stack(
                    key: ValueKey(p),
                    fit: StackFit.expand,
                    children: [
                      AppImage(path: p, isAsset: false, cacheWidth: 400),
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Pill(
                          label: 'Cambiar foto',
                          icon: Icons.check_circle_rounded,
                          background: AppColors.mint,
                          foreground: AppColors.successFg,
                          dense: true,
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
