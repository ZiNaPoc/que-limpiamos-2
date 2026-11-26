import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/mock_data.dart';
import '../models/worker_profile.dart';
import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/formatters.dart';
import '../services/haptics.dart';
import '../services/photo_picker.dart';
import '../services/session.dart';
import '../services/validators.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_modals.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/preferences_sheet.dart';
import '../widgets/wave_background.dart';
import 'availability_screen.dart';
import 'earnings_screen.dart';
import 'notifications_screen.dart';
import 'welcome_screen.dart';

/// Perfil del trabajador: datos editables, especialidades, INE y ajustes.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  Set<String> _specialties = {};
  bool _editingSpecialties = false;
  bool _saving = false;
  WorkerProfile? _loaded;

  /// Se incrementa al restablecer para reconstruir los campos bloqueados.
  int _formVersion = 0;

  @override
  void initState() {
    super.initState();
    for (final c in [_first, _last, _email, _phone]) {
      c.addListener(_onChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = AppScope.of(context).profile;
    // Sincroniza si el perfil cambió fuera de esta pantalla (p. ej. al
    // restablecer la demostración o iniciar sesión con otra cuenta).
    if (_loaded == null || _loaded!.email != profile.email ||
        _loaded!.memberSince != profile.memberSince) {
      _load(profile);
    }
  }

  bool _syncing = false;

  void _load(WorkerProfile p) {
    _syncing = true;
    _loaded = p;
    _first.text = p.firstName;
    _last.text = p.lastName;
    _email.text = p.email;
    _phone.text = p.phone;
    _specialties = p.specialties.toSet();
    _formVersion++;
    _syncing = false;
  }

  void _onChanged() {
    if (mounted && !_syncing) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isDirty(WorkerProfile p) =>
      _first.text.trim() != p.firstName ||
      _last.text.trim() != p.lastName ||
      _email.text.trim().toLowerCase() != p.email ||
      _phone.text.trim() != p.phone ||
      _specialties.length != p.specialties.length ||
      !_specialties.containsAll(p.specialties);

  Future<void> _save(AppState state) async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      showToast(context, 'Revisa los campos marcados.', error: true);
      return;
    }
    if (_specialties.isEmpty) {
      showToast(context, 'Elige al menos una especialidad.', error: true);
      return;
    }
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final updated = state.profile.copyWith(
      firstName: _first.text.trim(),
      lastName: _last.text.trim(),
      email: _email.text.trim().toLowerCase(),
      phone: _phone.text.trim(),
      specialties: _specialties.toList(),
    );
    _loaded = updated;
    state.updateProfile(updated);
    setState(() {
      _saving = false;
      _editingSpecialties = false;
      _formVersion++;
    });
    Haptics.success(context);
    showToast(context, 'Cambios guardados en este dispositivo.');
  }

  Future<void> _changePhoto(AppState state) async {
    final path = await PhotoPicker.pick(context, title: 'Foto de perfil');
    if (path == null || !mounted) return;
    state.updateProfile(state.profile.copyWith(photoPath: path));
    showToast(context, 'Foto de perfil actualizada.');
  }

  Future<void> _logout(AppState state) async {
    final ok = await confirmAction(
      context,
      title: 'Cerrar sesión',
      message: 'Tus datos se conservarán en este dispositivo.',
      confirmLabel: 'Cerrar sesión',
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await Session.instance.clear(avisarServidor: true);
    state.logout();
    if (!mounted) return;
    AppRoutes.resetTo(context, const WelcomeScreen());
  }

  Future<void> _resetDemo(AppState state) async {
    final ok = await confirmAction(
      context,
      title: 'Restablecer demostración',
      message:
          'Se restaurarán las solicitudes, la agenda, el historial y el perfil de prueba. Los cambios locales se perderán.',
      confirmLabel: 'Restablecer',
      icon: Icons.restart_alt_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    state.resetDemo();
    setState(() => _load(state.profile));
    showToast(context, 'Datos de demostración restablecidos.');
  }

  void _showIne(WorkerProfile p) {
    final verified = p.ineStatus == IneStatus.verificada;
    showAppSheet<void>(
      context,
      title: 'Identificación oficial (INE)',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          verified
              ? const NoticeBox.success(
                  message: 'Tu identificación está verificada.')
              : const NoticeBox.warning(
                  message:
                      'Tu INE está en revisión (simulado). Puedes seguir usando la app mientras tanto.'),
          const SizedBox(height: 14),
          if (p.ineFrontPath != null && p.ineBackPath != null)
            Row(
              children: [
                for (final (label, path) in [
                  ('Frente', p.ineFrontPath!),
                  ('Reverso', p.ineBackPath!),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: AspectRatio(
                              aspectRatio: 1.5,
                              child: AppImage(
                                  path: path, isAsset: false, cacheWidth: 400),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(label, style: AppText.caption),
                        ],
                      ),
                    ),
                  ),
              ],
            )
          else
            Text(
              'Los documentos de la cuenta de prueba no se muestran por privacidad.',
              style: AppText.body,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile;
    final pad = AppSpacing.screen(context);
    final dirty = _isDirty(p);
    final verified = p.ineStatus == IneStatus.verificada;

    return WaveBackground(
      headerHeight: 330,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              pad, MediaQuery.paddingOf(context).top + 12, pad, 28),
          children: [
            Row(
              children: [
                Expanded(child: Text('Mi perfil', style: AppText.display)),
                CircleIconButton(
                  icon: Icons.notifications_none_rounded,
                  tooltip: 'Notificaciones',
                  badge: state.unreadCount,
                  onPressed: () =>
                      AppRoutes.push(context, const NotificationsScreen()),
                ),
                const SizedBox(width: 8),
                const AppLogo(size: 52),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                onTap: () => _changePhoto(state),
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: AvatarCircle(
                        size: 124,
                        photoPath: p.photoPath,
                        initials:
                            '${p.firstName.isEmpty ? '' : p.firstName[0]}${p.lastName.isEmpty ? '' : p.lastName[0]}',
                        background: AppColors.steel,
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryStrong,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(Icons.photo_camera_outlined,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(p.fullName, textAlign: TextAlign.center, style: AppText.title),
            Text(
              '${state.averageRating.toStringAsFixed(1)} escobas · ${state.completedJobs.length} servicios · desde ${Fmt.monthYear(p.memberSince)}',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
            const SizedBox(height: 18),
            KeyedSubtree(
              key: ValueKey(_formVersion),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    label: 'Nombres',
                    controller: _first,
                    lockable: true,
                    textCapitalization: TextCapitalization.words,
                    validator: Validators.name,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Apellidos',
                    controller: _last,
                    lockable: true,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => Validators.notEmpty(v, field: 'El apellido'),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Correo',
                    controller: _email,
                    lockable: true,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    label: 'Número',
                    controller: _phone,
                    lockable: true,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: Validators.phone,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Text('Horario de disponibilidad', style: AppText.subtitle),
            ),
            AppCard(
              radius: AppRadius.pill,
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              onTap: () => AppRoutes.push(context, const AvailabilityScreen()),
              child: Row(
                children: [
                  Expanded(
                    child: Text(state.scheduleSummary, style: AppText.bodyStrong),
                  ),
                  Pill(
                    label: state.isOnline ? 'Activa' : 'Inactiva',
                    background:
                        state.isOnline ? AppColors.mint : AppColors.cloud,
                    foreground:
                        state.isOnline ? AppColors.successFg : AppColors.inkSoft,
                    dense: true,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, color: AppColors.inkSoft),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Text('Especialidades', style: AppText.subtitle),
            ),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _editingSpecialties
                              ? 'Toca para agregar o quitar'
                              : '${_specialties.length} seleccionadas',
                          style: AppText.caption,
                        ),
                      ),
                      IconButton(
                        tooltip: _editingSpecialties
                            ? 'Terminar edición'
                            : 'Editar especialidades',
                        onPressed: () => setState(
                            () => _editingSpecialties = !_editingSpecialties),
                        icon: Icon(
                          _editingSpecialties
                              ? Icons.check_rounded
                              : Icons.edit_outlined,
                          color: _editingSpecialties
                              ? AppColors.primaryStrong
                              : AppColors.inkSoft,
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: AppDurations.medium,
                    alignment: Alignment.topCenter,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (_editingSpecialties
                              ? MockData.allSpecialties
                              : _specialties.toList())
                          .map((s) {
                        final selected = _specialties.contains(s);
                        return FilterChip(
                          label: Text(s),
                          selected: selected,
                          showCheckmark: _editingSpecialties,
                          checkmarkColor: Colors.white,
                          labelStyle: AppText.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : AppColors.ink,
                          ),
                          selectedColor: AppColors.primaryStrong,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                              color: selected
                                  ? AppColors.primaryStrong
                                  : AppColors.border),
                          shape: const StadiumBorder(),
                          onSelected: _editingSpecialties
                              ? (v) => setState(() {
                                    if (v) {
                                      _specialties.add(s);
                                    } else {
                                      _specialties.remove(s);
                                    }
                                  })
                              : (_) => setState(() => _editingSpecialties = true),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => _showIne(p),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.badge_outlined, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('INE',
                            style: AppText.subtitle.copyWith(color: Colors.white)),
                      ),
                      Pill(
                        label: p.ineStatus.label,
                        background: verified ? AppColors.mint : AppColors.warningBg,
                        foreground:
                            verified ? AppColors.successFg : AppColors.warningFg,
                        dense: true,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: dirty
                  ? const Padding(
                      key: ValueKey('dirty'),
                      padding: EdgeInsets.only(bottom: 10),
                      child: NoticeBox(
                        icon: Icons.edit_note_rounded,
                        message: 'Tienes cambios sin guardar.',
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('clean')),
            ),
            AppButton(
              label: 'Guardar cambios',
              loading: _saving,
              onPressed: dirty ? () => _save(state) : null,
            ),
            const SizedBox(height: 24),
            const SectionTitle('Configuración'),
            _SettingsTile(
              icon: Icons.tune_rounded,
              title: 'Preferencias',
              subtitle: 'Alertas, vibración, distancia y horario',
              onTap: () => showPreferencesSheet(context),
            ),
            _SettingsTile(
              icon: Icons.toggle_on_outlined,
              title: 'Disponibilidad',
              subtitle: state.isOnline ? 'Activa' : 'Inactiva',
              onTap: () => AppRoutes.push(context, const AvailabilityScreen()),
            ),
            _SettingsTile(
              icon: Icons.insights_rounded,
              title: 'Ingresos y actividad',
              subtitle: '${Fmt.money(state.totalEarnings)} MXN en total',
              onTap: () => AppRoutes.push(context, const EarningsScreen()),
            ),
            _SettingsTile(
              icon: Icons.notifications_none_rounded,
              title: 'Notificaciones',
              subtitle: state.unreadCount == 0
                  ? 'Sin pendientes'
                  : '${state.unreadCount} sin leer',
              onTap: () => AppRoutes.push(context, const NotificationsScreen()),
            ),
            _SettingsTile(
              icon: Icons.restart_alt_rounded,
              title: 'Restablecer demostración',
              subtitle: 'Vuelve a los datos de prueba iniciales',
              onTap: () => _resetDemo(state),
            ),
            const SizedBox(height: 10),
            Center(
              child: AppLinkButton(
                label: 'Cerrar sesión',
                onPressed: () => _logout(state),
              ),
            ),
            const SizedBox(height: 4),
            Text('¿Qué limpiamos? · Colaboradores v1.0.0 (demostración local)',
                textAlign: TextAlign.center, style: AppText.caption),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration:
                  const BoxDecoration(color: AppColors.ice, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primaryStrong, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong),
                  Text(subtitle, style: AppText.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}
