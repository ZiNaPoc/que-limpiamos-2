import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/availability_toggle.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/screen_header.dart';
import '../widgets/status_badge.dart';
import '../widgets/wave_background.dart';
import 'availability_screen.dart';
import 'earnings_screen.dart';
import 'main_shell.dart';
import 'notifications_screen.dart';
import 'request_detail_screen.dart';

/// Inicio: resumen del día, ingresos, próximo servicio y accesos rápidos.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pad = AppSpacing.screen(context);
    final shell = MainShell.of(context);

    return WaveBackground(
      headerHeight: 330,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
        children: [
          ScreenHeader(
            eyebrow: 'Hola, ${state.profile.firstName}',
            title: 'Tu día de hoy',
            actions: [
              CircleIconButton(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Notificaciones',
                badge: state.unreadCount,
                onPressed: () =>
                    AppRoutes.push(context, const NotificationsScreen()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FadeSlideIn(child: _NewRequestsCard(state: state)),
          if (state.needsAction.isNotEmpty) ...[
            const SizedBox(height: 12),
            FadeSlideIn(
              delay: FadeSlideIn.stagger(1),
              child: _ActionBanner(
                count: state.needsAction.length,
                onTap: () => shell?.goTo(MainShellState.tabRequests,
                    filter: RequestFilter.porAcordar),
              ),
            ),
          ],
          const SizedBox(height: 14),
          FadeSlideIn(
              delay: FadeSlideIn.stagger(2), child: _EarningsCard(state: state)),
          const SizedBox(height: 10),
          SectionTitle(
            'Próximo servicio',
            action: 'Ver agenda',
            onAction: () => shell?.goTo(MainShellState.tabAgenda),
          ),
          FadeSlideIn(
            delay: FadeSlideIn.stagger(3),
            child: _NextServiceCard(request: state.nextService, state: state),
          ),
          const SizedBox(height: 12),
          const SectionTitle('Esta semana'),
          FadeSlideIn(
            delay: FadeSlideIn.stagger(4),
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    value: '${state.servicesThisWeek}',
                    label: 'Servicios',
                    icon: Icons.event_available_rounded,
                    onTap: () => shell?.goTo(MainShellState.tabAgenda),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    value: state.averageRating == 0
                        ? '—'
                        : state.averageRating.toStringAsFixed(1),
                    label: 'Calificación',
                    icon: Icons.cleaning_services_rounded,
                    onTap: () => showReviewsSheet(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    value: Fmt.money(state.earningsBetween(state.weekStart,
                        state.weekStart.add(const Duration(days: 7)))),
                    label: 'Ganado',
                    icon: Icons.payments_outlined,
                    onTap: () =>
                        AppRoutes.push(context, const EarningsScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle('Accesos rápidos'),
          FadeSlideIn(
            delay: FadeSlideIn.stagger(5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _QuickAction(
                  icon: Icons.toggle_on_outlined,
                  label: 'Disponibilidad',
                  onTap: () =>
                      AppRoutes.push(context, const AvailabilityScreen()),
                ),
                _QuickAction(
                  icon: Icons.forum_outlined,
                  label: 'Por acordar',
                  badge: state.negotiatingRequests.length,
                  onTap: () => shell?.goTo(MainShellState.tabRequests,
                      filter: RequestFilter.porAcordar),
                ),
                _QuickAction(
                  icon: Icons.insights_rounded,
                  label: 'Ingresos',
                  onTap: () =>
                      AppRoutes.push(context, const EarningsScreen()),
                ),
                _QuickAction(
                  icon: Icons.history_rounded,
                  label: 'Historial',
                  onTap: () => shell?.goTo(MainShellState.tabHistory),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewRequestsCard extends StatelessWidget {
  const _NewRequestsCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final count = state.availableRequests.length;
    final String status;
    if (!state.isOnline) {
      status = 'Tu disponibilidad está desactivada.';
    } else if (state.isNowWithinSchedule) {
      status = 'Dentro de tu horario.';
    } else {
      status = 'Fuera de tu horario en este momento.';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryStrong, AppColors.inkSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.lifted,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: AppDurations.medium,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
                    .animate(a),
                child: child,
              ),
            ),
            child: Text(
              count == 0
                  ? 'Sin solicitudes nuevas'
                  : count == 1
                      ? '1 solicitud nueva'
                      : '$count solicitudes nuevas',
              key: ValueKey(count),
              style: AppText.title.copyWith(color: Colors.white),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                state.isOnline
                    ? Icons.radio_button_checked_rounded
                    : Icons.pause_circle_outline_rounded,
                size: 14,
                color: state.isOnline ? AppColors.mint : AppColors.fog,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(status,
                    style: AppText.bodyStrong.copyWith(color: AppColors.ice)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () => MainShell.of(context)?.goTo(
                  MainShellState.tabRequests,
                  filter: RequestFilter.nuevas),
              child: SizedBox(
                height: 50,
                width: double.infinity,
                child: Center(
                  child: Text('Ver solicitudes',
                      style: AppText.button.copyWith(color: AppColors.ink)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBanner extends StatelessWidget {
  const _ActionBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.warningBg,
      shadow: false,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.touch_app_rounded, color: AppColors.warningFg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? '1 solicitud espera tu respuesta'
                  : '$count solicitudes esperan tu respuesta',
              style: AppText.bodyStrong.copyWith(color: AppColors.warningFg),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.warningFg),
        ],
      ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => AppRoutes.push(context, const EarningsScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ingresos totales', style: AppText.heading),
                    Text(
                        'Activa desde ${Fmt.monthYear(state.profile.memberSince)}',
                        style: AppText.caption),
                  ],
                ),
              ),
              AvailabilityToggle(
                value: state.isOnline,
                onChanged: (v) {
                  state.setOnline(v);
                  showToast(
                    context,
                    v
                        ? 'Disponibilidad activada: puedes aceptar solicitudes.'
                        : 'Disponibilidad desactivada: no podrás aceptar nuevas solicitudes.',
                    icon: v ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: state.totalEarnings),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    Fmt.money(v, decimals: true),
                    style: AppText.title,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('MXN', style: AppText.caption),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextServiceCard extends StatelessWidget {
  const _NextServiceCard({required this.request, required this.state});

  final ServiceRequest? request;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final r = request;
    if (r == null) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.event_busy_outlined, color: AppColors.inkMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text('No tienes servicios confirmados próximos.',
                  style: AppText.body),
            ),
          ],
        ),
      );
    }
    final running = r.status == RequestStatus.enCurso;
    return AppCard(
      border: running ? AppColors.seafoam : null,
      onTap: () =>
          AppRoutes.push(context, RequestDetailScreen(requestId: r.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(r.cleaningType, style: AppText.heading)),
              StatusBadge(request: r),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${Fmt.relativeDay(r.scheduledAt, state.now)} · ${Fmt.time(r.scheduledAt)} · ${Fmt.money(r.agreedPrice ?? r.displayPrice)} MXN',
            style: AppText.bodyStrong,
          ),
          const SizedBox(height: 2),
          Text(
            running && r.startedAt != null
                ? 'En curso desde las ${Fmt.time(r.startedAt!)}'
                : '${r.client.shortName} · ${r.space.zone}',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: AppText.title.copyWith(fontSize: 20)),
          ),
          Text(label,
              style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    // Expanded funciona aquí porque este widget es hijo directo de un Row.
    return Expanded(
      child: Column(
        children: [
          CircleIconButton(
            icon: icon,
            size: 54,
            badge: badge,
            foreground: AppColors.primaryStrong,
            onPressed: onTap,
          ),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                  color: AppColors.ink, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Hoja con las calificaciones recibidas.
Future<void> showReviewsSheet(BuildContext context) {
  final state = AppScope.read(context);
  final reviews = state.receivedReviews;
  return showAppSheet<void>(
    context,
    title: 'Tus calificaciones',
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(state.averageRating.toStringAsFixed(1),
                style: AppText.display.copyWith(fontSize: 40)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BroomRating(value: state.averageRating.round(), size: 18),
                  Text('${reviews.length} calificaciones recibidas',
                      style: AppText.caption),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (reviews.isEmpty)
          const EmptyState(
            icon: Icons.cleaning_services_outlined,
            title: 'Aún no tienes calificaciones',
            message: 'Aparecerán aquí cuando los clientes califiquen tus servicios.',
          ),
        ...reviews.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                shadow: false,
                border: AppColors.divider,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text(r.cleaningType, style: AppText.label)),
                        Text(Fmt.date(r.scheduledAt), style: AppText.caption),
                      ],
                    ),
                    const SizedBox(height: 4),
                    BroomRating(value: r.ratingReceived ?? 0, size: 14),
                    if (r.reviewReceived != null) ...[
                      const SizedBox(height: 4),
                      Text('“${r.reviewReceived}” — ${r.client.shortName}',
                          style: AppText.body),
                    ],
                  ],
                ),
              ),
            )),
      ],
    ),
  );
}
