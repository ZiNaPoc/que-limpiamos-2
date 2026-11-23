import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';

/// Historial de limpiezas (datos de ejemplo, en lo que se conecta al backend).
class HistorialScreen extends StatelessWidget {
  const HistorialScreen({super.key});

  static const _pasadas = [
    (servicio: 'Limpieza general', fecha: '15/10/2026', horario: '10:00 AM'),
    (servicio: 'Limpieza profunda', fecha: '10/10/2026', horario: '09:00 AM'),
    (servicio: 'Limpieza de cocina', fecha: '05/10/2026', horario: '12:00 PM'),
  ];

  static void _pronto(BuildContext context) {
    showToast(context, 'Esta opción estará disponible pronto.',
        icon: Icons.info_outline_rounded);
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);

    return Scaffold(
      body: WaveBackground(
        headerHeight: 200,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              pad, 0, pad, MediaQuery.paddingOf(context).bottom + 28),
          children: [
            const StepHeader(title: 'Historial'),
            const SizedBox(height: 18),

            // SERVICIO ACTUAL
            FadeSlideIn(child: _TarjetaActual(onAccion: () => _pronto(context))),
            const SizedBox(height: 26),

            // SERVICIOS PASADOS
            Text('Pasadas', style: AppText.title),
            const SizedBox(height: 12),
            for (var i = 0; i < _pasadas.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FadeSlideIn(
                  delay: FadeSlideIn.stagger(i + 1),
                  child: _TarjetaPasada(
                    servicio: _pasadas[i].servicio,
                    fecha: _pasadas[i].fecha,
                    horario: _pasadas[i].horario,
                    onAccion: () => _pronto(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// TARJETA SERVICIO ACTUAL
class _TarjetaActual extends StatelessWidget {
  const _TarjetaActual({required this.onAccion});

  final VoidCallback onAccion;

  @override
  Widget build(BuildContext context) {
    return HeroPanel(
      seed: 4,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const BlobAvatar(seed: 9, initials: 'ML', size: 76),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('María López',
                        style: AppText.heading.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Horario: 10:00 AM - 12:00 PM',
                        style: AppText.caption.copyWith(color: AppColors.ice)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.fade(Colors.white, 0.94),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Linea('Servicio', 'Limpieza general'),
                _Linea('Fecha', '20/10/2026'),
                _Linea('Horario', '10:00 AM'),
                _Linea('Precio', '\$350 MXN'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _BotonPildora(label: 'Eliminar limpieza', onTap: onAccion),
              const SizedBox(width: 8),
              _BotonPildora(
                  label: 'Editar limpieza', filled: true, onTap: onAccion),
            ],
          ),
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: AppText.body.copyWith(color: AppColors.inkSoft, fontSize: 13),
          children: [
            TextSpan(
                text: value, style: AppText.bodyStrong.copyWith(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _BotonPildora extends StatelessWidget {
  const _BotonPildora(
      {required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Material(
        color: filled ? AppColors.ice : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            alignment: Alignment.center,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(
                    fontSize: 12,
                    color: filled ? AppColors.primaryStrong : AppColors.ink)),
          ),
        ),
      ),
    );
  }
}

// TARJETAS DE SERVICIOS PASADOS
class _TarjetaPasada extends StatelessWidget {
  const _TarjetaPasada({
    required this.servicio,
    required this.fecha,
    required this.horario,
    required this.onAccion,
  });

  final String servicio;
  final String fecha;
  final String horario;
  final VoidCallback onAccion;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: AppRadius.xl,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                color: AppColors.mint, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded,
                color: AppColors.successFg, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(servicio,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('$fecha   $horario', style: AppText.caption),
                const SizedBox(height: 4),
                const Pill(
                  label: 'Finalizada',
                  icon: Icons.task_alt_rounded,
                  background: AppColors.frost,
                  foreground: AppColors.inkSoft,
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BotonContorno(label: 'Reagendar', onTap: onAccion),
                const SizedBox(height: 6),
                _BotonContorno(label: 'Reportar', onTap: onAccion),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// BOTONES CON CONTORNO
class _BotonContorno extends StatelessWidget {
  const _BotonContorno({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: AppColors.primary, width: 1.2),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(label,
              textAlign: TextAlign.center,
              style: AppText.label
                  .copyWith(fontSize: 12, color: AppColors.primaryStrong)),
        ),
      ),
    );
  }
}
