import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_routes.dart';
import '../services/haptics.dart';
import '../services/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'app_bottom_nav.dart';
import 'historial_screen.dart';
import 'mis_inmuebles_screen.dart';
import 'mis_resenas_reportes_screen.dart';
import 'welcome_screen.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  // DATOS DEL USUARIO (de la sesión activa; si no hay, valores de ejemplo)
  late final TextEditingController nombre = TextEditingController(
      text: Session.instance.user?.nombre ?? 'Usuario');

  late final TextEditingController telefono = TextEditingController(
      text: Session.instance.user?.telefono ?? '1234567891');

  late final TextEditingController correo = TextEditingController(
      text: Session.instance.user?.correo ?? 'abcd@ejemplo.com');

  late String nombreMostrado = Session.instance.user?.nombre ?? 'Usuario';

  bool _guardando = false;

  @override
  void dispose() {
    nombre.dispose();
    telefono.dispose();
    correo.dispose();
    super.dispose();
  }

  String get _iniciales {
    final partes = nombreMostrado
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  // GUARDAR CAMBIOS
  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();

    if (nombre.text.trim().isEmpty ||
        telefono.text.trim().isEmpty ||
        correo.text.trim().isEmpty) {
      _aviso('Completa todos los campos', error: true);
      return;
    }

    if (!correo.text.contains('@')) {
      _aviso('Escribe un correo válido', error: true);
      return;
    }

    setState(() => _guardando = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    setState(() {
      nombreMostrado = nombre.text.trim();
      _guardando = false;
    });

    Haptics.success(context);
    _aviso('Cambios guardados');
  }

  // CERRAR SESIÓN
  Future<void> _cerrarSesion() async {
    final ok = await confirmAction(
      context,
      title: 'Cerrar sesión',
      message: '¿Quieres salir de tu cuenta?',
      confirmLabel: 'Cerrar sesión',
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await Session.instance.clear(avisarServidor: true);
    if (!mounted) return;
    AppRoutes.resetTo(context, const WelcomeScreen());
  }

  // MOSTRAR AVISOS
  void _aviso(String mensaje, {bool error = false}) {
    showToast(context, mensaje, error: error);
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context) + 4;

    return Scaffold(
      extendBody: true,
      body: WaveBackground(
        headerHeight: 250,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, MediaQuery.paddingOf(context).top + 16,
              pad, AppBottomNav.reservedHeight(context)),
          children: [
            // TÍTULO + BOTÓN HISTORIAL
            TabHeader(
              title: 'Mi perfil',
              trailing: HistoryChip(
                onPressed: () =>
                    AppRoutes.push(context, const HistorialScreen()),
              ),
            ),
            const SizedBox(height: 6),
            // Accesos a mis reseñas y mis reportes (Fase 3b).
            Wrap(
              spacing: 8,
              children: [
                ActionChip(avatar: const Icon(Icons.home_work_outlined, size: 18), label: const Text('Mis inmuebles'), onPressed: () => AppRoutes.push(context, const MisInmueblesScreen())),
                ActionChip(avatar: const Icon(Icons.star_outline_rounded, size: 18), label: const Text('Mis reseñas'), onPressed: () => AppRoutes.push(context, const MisResenasScreen())),
                ActionChip(avatar: const Icon(Icons.flag_outlined, size: 18), label: const Text('Mis reportes'), onPressed: () => AppRoutes.push(context, const MisReportesScreen())),
              ],
            ),
            const SizedBox(height: 10),

            // FOTO DE PERFIL
            Center(
              child: SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const BlobAvatar(seed: 5, size: 150),
                    AvatarCircle(
                      size: 116,
                      initials: _iniciales,
                      background: AppColors.mint,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),

            // NOMBRE
            Text(nombreMostrado,
                textAlign: TextAlign.center, style: AppText.title),
            if (Session.instance.user != null)
              Text('Cliente', textAlign: TextAlign.center, style: AppText.caption),
            const SizedBox(height: 20),

            // CAMPOS
            AppTextField(
              label: 'Nombre',
              controller: nombre,
              lockable: true,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              prefixIcon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Número telefónico',
              controller: telefono,
              lockable: true,
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'Correo electrónico',
              controller: correo,
              lockable: true,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.mail_outline_rounded,
            ),
            const SizedBox(height: 14),

            // INE
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('INE',
                        style: AppText.subtitle.copyWith(color: Colors.white)),
                  ),
                  const Pill(
                    label: 'Verificada',
                    background: AppColors.mint,
                    foreground: AppColors.successFg,
                    dense: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // BOTÓN GUARDAR
            AppButton(
              label: 'Guardar cambios',
              icon: Icons.save_outlined,
              loading: _guardando,
              onPressed: _guardar,
            ),
            const SizedBox(height: 18),
            Center(
              child: AppLinkButton(
                label: 'Cerrar sesión',
                onPressed: _cerrarSesion,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }
}
