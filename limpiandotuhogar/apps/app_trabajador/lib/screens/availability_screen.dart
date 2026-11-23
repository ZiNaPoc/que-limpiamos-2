import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../models/worker_profile.dart';
import '../services/app_scope.dart';
import '../services/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/availability_toggle.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/screen_header.dart';
import '../widgets/wave_background.dart';

/// Disponibilidad: estado activo/inactivo y horario semanal.
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen>
    with SingleTickerProviderStateMixin {
  late List<DaySchedule> _draft;
  bool _initialized = false;

  // Pulso suave que indica que el trabajador está en línea.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!_initialized) {
      _draft = List.of(state.profile.schedule);
      _initialized = true;
    }
    // Se llama también cuando cambia el estado global (AppScope).
    if (state.isOnline) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool _dirty(List<DaySchedule> saved) {
    for (final d in _draft) {
      final s = saved.firstWhere((x) => x.weekday == d.weekday,
          orElse: () => d.copyWith(enabled: !d.enabled));
      if (s.enabled != d.enabled ||
          s.startMinutes != d.startMinutes ||
          s.endMinutes != d.endMinutes) {
        return true;
      }
    }
    return false;
  }

  void _update(DaySchedule day) {
    setState(() {
      _draft = [
        for (final d in _draft) d.weekday == day.weekday ? day : d,
      ];
    });
  }

  void _preset(List<int> weekdays, int start, int end) {
    setState(() {
      _draft = List.generate(
        7,
        (i) => DaySchedule(
          weekday: i + 1,
          enabled: weekdays.contains(i + 1),
          startMinutes: start,
          endMinutes: end,
        ),
      );
    });
  }

  Future<void> _editHours(DaySchedule day) async {
    final start = await showTimePicker(
      context: context,
      helpText: 'Hora de inicio · ${Fmt.weekdayName(day.weekday)}',
      initialTime: TimeOfDay(
          hour: day.startMinutes ~/ 60, minute: day.startMinutes % 60),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      helpText: 'Hora de fin · ${Fmt.weekdayName(day.weekday)}',
      initialTime:
          TimeOfDay(hour: day.endMinutes ~/ 60, minute: day.endMinutes % 60),
    );
    if (end == null || !mounted) return;
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    if (e - s < 60) {
      showToast(context, 'La hora de fin debe ser al menos 1 hora después del inicio.',
          error: true);
      return;
    }
    _update(day.copyWith(startMinutes: s, endMinutes: e, enabled: true));
  }

  void _save() {
    final state = AppScope.read(context);
    if (!_draft.any((d) => d.enabled)) {
      showToast(context, 'Activa al menos un día de trabajo.', error: true);
      return;
    }
    state.updateSchedule(_draft);
    showToast(context, 'Horario guardado.', icon: Icons.schedule_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final online = state.isOnline;
    final dirty = _dirty(state.profile.schedule);
    final pad = AppSpacing.screen(context);

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final discard = await confirmAction(
          context,
          title: '¿Descartar cambios?',
          message: 'Tienes cambios en tu horario que no has guardado.',
          confirmLabel: 'Descartar',
          cancelLabel: 'Seguir editando',
          destructive: true,
          icon: Icons.edit_calendar_outlined,
        );
        if (discard && mounted) {
          setState(() => _draft = List.of(state.profile.schedule));
          navigator.pop();
        }
      },
      child: Scaffold(
        body: WaveBackground(
          headerHeight: 250,
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
            children: [
              ScreenHeader(
                title: 'Disponibilidad',
                subtitle: 'Controla cuándo recibes y aceptas solicitudes.',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 18),
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) => Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: online ? AppColors.successFg : AppColors.inkMuted,
                              boxShadow: online
                                  ? [
                                      BoxShadow(
                                        color: AppColors.fade(AppColors.seafoam,
                                            0.9 - _pulse.value * 0.6),
                                        blurRadius: 4 + _pulse.value * 10,
                                        spreadRadius: 2 + _pulse.value * 6,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(online ? 'Estás disponible' : 'No estás disponible',
                                  style: AppText.heading),
                              Text(
                                state.isNowWithinSchedule
                                    ? 'Ahora estás dentro de tu horario.'
                                    : 'Ahora estás fuera de tu horario.',
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ),
                        AvailabilityToggle(
                          value: online,
                          onChanged: (v) {
                            state.setOnline(v);
                            showToast(
                                context,
                                v
                                    ? 'Disponibilidad activada.'
                                    : 'Disponibilidad desactivada.');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: AppDurations.medium,
                      child: online
                          ? const NoticeBox.success(
                              key: ValueKey('on'),
                              message:
                                  'Recibes solicitudes y puedes aceptarlas. Las que estén fuera de tu horario se marcan para que lo consideres.',
                            )
                          : const NoticeBox.warning(
                              key: ValueKey('off'),
                              message:
                                  'No podrás aceptar nuevas solicitudes. Tus servicios confirmados se mantienen en tu agenda.',
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SectionTitle('Horario semanal',
                  action: dirty ? 'Deshacer' : null,
                  onAction: () => setState(
                      () => _draft = List.of(state.profile.schedule))),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Lun–Vie · 8–6'),
                    onPressed: () => _preset([1, 2, 3, 4, 5], 480, 1080),
                  ),
                  ActionChip(
                    label: const Text('Lun–Sáb · 8–7'),
                    onPressed: () => _preset([1, 2, 3, 4, 5, 6], 480, 1140),
                  ),
                  ActionChip(
                    label: const Text('Todos los días · 9–5'),
                    onPressed: () => _preset([1, 2, 3, 4, 5, 6, 7], 540, 1020),
                  ),
                  ActionChip(
                    label: const Text('Restablecer'),
                    onPressed: () =>
                        setState(() => _draft = MockData.defaultSchedule()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final day in _draft)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AnimatedOpacity(
                    duration: AppDurations.medium,
                    opacity: day.enabled ? 1 : 0.6,
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                      shadow: day.enabled,
                      border: day.enabled ? null : AppColors.divider,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              Fmt.weekdayName(day.weekday)[0].toUpperCase() +
                                  Fmt.weekdayName(day.weekday).substring(1),
                              style: AppText.subtitle,
                            ),
                          ),
                          Expanded(
                            child: TextButton(
                              onPressed: day.enabled ? () => _editHours(day) : null,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  day.enabled
                                      ? '${Fmt.minutes(day.startMinutes)} – ${Fmt.minutes(day.endMinutes)}'
                                      : 'Descanso',
                                  style: AppText.label.copyWith(
                                      color: day.enabled
                                          ? AppColors.primaryStrong
                                          : AppColors.inkMuted),
                                ),
                              ),
                            ),
                          ),
                          Switch(
                            value: day.enabled,
                            onChanged: (v) => _update(day.copyWith(enabled: v)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Resumen: ${state.scheduleSummary}', style: AppText.caption),
              const SizedBox(height: 16),
              AppButton(
                label: dirty ? 'Guardar horario' : 'Horario guardado',
                icon: dirty ? Icons.save_outlined : Icons.check_rounded,
                onPressed: dirty ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
