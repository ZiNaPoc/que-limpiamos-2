import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/preferences_sheet.dart';
import '../widgets/request_card.dart';
import '../widgets/screen_header.dart';
import 'main_shell.dart';
import 'request_detail_screen.dart';

/// Solicitudes disponibles y en negociación, con filtros.
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  static const _labels = {
    RequestFilter.todas: 'Todas',
    RequestFilter.nuevas: 'Nuevas',
    RequestFilter.porAcordar: 'Por acordar',
  };

  List<ServiceRequest> _itemsFor(AppState state, RequestFilter filter) {
    switch (filter) {
      case RequestFilter.nuevas:
        return state.availableRequests;
      case RequestFilter.porAcordar:
        final list = state.negotiatingRequests;
        final action = state.needsAction.toSet();
        list.sort((a, b) {
          final pa = action.contains(a) ? 0 : 1;
          final pb = action.contains(b) ? 0 : 1;
          return pa != pb ? pa - pb : a.scheduledAt.compareTo(b.scheduledAt);
        });
        return list;
      case RequestFilter.todas:
        final action = state.needsAction;
        return [
          ...action,
          ...state.availableRequests,
          ...state.negotiatingRequests.where((r) => !action.contains(r)),
          ...state.unavailableRequests,
        ];
    }
  }

  int _countFor(AppState state, RequestFilter filter) => switch (filter) {
        RequestFilter.todas =>
          state.availableRequests.length + state.negotiatingRequests.length,
        RequestFilter.nuevas => state.availableRequests.length,
        RequestFilter.porAcordar => state.negotiatingRequests.length,
      };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final shell = MainShell.of(context);
    final pad = AppSpacing.screen(context);
    final filterNotifier = shell?.requestFilter;

    if (filterNotifier == null) return const SizedBox.shrink();

    return ValueListenableBuilder<RequestFilter>(
      valueListenable: filterNotifier,
      builder: (context, filter, _) {
        final items = _itemsFor(state, filter);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ScreenHeader(
                    title: 'Solicitudes',
                    subtitle: 'Tú decides cuáles aceptar.',
                    onBack: () => shell?.goTo(MainShellState.tabHome),
                    center: true,
                    actions: [
                      CircleIconButton(
                        icon: Icons.tune_rounded,
                        tooltip: 'Preferencias de solicitudes',
                        badge: state.hiddenByPreferences,
                        onPressed: () => showPreferencesSheet(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ChoiceChips<RequestFilter>(
                    options: RequestFilter.values,
                    selected: filter,
                    labelOf: (f) => _labels[f]!,
                    countOf: (f) => _countFor(state, f),
                    onSelected: (f) => filterNotifier.value = f,
                  ),
                  const SizedBox(height: 14),
                  if (!state.isOnline)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NoticeBox.warning(
                        message:
                            'Tu disponibilidad está desactivada. Puedes revisar solicitudes, pero no aceptarlas.',
                        action: Align(
                          alignment: Alignment.centerLeft,
                          child: AppLinkButton(
                            label: 'Activar disponibilidad',
                            onPressed: () {
                              state.setOnline(true);
                              showToast(context, 'Disponibilidad activada.');
                            },
                          ),
                        ),
                      ),
                    ),
                  if (state.hiddenByPreferences > 0 &&
                      filter != RequestFilter.porAcordar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: NoticeBox(
                        icon: Icons.filter_alt_outlined,
                        message:
                            '${state.hiddenByPreferences} solicitud(es) ocultas por tu distancia máxima u horario.',
                        action: Align(
                          alignment: Alignment.centerLeft,
                          child: AppLinkButton(
                            label: 'Ajustar preferencias',
                            onPressed: () => showPreferencesSheet(context),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
              sliver: SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: AppDurations.medium,
                  switchInCurve: Curves.easeOut,
                  child: items.isEmpty
                      ? EmptyState(
                          key: ValueKey('empty-$filter'),
                          icon: filter == RequestFilter.porAcordar
                              ? Icons.forum_outlined
                              : Icons.inbox_outlined,
                          title: filter == RequestFilter.porAcordar
                              ? 'Nada por acordar'
                              : 'No hay solicitudes nuevas',
                          message: filter == RequestFilter.porAcordar
                              ? 'Cuando aceptes una oportunidad aparecerá aquí mientras acuerdan el precio.'
                              : 'Te avisaremos cuando un cliente publique una solicitud cerca de ti.',
                        )
                      : Column(
                          key: ValueKey(filter),
                          children: [
                            for (var i = 0; i < items.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: FadeSlideIn(
                                  key: ValueKey('${filter.name}-${items[i].id}'),
                                  delay: FadeSlideIn.stagger(i),
                                  child: RequestCard(
                                    request: items[i],
                                    onOpen: () => AppRoutes.push(
                                      context,
                                      RequestDetailScreen(
                                          requestId: items[i].id),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
