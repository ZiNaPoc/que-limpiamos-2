import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/screen_header.dart';
import '../widgets/status_badge.dart';
import 'earnings_screen.dart';
import 'main_shell.dart';
import 'rate_client_screen.dart';
import 'request_detail_screen.dart';

enum _HistoryTab { realizados, noConcretados }

/// Historial de trabajos realizados y solicitudes no concretadas.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _HistoryTab _tab = _HistoryTab.realizados;

  void _open(ServiceRequest r) =>
      AppRoutes.push(context, RequestDetailScreen(requestId: r.id));

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pad = AppSpacing.screen(context);
    final done = state.completedJobs;
    final closed = state.closedRequests;
    final latest = done.isEmpty ? null : done.first;
    final past = done.length > 1 ? done.sublist(1) : <ServiceRequest>[];

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
      children: [
        ScreenHeader(
          title: 'Historial',
          onBack: () => MainShell.of(context)?.goTo(MainShellState.tabHome),
        ),
        const SizedBox(height: 12),
        AppCard(
          color: AppColors.ice,
          shadow: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          onTap: () => AppRoutes.push(context, const EarningsScreen()),
          child: Row(
            children: [
              const Icon(Icons.insights_rounded, color: AppColors.primaryStrong),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${done.length} servicios · ${Fmt.money(state.totalEarnings)} MXN',
                  style: AppText.bodyStrong,
                ),
              ),
              Text('Ver ingresos',
                  style: AppText.label.copyWith(color: AppColors.primaryStrong)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ChoiceChips<_HistoryTab>(
          options: _HistoryTab.values,
          selected: _tab,
          labelOf: (t) =>
              t == _HistoryTab.realizados ? 'Realizados' : 'No concretados',
          countOf: (t) =>
              t == _HistoryTab.realizados ? done.length : closed.length,
          onSelected: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: AppDurations.medium,
          child: _tab == _HistoryTab.realizados
              ? Column(
                  key: const ValueKey('done'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (latest == null)
                      const EmptyState(
                        icon: Icons.history_rounded,
                        title: 'Aún no hay trabajos realizados',
                        message:
                            'Cuando finalices un servicio aparecerá en tu historial.',
                      )
                    else
                      FadeSlideIn(
                        child: _LatestJobCard(
                            request: latest, onTap: () => _open(latest)),
                      ),
                    if (past.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Pasadas', style: AppText.heading),
                      const SizedBox(height: 10),
                      for (var i = 0; i < past.length; i++)
                        FadeSlideIn(
                          key: ValueKey('past-${past[i].id}'),
                          delay: FadeSlideIn.stagger(i),
                          child: _PastJobTile(
                            request: past[i],
                            onTap: () => _open(past[i]),
                          ),
                        ),
                    ],
                  ],
                )
              : Column(
                  key: const ValueKey('closed'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (closed.isEmpty)
                      const EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'Nada por aquí',
                        message:
                            'Las solicitudes rechazadas o canceladas aparecerán en esta sección.',
                      ),
                    for (final r in closed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          shadow: false,
                          border: AppColors.divider,
                          onTap: () => _open(r),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                      child: Text(r.cleaningType,
                                          style: AppText.heading)),
                                  StatusBadge(request: r),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(Fmt.dateTime(r.scheduledAt),
                                  style: AppText.caption),
                              const SizedBox(height: 4),
                              Text(r.statusReason ?? '', style: AppText.body),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LatestJobCard extends StatelessWidget {
  const _LatestJobCard({required this.request, required this.onTap});

  final ServiceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final start = r.startedAt ?? r.scheduledAt;
    final end = r.finishedAt ?? r.endsAt;
    return AppCard(
      color: AppColors.primaryStrong,
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 92,
                height: 92,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: AppImage(path: r.space.photos.first, cacheWidth: 300),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trabajo realizado',
                        style: AppText.heading.copyWith(color: Colors.white)),
                    const SizedBox(height: 6),
                    Text('Horario: ${Fmt.time(start)} – ${Fmt.time(end)}',
                        style: AppText.bodyStrong.copyWith(color: AppColors.ice)),
                    Text(r.client.shortName,
                        style: AppText.caption.copyWith(color: AppColors.frost)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Servicio: ${r.cleaningType}', style: AppText.bodyStrong),
                Text('Fecha: ${Fmt.date(r.scheduledAt)}', style: AppText.bodyStrong),
                Text('Precio: ${Fmt.money(r.agreedPrice ?? 0)} MXN',
                    style: AppText.bodyStrong),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastJobTile extends StatelessWidget {
  const _PastJobTile({required this.request, required this.onTap});

  final ServiceRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final rated = r.clientRatingGiven != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        onTap: onTap,
        radius: AppRadius.xl,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 54,
                height: 54,
                child: AppImage(path: r.space.photos.first, cacheWidth: 200),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.cleaningType,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    '${Fmt.date(r.scheduledAt)}   ${Fmt.time(r.scheduledAt)}   ${Fmt.money(r.agreedPrice ?? 0)}',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => rated
                  ? showRatingDetails(context, r)
                  : AppRoutes.push(context, RateClientScreen(requestId: r.id)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryStrong,
                backgroundColor: rated ? Colors.white : AppColors.ice,
                side: const BorderSide(color: AppColors.primary),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                textStyle: AppText.caption.copyWith(fontWeight: FontWeight.w700),
              ),
              child: Text(rated ? 'Ver calificación' : 'Calificar'),
            ),
          ],
        ),
      ),
    );
  }
}
