import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import 'collaborators_screen.dart';
import 'cotizacion_screen.dart';
import 'service_request_data.dart';

/// Tarjeta modal: horario/fecha y, después, cómo elegir colaborador.
/// Se muestra con `showAppDialog`.
class ScheduleDialog extends StatefulWidget {
  const ScheduleDialog({
    super.key,
    required this.serviceTitle,
    required this.price,
    required this.image,
    required this.request,
  });

  final String serviceTitle;
  final String price; // ej. "Desde $400"
  final String image;
  final ServiceRequestData request;

  @override
  State<ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<ScheduleDialog> {
  static const String _msgFalta = 'Elige horario y fecha para continuar';
  static const String _msgPasado =
      'Elige una fecha y hora que aún no hayan pasado';

  TimeOfDay? time;
  DateTime? date;
  bool scheduleOpen = true; // sección de horario y fecha abierta
  bool confirmed = false; // ya dio Ok -> aparece la elección de colaborador
  bool showError = false;
  String errorMsg = _msgFalta;

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final periodo = t.period == DayPeriod.am ? 'a.m.' : 'p.m.';
    return '$h:$m $periodo';
  }

  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy';
  }

  static const List<String> _dias = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: time ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Horario de tu limpieza',
    );
    if (picked != null && mounted) {
      setState(() {
        time = picked;
        showError = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final hoy = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: date ?? hoy,
      firstDate: hoy,
      lastDate: hoy.add(const Duration(days: 365)),
      helpText: 'Fecha de tu limpieza',
    );
    if (picked != null && mounted) {
      setState(() {
        date = picked;
        showError = false;
      });
    }
  }

  void _confirmar() {
    final d = date;
    final t = time;
    if (t == null || d == null) {
      setState(() {
        showError = true;
        errorMsg = _msgFalta;
      });
      return;
    }

    // La fecha y hora combinadas deben ser futuras: si no, el trabajador
    // no podría aceptar la solicitud.
    final fecha = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (!fecha.isAfter(DateTime.now())) {
      setState(() {
        showError = true;
        errorMsg = _msgPasado;
      });
      return;
    }

    setState(() {
      showError = false;
      confirmed = true;
      scheduleOpen = false; // se oculta con animación
    });
  }

  void _elegir(Widget Function(ServiceRequestData data) crearPantalla) {
    final data = widget.request.copyWith(date: date, time: time);
    final nav = Navigator.of(context);
    nav.pop(); // cierra el diálogo
    nav.push(AppRoutes.fadeSlide(crearPantalla(data)));
  }

  @override
  Widget build(BuildContext context) {
    final d = date;
    final t = time;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Encabezado: foto + título + precio
          Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.md),
                  bottomRight: Radius.circular(AppRadius.md),
                  topRight: Radius.circular(6),
                  bottomLeft: Radius.circular(6),
                ),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: ServiceImage(path: widget.image, cacheWidth: 200),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.serviceTitle, style: AppText.heading),
                    Text(widget.price, style: AppText.caption),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: AppColors.inkSoft),
              ),
            ],
          ),
          const Divider(height: 28, color: AppColors.divider),

          // ── HORARIO Y FECHA ──
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: confirmed
                ? () => setState(() => scheduleOpen = !scheduleOpen)
                : null,
            child: Row(
              children: [
                Expanded(
                  child: Text('Elige horario y fecha de tu limpieza',
                      style: AppText.heading),
                ),
                if (confirmed)
                  AnimatedRotation(
                    turns: scheduleOpen ? 0.5 : 0,
                    duration: AppDurations.medium,
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.inkSoft),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: AppDurations.medium,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: scheduleOpen
                ? _scheduleContent()
                : (confirmed && d != null && t != null)
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 18, color: AppColors.successFg),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${_dias[d.weekday - 1]} ${_fmtDate(d)} · ${_fmtTime(t)}',
                                style: AppText.bodyStrong
                                    .copyWith(color: AppColors.successFg),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
          ),

          // ── ELECCIÓN DE COLABORADOR (aparece tras el Ok) ──
          AnimatedSize(
            duration: AppDurations.slow,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: confirmed
                ? _collaboratorSection()
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _scheduleContent() {
    final t = time;
    final d = date;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  label: 'Horario',
                  value: t == null ? '00:00' : _fmtTime(t),
                  icon: Icons.schedule_rounded,
                  empty: t == null,
                  onTap: _pickTime,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerField(
                  label: 'Fecha',
                  value: d == null ? '00/00/00' : _fmtDate(d),
                  icon: Icons.calendar_month_rounded,
                  empty: d == null,
                  onTap: _pickDate,
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: AppDurations.medium,
            child: showError
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NoticeBox.warning(message: errorMsg),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Ok',
              expand: false,
              height: 42,
              onPressed: _confirmar,
            ),
          ),
        ],
      ),
    );
  }

  Widget _collaboratorSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('¿Cómo quieres elegir a tu colaborador?',
              style: AppText.heading),
          const SizedBox(height: 12),

          // Opción 1: Elegir personalmente
          FadeSlideIn(
            child: _ModeOption(
              icon: Icons.person_search_outlined,
              title: 'Elegir personalmente',
              subtitle: 'Revisa perfiles y escoge a quien prefieras',
              dark: false,
              onTap: () =>
                  _elegir((data) => CollaboratorsScreen(request: data)),
            ),
          ),
          const SizedBox(height: 10),

          // Opción 2: Asignación automática
          FadeSlideIn(
            delay: FadeSlideIn.stagger(1),
            child: _ModeOption(
              icon: Icons.auto_awesome,
              title: 'Asignación automática',
              subtitle: 'Te asignamos a alguien disponible',
              badge: 'Más rápido',
              dark: true,
              onTap: () => _elegir((data) => CotizacionScreen(request: data)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.empty,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool empty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppText.label.copyWith(color: AppColors.primaryStrong)),
        const SizedBox(height: 6),
        Material(
          color: AppColors.ice,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: AppText.label.copyWith(
                              color:
                                  empty ? AppColors.inkMuted : AppColors.ink)),
                    ),
                  ),
                  Icon(icon, size: 18, color: AppColors.primaryStrong),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.dark,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool dark;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : AppColors.primaryStrong;
    return AppCard(
      onTap: onTap,
      color: dark ? AppColors.primaryStrong : Colors.white,
      border: dark ? null : AppColors.primaryStrong,
      shadow: dark,
      radius: AppRadius.lg,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: dark ? AppColors.mint : AppColors.ice,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.ink, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          style: AppText.bodyStrong.copyWith(
                              color: fg, fontWeight: FontWeight.w700)),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Pill(
                        label: badge!,
                        background: AppColors.mint,
                        foreground: AppColors.successFg,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                Text(subtitle,
                    style: AppText.caption.copyWith(
                        color: dark ? AppColors.frost : AppColors.inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
