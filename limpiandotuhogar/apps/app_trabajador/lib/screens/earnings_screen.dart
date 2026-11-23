import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/screen_header.dart';
import '../widgets/wave_background.dart';
import 'request_detail_screen.dart';

enum _Period { semana, mes, total }

/// Ingresos y actividad (montos informativos, sin movimientos reales).
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  _Period _period = _Period.mes;
  int? _selectedBar;

  (DateTime, DateTime) _range(AppState state) {
    final n = state.now;
    switch (_period) {
      case _Period.semana:
        final start = state.weekStart;
        return (start, start.add(const Duration(days: 7)));
      case _Period.mes:
        final start = DateTime(n.year, n.month);
        return (start, DateTime(n.year, n.month + 1));
      case _Period.total:
        return (DateTime(2000), DateTime(n.year + 1));
    }
  }

  (DateTime, DateTime)? _previousRange(AppState state) {
    final (start, _) = _range(state);
    switch (_period) {
      case _Period.semana:
        return (start.subtract(const Duration(days: 7)), start);
      case _Period.mes:
        return (DateTime(start.year, start.month - 1), start);
      case _Period.total:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pad = AppSpacing.screen(context);
    final (start, end) = _range(state);
    final amount = state.earningsBetween(start, end);
    final count = state.completedBetween(start, end);
    final prev = _previousRange(state);
    final prevAmount = prev == null ? null : state.earningsBetween(prev.$1, prev.$2);
    final jobs = state.completedJobs;
    final avg = jobs.isEmpty ? 0.0 : state.totalEarnings / jobs.length;

    // Últimas 6 semanas para la gráfica.
    final weeks = List.generate(6, (i) {
      final s = state.weekStart.subtract(Duration(days: 7 * (5 - i)));
      return (s, state.earningsBetween(s, s.add(const Duration(days: 7))));
    });
    final maxWeek = weeks.fold<double>(0, (m, w) => w.$2 > m ? w.$2 : m);

    String? trend;
    if (prevAmount != null) {
      if (prevAmount == 0) {
        trend = amount > 0 ? 'Primer ingreso del periodo' : null;
      } else {
        final pct = ((amount - prevAmount) / prevAmount * 100).round();
        trend = '${pct >= 0 ? '+' : ''}$pct% vs. periodo anterior';
      }
    }

    return Scaffold(
      body: WaveBackground(
        headerHeight: 240,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
          children: [
            ScreenHeader(
              title: 'Ingresos y actividad',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 14),
            ChoiceChips<_Period>(
              options: _Period.values,
              selected: _period,
              labelOf: (p) => switch (p) {
                _Period.semana => 'Esta semana',
                _Period.mes => 'Este mes',
                _Period.total => 'Total',
              },
              onSelected: (p) => setState(() => _period = p),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(20),
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
                  Text('Ingresos del periodo',
                      style: AppText.bodyStrong.copyWith(color: AppColors.ice)),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: amount),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${Fmt.money(v, decimals: true)} MXN',
                          style: AppText.display.copyWith(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Pill(
                        label: '$count servicio${count == 1 ? '' : 's'}',
                        background: AppColors.fade(Colors.white, 0.18),
                        foreground: Colors.white,
                        icon: Icons.task_alt_rounded,
                      ),
                      if (trend != null)
                        Pill(
                          label: trend,
                          background: AppColors.fade(Colors.white, 0.18),
                          foreground: Colors.white,
                          icon: Icons.trending_up_rounded,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Últimas 6 semanas', style: AppText.heading),
                  Text(
                    _selectedBar == null
                        ? 'Toca una barra para ver el monto.'
                        : 'Semana del ${Fmt.date(weeks[_selectedBar!].$1)}: ${Fmt.money(weeks[_selectedBar!].$2)} MXN',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 150,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(weeks.length, (i) {
                        final value = weeks[i].$2;
                        final ratio = maxWeek == 0 ? 0.0 : value / maxWeek;
                        final selected = _selectedBar == i;
                        final current = i == weeks.length - 1;
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(
                                () => _selectedBar = selected ? null : i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: ratio),
                                    duration:
                                        Duration(milliseconds: 500 + i * 80),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, v, _) => AnimatedContainer(
                                      duration: AppDurations.fast,
                                      height: 6 + v * 104,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.primaryStrong
                                            : current
                                                ? AppColors.lagoon
                                                : AppColors.sky,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${weeks[i].$1.day}/${weeks[i].$1.month}',
                                    style: AppText.caption.copyWith(
                                        fontSize: 10,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w400),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                      icon: Icons.task_alt_rounded,
                      value: '${jobs.length}',
                      label: 'Servicios realizados'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                      icon: Icons.sell_outlined,
                      value: Fmt.money(avg),
                      label: 'Promedio por servicio'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                      icon: Icons.schedule_rounded,
                      value: '${state.totalHoursWorked.round()} h',
                      label: 'Horas trabajadas'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                      icon: Icons.cleaning_services_rounded,
                      value: state.averageRating == 0
                          ? '—'
                          : state.averageRating.toStringAsFixed(1),
                      label: 'Calificación promedio'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Actividad reciente', style: AppText.heading),
            const SizedBox(height: 10),
            if (jobs.isEmpty)
              const EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Sin actividad',
                message: 'Aquí verás tus servicios finalizados.',
              ),
            for (var i = 0; i < jobs.length; i++)
              FadeSlideIn(
                key: ValueKey('earn-${jobs[i].id}'),
                delay: FadeSlideIn.stagger(i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    onTap: () => AppRoutes.push(
                        context, RequestDetailScreen(requestId: jobs[i].id)),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                              color: AppColors.ice, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded,
                              color: AppColors.primaryStrong),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(jobs[i].cleaningType,
                                  style: AppText.bodyStrong),
                              Text(
                                  '${Fmt.date(jobs[i].finishedAt ?? jobs[i].scheduledAt)} · ${jobs[i].client.shortName}',
                                  style: AppText.caption),
                            ],
                          ),
                        ),
                        Text('+${Fmt.money(jobs[i].agreedPrice ?? 0)}',
                            style: AppText.subtitle.copyWith(
                                color: AppColors.successFg,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const NoticeBox(
              message:
                  'Montos informativos calculados con tus servicios finalizados. Esta app no realiza cobros, pagos ni transferencias.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppText.title),
          ),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption),
        ],
      ),
    );
  }
}
