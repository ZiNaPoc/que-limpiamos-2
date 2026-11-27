import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../services/app_scope.dart';
import '../services/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';
import 'common.dart';
import 'status_badge.dart';

/// Etiqueta y valor del precio según el estado de la negociación.
(String, String) priceLabelFor(ServiceRequest r) {
  switch (r.status) {
    case RequestStatus.disponible:
      return ('Estimado del cliente', '${Fmt.range(r.estimateMin, r.estimateMax)} MXN');
    case RequestStatus.enNegociacion:
      if (r.clientOffer != null) {
        return ('Contraoferta del cliente', '${Fmt.money(r.clientOffer!)} MXN');
      }
      return ('Estimado del cliente', '${Fmt.range(r.estimateMin, r.estimateMax)} MXN');
    case RequestStatus.pendiente:
      return ('Tu propuesta', '${Fmt.money(r.proposal?.amount ?? 0)} MXN');
    case RequestStatus.aceptada:
    case RequestStatus.confirmada:
    case RequestStatus.enCurso:
    case RequestStatus.finalizada:
      return ('Precio acordado', '${Fmt.money(r.agreedPrice ?? r.displayPrice)} MXN');
    case RequestStatus.rechazada:
    case RequestStatus.cancelada:
      return ('Estimado del cliente', '${Fmt.range(r.estimateMin, r.estimateMax)} MXN');
  }
}

class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    required this.onOpen,
    this.buttonLabel = 'Ver solicitud',
  });

  final ServiceRequest request;
  final VoidCallback onOpen;
  final String buttonLabel;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = request;

    if (r.takenByOther || r.status.isClosed) {
      return AppCard(
        color: AppColors.fade(Colors.white, 0.6),
        shadow: false,
        border: AppColors.divider,
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(r.cleaningType,
                      style: AppText.heading.copyWith(color: AppColors.inkSoft)),
                ),
                const SizedBox(width: 8),
                StatusBadge(request: r),
              ],
            ),
            const SizedBox(height: 6),
            Text(r.statusReason ?? 'Esta solicitud ya no está disponible.',
                style: AppText.bodyStrong.copyWith(color: AppColors.inkSoft)),
          ],
        ),
      );
    }

    final (priceLabel, priceValue) = priceLabelFor(r);
    final outsideSchedule =
        r.status == RequestStatus.disponible && !state.isWithinSchedule(r);
    final needsAction = r.status == RequestStatus.aceptada ||
        (r.status == RequestStatus.enNegociacion && r.clientOffer != null);

    return AppCard(
      onTap: onOpen,
      border: needsAction ? AppColors.lagoon : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(r.cleaningType, style: AppText.heading)),
              const SizedBox(width: 8),
              StatusBadge(request: r),
            ],
          ),
          // Se distingue a simple vista una solicitud REAL de una de demostración (doc 25 v2).
          Text(r.id.startsWith('api-') ? 'Solicitud real' : 'Demostración',
              style: AppText.caption.copyWith(color: r.id.startsWith('api-') ? AppColors.primaryStrong : AppColors.inkMuted)),
          const SizedBox(height: 4),
          Text(
            [...r.space.areas, if (r.extraService != null) r.extraService!]
                .join(' · '),
            style: AppText.bodyStrong,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${Fmt.relativeDay(r.scheduledAt, state.now)} · ${Fmt.time(r.scheduledAt)} · ${r.durationHours} h',
            style: AppText.bodyStrong.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 2),
          Text(
            '${r.space.zone} · ${r.space.distanceKm.toStringAsFixed(1)} km',
            style: AppText.caption,
          ),
          if (outsideSchedule || needsAction) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (outsideSchedule)
                  const Pill(
                    label: 'Fuera de tu horario',
                    icon: Icons.schedule_rounded,
                    background: AppColors.warningBg,
                    foreground: AppColors.warningFg,
                    dense: true,
                  ),
                if (needsAction)
                  const Pill(
                    label: 'Requiere tu respuesta',
                    icon: Icons.touch_app_rounded,
                    background: AppColors.ice,
                    foreground: AppColors.primaryStrong,
                    dense: true,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text(priceLabel, style: AppText.body)),
              Text(priceValue,
                  style: AppText.subtitle.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(label: buttonLabel, height: 46, onPressed: onOpen),
        ],
      ),
    );
  }
}
