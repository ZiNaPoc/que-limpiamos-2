import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../theme/app_colors.dart';
import 'common.dart';

/// Apariencia (texto, colores e icono) de cada estado.
class StatusStyle {
  const StatusStyle(this.label, this.background, this.foreground, this.icon);

  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;

  static StatusStyle of(ServiceRequest r) {
    if (r.takenByOther) {
      return const StatusStyle('No disponible', AppColors.cloud,
          AppColors.inkSoft, Icons.block_rounded);
    }
    if (r.status == RequestStatus.enNegociacion && r.clientOffer != null) {
      return const StatusStyle('Contraoferta', AppColors.warningBg,
          AppColors.warningFg, Icons.swap_horiz_rounded);
    }
    return forStatus(r.status);
  }

  static StatusStyle forStatus(RequestStatus s) => switch (s) {
        RequestStatus.disponible => const StatusStyle('Nueva', AppColors.aqua,
            AppColors.infoFg, Icons.fiber_new_rounded),
        RequestStatus.enNegociacion => const StatusStyle('En negociación',
            AppColors.periwinkle, AppColors.negotiationFg, Icons.forum_outlined),
        RequestStatus.pendiente => const StatusStyle('Pendiente',
            AppColors.frost, AppColors.inkSoft, Icons.hourglass_top_rounded),
        RequestStatus.aceptada => const StatusStyle('Aceptada',
            AppColors.sage, AppColors.progressFg, Icons.handshake_outlined),
        RequestStatus.confirmada => const StatusStyle('Confirmada',
            AppColors.mint, AppColors.successFg, Icons.event_available_rounded),
        RequestStatus.enCurso => const StatusStyle('En curso',
            AppColors.seafoam, AppColors.progressFg, Icons.timelapse_rounded),
        RequestStatus.finalizada => const StatusStyle('Finalizada',
            AppColors.mist, AppColors.inkSoft, Icons.task_alt_rounded),
        RequestStatus.rechazada => const StatusStyle('Rechazada',
            AppColors.errorBg, AppColors.errorFg, Icons.close_rounded),
        RequestStatus.cancelada => const StatusStyle('Cancelada',
            AppColors.errorBg, AppColors.errorFg, Icons.event_busy_rounded),
      };
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.request, this.dense = true});

  final ServiceRequest request;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.of(request);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Pill(
        key: ValueKey(style.label),
        label: style.label,
        background: style.background,
        foreground: style.foreground,
        icon: dense ? null : style.icon,
        dense: dense,
      ),
    );
  }
}
