import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/screen_header.dart';
import 'request_detail_screen.dart';

/// Icono y colores por tipo de notificación.
(IconData, Color, Color) notificationStyle(NotificationType t) => switch (t) {
      NotificationType.solicitud =>
        (Icons.inbox_rounded, AppColors.aqua, AppColors.infoFg),
      NotificationType.propuesta =>
        (Icons.sell_outlined, AppColors.periwinkle, AppColors.negotiationFg),
      NotificationType.servicio =>
        (Icons.event_available_rounded, AppColors.mint, AppColors.successFg),
      NotificationType.calificacion =>
        (Icons.cleaning_services_rounded, AppColors.sage, AppColors.progressFg),
      NotificationType.sistema =>
        (Icons.info_outline_rounded, AppColors.mist, AppColors.inkSoft),
    };

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _onlyUnread = false;

  Future<void> _open(AppNotification n) async {
    final state = AppScope.read(context);
    state.markNotificationRead(n.id);
    final request = n.requestId == null ? null : state.byId(n.requestId!);
    final (icon, bg, fg) = notificationStyle(n.type);
    final goToRequest = await showAppDialog<bool>(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Icon(icon, color: fg, size: 28),
              ),
            ),
            const SizedBox(height: 14),
            Text(n.title, textAlign: TextAlign.center, style: AppText.title),
            const SizedBox(height: 4),
            Text(Fmt.ago(n.time, state.now),
                textAlign: TextAlign.center, style: AppText.caption),
            const SizedBox(height: 12),
            Text(n.body, textAlign: TextAlign.center, style: AppText.body),
            const SizedBox(height: 18),
            if (request != null)
              AppButton(
                label: 'Ver solicitud',
                icon: Icons.open_in_new_rounded,
                onPressed: () => Navigator.of(ctx).pop(true),
              )
            else if (n.requestId != null)
              const NoticeBox(
                  message: 'La solicitud relacionada ya no está disponible.'),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
    if (goToRequest == true && request != null && mounted) {
      AppRoutes.push(context, RequestDetailScreen(requestId: request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pad = AppSpacing.screen(context);
    final all = state.notifications;
    final list = _onlyUnread ? all.where((n) => !n.read).toList() : all;
    final unread = list.where((n) => !n.read).toList();
    final read = list.where((n) => n.read).toList();

    Widget tile(AppNotification n, int i) {
      final (icon, bg, fg) = notificationStyle(n.type);
      return FadeSlideIn(
        key: ValueKey('n-${n.id}'),
        delay: FadeSlideIn.stagger(i),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Dismissible(
            key: ValueKey('dismiss-${n.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.errorFg),
            ),
            onDismissed: (_) {
              state.deleteNotification(n.id);
              showToast(context, 'Notificación eliminada.',
                  icon: Icons.delete_outline_rounded);
            },
            child: AppCard(
              onTap: () => _open(n),
              color: n.read ? Colors.white : AppColors.ice,
              shadow: !n.read,
              border: n.read ? AppColors.divider : null,
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: Icon(icon, color: fg, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(n.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.bodyStrong.copyWith(
                                      fontWeight: n.read
                                          ? FontWeight.w500
                                          : FontWeight.w700)),
                            ),
                            AnimatedContainer(
                              duration: AppDurations.medium,
                              width: n.read ? 0 : 9,
                              height: 9,
                              decoration: const BoxDecoration(
                                  color: AppColors.primaryStrong,
                                  shape: BoxShape.circle),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(n.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(Fmt.ago(n.time, state.now), style: AppText.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    var i = 0;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 28),
        children: [
          ScreenHeader(
            title: 'Notificaciones',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ChoiceChips<bool>(
                  options: const [false, true],
                  selected: _onlyUnread,
                  labelOf: (v) => v ? 'No leídas' : 'Todas',
                  countOf: (v) => v ? state.unreadCount : 0,
                  onSelected: (v) => setState(() => _onlyUnread = v),
                ),
              ),
              TextButton(
                onPressed: state.unreadCount == 0
                    ? null
                    : () {
                        state.markAllNotificationsRead();
                        showToast(context, 'Todas marcadas como leídas.');
                      },
                child: const Text('Marcar todo'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Desliza a la izquierda para eliminar.', style: AppText.caption),
          const SizedBox(height: 12),
          if (list.isEmpty)
            EmptyState(
              icon: Icons.notifications_off_outlined,
              title: _onlyUnread ? 'Estás al día' : 'Sin notificaciones',
              message: _onlyUnread
                  ? 'No tienes notificaciones pendientes por leer.'
                  : 'Aquí verás avisos de solicitudes, propuestas y servicios.',
            ),
          if (unread.isNotEmpty) ...[
            const SectionTitle('Nuevas'),
            for (final n in unread) tile(n, i++),
          ],
          if (read.isNotEmpty) ...[
            const SectionTitle('Anteriores'),
            for (final n in read) tile(n, i++),
          ],
        ],
      ),
    );
  }
}
