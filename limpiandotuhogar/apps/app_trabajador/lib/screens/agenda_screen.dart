import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/formatters.dart';
import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/request_card.dart';
import '../widgets/screen_header.dart';
import 'main_shell.dart';
import 'request_detail_screen.dart';

enum AgendaFilter {
  todos('Todos'),
  porConfirmar('Por confirmar'),
  confirmados('Confirmados'),
  enCurso('En curso');

  const AgendaFilter(this.label);
  final String label;

  bool matches(ServiceRequest r) => switch (this) {
        AgendaFilter.todos => true,
        AgendaFilter.porConfirmar => r.status == RequestStatus.aceptada,
        AgendaFilter.confirmados => r.status == RequestStatus.confirmada,
        AgendaFilter.enCurso => r.status == RequestStatus.enCurso,
      };
}

/// Agenda de servicios con búsqueda, filtro y franja de días.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final _search = TextEditingController();
  String _query = '';
  AgendaFilter _filter = AgendaFilter.todos;
  DateTime? _day;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesQuery(ServiceRequest r) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return r.cleaningType.toLowerCase().contains(q) ||
        r.client.fullName.toLowerCase().contains(q) ||
        r.space.zone.toLowerCase().contains(q) ||
        r.space.areas.any((a) => a.toLowerCase().contains(q));
  }

  String _groupFor(ServiceRequest r, DateTime now) {
    if (r.status == RequestStatus.enCurso) return 'En curso';
    final diff = Fmt.dayDiff(now, r.scheduledAt);
    if (diff < 0) return 'Pendientes de iniciar';
    if (diff == 0) return 'Para hoy';
    if (diff == 1) return 'Para mañana';
    if (diff < 7) return 'En los próximos días';
    return 'Para la siguiente semana';
  }

  Future<void> _openFilter() async {
    final selected = await showAppSheet<AgendaFilter>(
      context,
      title: 'Filtrar agenda',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: AgendaFilter.values.map((f) {
          final active = f == _filter;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              shadow: false,
              color: active ? AppColors.ice : Colors.white,
              border: active ? AppColors.primary : AppColors.divider,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              onTap: () => Navigator.of(ctx).pop(f),
              child: Row(
                children: [
                  Icon(
                    active
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: active ? AppColors.primaryStrong : AppColors.inkMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(f.label, style: AppText.subtitle)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
    if (selected != null && mounted) setState(() => _filter = selected);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final now = state.now;
    final pad = AppSpacing.screen(context);
    final all = state.agendaRequests;
    final items = all.where((r) {
      if (!_filter.matches(r) || !_matchesQuery(r)) return false;
      final day = _day;
      if (day != null && Fmt.dayDiff(day, r.scheduledAt) != 0) return false;
      return true;
    }).toList();

    // Agrupa conservando el orden cronológico.
    final groups = <String, List<ServiceRequest>>{};
    for (final r in items) {
      groups.putIfAbsent(_groupFor(r, now), () => []).add(r);
    }
    final filtersActive = _filter != AgendaFilter.todos || _day != null || _query.isNotEmpty;

    var index = 0;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
      children: [
        ScreenHeader(
          title: 'Agenda',
          center: true,
          onBack: () => MainShell.of(context)?.goTo(MainShellState.tabHome),
        ),
        const SizedBox(height: 14),
        Container(
          height: 52,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  textInputAction: TextInputAction.search,
                  style: AppText.bodyStrong,
                  decoration: InputDecoration(
                    hintText: 'Buscar servicio, cliente o zona',
                    hintStyle: AppText.body,
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: 'Limpiar búsqueda',
                  icon: const Icon(Icons.close_rounded, color: AppColors.inkMuted),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
              ActionChip(
                avatar: Icon(Icons.tune_rounded,
                    size: 16,
                    color: _filter == AgendaFilter.todos
                        ? AppColors.ink
                        : Colors.white),
                label: Text(_filter == AgendaFilter.todos ? 'Filtrado' : _filter.label),
                labelStyle: AppText.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _filter == AgendaFilter.todos ? AppColors.ink : Colors.white,
                ),
                backgroundColor: _filter == AgendaFilter.todos
                    ? Colors.white
                    : AppColors.primaryStrong,
                side: const BorderSide(color: AppColors.border),
                shape: const StadiumBorder(),
                onPressed: _openFilter,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _DayStrip(
          now: now,
          selected: _day,
          hasJob: (d) => all.any((r) => Fmt.dayDiff(d, r.scheduledAt) == 0),
          onSelect: (d) => setState(() {
            _day = (_day != null && Fmt.dayDiff(_day!, d) == 0) ? null : d;
          }),
        ),
        if (filtersActive)
          Align(
            alignment: Alignment.centerRight,
            child: AppLinkButton(
              label: 'Quitar filtros',
              fontSize: 12,
              onPressed: () {
                _search.clear();
                setState(() {
                  _query = '';
                  _filter = AgendaFilter.todos;
                  _day = null;
                });
              },
            ),
          ),
        const SizedBox(height: 6),
        if (groups.isEmpty)
          EmptyState(
            icon: Icons.event_note_outlined,
            title: filtersActive ? 'Sin resultados' : 'Tu agenda está libre',
            message: filtersActive
                ? 'Prueba con otra búsqueda o quita los filtros.'
                : 'Cuando confirmes un servicio aparecerá aquí.',
            action: filtersActive
                ? null
                : AppButton(
                    label: 'Ver solicitudes',
                    expand: false,
                    onPressed: () =>
                        MainShell.of(context)?.goTo(MainShellState.tabRequests),
                  ),
          ),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10, left: 4),
            child: Row(
              children: [
                Expanded(child: Text(entry.key, style: AppText.heading)),
                Text('${entry.value.length}', style: AppText.caption),
              ],
            ),
          ),
          for (final r in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FadeSlideIn(
                key: ValueKey('agenda-${r.id}'),
                delay: FadeSlideIn.stagger(index++),
                child: RequestCard(
                  request: r,
                  buttonLabel: r.status == RequestStatus.aceptada
                      ? 'Confirmar servicio'
                      : 'Ver servicio',
                  onOpen: () => AppRoutes.push(
                      context, RequestDetailScreen(requestId: r.id)),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.now,
    required this.selected,
    required this.hasJob,
    required this.onSelect,
  });

  final DateTime now;
  final DateTime? selected;
  final bool Function(DateTime) hasJob;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = today.add(Duration(days: i));
          final sel = selected;
          final active = sel != null && Fmt.dayDiff(sel, d) == 0;
          final busy = hasJob(d);
          return GestureDetector(
            onTap: () {
              Haptics.tap(context);
              onSelect(d);
            },
            child: AnimatedContainer(
              duration: AppDurations.medium,
              curve: Curves.easeOutCubic,
              width: 54,
              decoration: BoxDecoration(
                color: active ? AppColors.primaryStrong : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: i == 0 && !active ? AppColors.primary : AppColors.divider),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(i == 0 ? 'Hoy' : Fmt.weekdayShort(d.weekday),
                      style: AppText.caption.copyWith(
                          color: active ? AppColors.ice : AppColors.inkMuted)),
                  Text('${d.day}',
                      style: AppText.heading.copyWith(
                          color: active ? Colors.white : AppColors.ink)),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: AppDurations.medium,
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: busy
                          ? (active ? AppColors.mint : AppColors.lagoon)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
