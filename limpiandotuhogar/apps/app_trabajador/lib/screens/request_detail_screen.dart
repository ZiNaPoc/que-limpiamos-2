import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_request.dart';
import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/client_profile_dialog.dart';
import '../widgets/common.dart';
import '../widgets/mini_map.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/screen_header.dart';
import '../widgets/status_badge.dart';
import '../widgets/wave_background.dart';
import 'chat_screen.dart';
import 'request_actions.dart';

/// Detalle de una solicitud o servicio con carrusel Precio / Espacio /
/// Servicio y acciones según el estado.
class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({
    super.key,
    required this.requestId,
    this.initialPage = 0,
  });

  final String requestId;
  final int initialPage;

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  late final PageController _pages =
      PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goToPage(int i) {
    _pages.animateToPage(i,
        duration: AppDurations.slow, curve: Curves.easeOutCubic);
  }

  void _openChat(AppState state, ServiceRequest r) {
    final check = state.canChat(r);
    if (!check.allowed) {
      showToast(context, check.reason!, icon: Icons.lock_outline_rounded);
      return;
    }
    AppRoutes.push(context, ChatScreen(requestId: r.id));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = state.byId(widget.requestId);
    final pad = AppSpacing.screen(context);

    if (r == null) {
      return Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Solicitud no encontrada',
            message: 'Es posible que se haya restablecido la información.',
            action: AppButton(
              label: 'Regresar',
              expand: false,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      );
    }

    final canChat = state.canChat(r).allowed;
    final unreadFromClient = r.messages.isNotEmpty && !r.messages.last.fromWorker
        ? 1
        : 0;

    return Scaffold(
      body: WaveBackground(
        headerHeight: 190,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: ScreenHeader(
                title: r.cleaningType,
                subtitle:
                    'Solicitud de ${r.client.shortName} · ${Fmt.ago(r.createdAt, state.now)}',
                subtitleStyle: AppText.caption.copyWith(
                    color: AppColors.ink, fontWeight: FontWeight.w500),
                titleStyle: AppText.title.copyWith(fontSize: 24),
                center: true,
                logoSize: 46,
                onBack: () => Navigator.of(context).maybePop(),
                actions: [
                  CircleIconButton(
                    icon: canChat
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.speaker_notes_off_outlined,
                    tooltip: 'Chat con el cliente',
                    badge: canChat ? unreadFromClient : 0,
                    foreground: canChat ? AppColors.ink : AppColors.inkMuted,
                    onPressed: () => _openChat(state, r),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: _StatusProgress(request: r),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: _TabSelector(
                controller: _pages,
                page: _page,
                onTap: _goToPage,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _PageFrame(child: _PricePage(request: r, state: state)),
                  _PageFrame(child: _SpacePage(request: r, state: state)),
                  _PageFrame(child: _ServicePage(request: r, state: state)),
                ],
              ),
            ),
            _Dots(count: 3, index: _page, onTap: _goToPage),
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 6, pad, 10),
              child: _ClientPill(onTap: () => showClientProfile(context, r)),
            ),
            RequestActionPanel(request: r),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Encabezado: progreso, pestañas e indicadores
// ════════════════════════════════════════════════════════════════════

class _StatusProgress extends StatelessWidget {
  const _StatusProgress({required this.request});

  final ServiceRequest request;

  static const _steps = [
    'Oportunidad',
    'Propuesta',
    'Acuerdo',
    'Confirmado',
    'En curso',
    'Finalizado',
  ];

  int get _index => switch (request.status) {
        RequestStatus.disponible => 0,
        RequestStatus.enNegociacion || RequestStatus.pendiente => 1,
        RequestStatus.aceptada => 2,
        RequestStatus.confirmada => 3,
        RequestStatus.enCurso => 4,
        RequestStatus.finalizada => 5,
        RequestStatus.rechazada || RequestStatus.cancelada => -1,
      };

  @override
  Widget build(BuildContext context) {
    final idx = _index;
    if (idx < 0) {
      return Row(
        children: [
          StatusBadge(request: request, dense: false),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              request.statusReason ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppColors.ink),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_steps.length, (i) {
            return Expanded(
              child: AnimatedContainer(
                duration: AppDurations.slow,
                curve: Curves.easeOutCubic,
                margin: EdgeInsets.only(right: i == _steps.length - 1 ? 0 : 4),
                height: 5,
                decoration: BoxDecoration(
                  color: i <= idx
                      ? AppColors.primaryStrong
                      : AppColors.fade(Colors.white, 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: AppDurations.medium,
                child: Text(
                  'Paso ${idx + 1} de ${_steps.length} · ${_steps[idx]}',
                  key: ValueKey(idx),
                  style: AppText.caption.copyWith(
                      color: AppColors.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            StatusBadge(request: request),
          ],
        ),
      ],
    );
  }
}

class _TabSelector extends StatelessWidget {
  const _TabSelector({
    required this.controller,
    required this.page,
    required this.onTap,
  });

  final PageController controller;
  final int page;
  final ValueChanged<int> onTap;

  static const _tabs = [
    (Icons.payments_outlined, 'Precio'),
    (Icons.home_work_outlined, 'Espacio'),
    (Icons.cleaning_services_outlined, 'Servicio'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.soft,
      ),
      child: Stack(
        children: [
          // Indicador que sigue al deslizamiento del carrusel.
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              double current = page.toDouble();
              if (controller.hasClients &&
                  controller.position.haveDimensions &&
                  controller.page != null) {
                current = controller.page!;
              }
              return Align(
                alignment: Alignment(-1 + current, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / _tabs.length,
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primaryStrong,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned.fill(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(_tabs.length, (i) {
              final active = i == page;
              return Expanded(
                child: Semantics(
                  selected: active,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_tabs[i].$1,
                            size: 16,
                            color: active ? Colors.white : AppColors.inkSoft),
                        const SizedBox(width: 6),
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: AppDurations.medium,
                            style: AppText.label.copyWith(
                              color: active ? Colors.white : AppColors.inkSoft,
                            ),
                            child: Text(_tabs[i].$2,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
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
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index, required this.onTap});

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return GestureDetector(
          onTap: () => onTap(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: AnimatedContainer(
              duration: AppDurations.medium,
              width: active ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? AppColors.primaryStrong : AppColors.fog,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ClientPill extends StatelessWidget {
  const _ClientPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryStrong,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              const SizedBox(width: 6),
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded,
                    color: AppColors.primaryStrong, size: 22),
              ),
              Expanded(
                child: Text('Ver perfil del cliente',
                    textAlign: TextAlign.center,
                    style: AppText.button.copyWith(color: Colors.white)),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// Páginas del carrusel
// ════════════════════════════════════════════════════════════════════

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppShadows.soft,
        ),
        child: child,
      ),
    );
  }
}

class _Overline extends StatelessWidget {
  const _Overline(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(text, textAlign: TextAlign.center, style: AppText.overline),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(text, style: AppText.subtitle),
      );
}

/// Caja de texto de solo lectura (estilo de los mockups).
class _FieldBox extends StatelessWidget {
  const _FieldBox(this.text, {this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primary : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        text,
        textAlign: highlight ? TextAlign.center : TextAlign.start,
        style: AppText.bodyStrong
            .copyWith(color: highlight ? Colors.white : AppColors.ink),
      ),
    );
  }
}

String negotiationHint(ServiceRequest r) {
  switch (r.status) {
    case RequestStatus.disponible:
      return 'El precio no lo fija la plataforma. Si te interesa, acepta la oportunidad y después envía tu propuesta.';
    case RequestStatus.enNegociacion:
      return r.clientOffer != null
          ? 'El cliente respondió con una contraoferta. Puedes aceptarla, enviar otra propuesta o rechazar.'
          : 'Aceptaste la oportunidad. Envía tu propuesta económica para continuar.';
    case RequestStatus.pendiente:
      return 'Tu propuesta espera la respuesta del cliente. Puedes editarla mientras siga pendiente.';
    case RequestStatus.aceptada:
      return 'Ya hay acuerdo de precio. Confirma el servicio para agregarlo definitivamente a tu agenda.';
    case RequestStatus.confirmada:
      return 'Servicio confirmado por el precio acordado.';
    case RequestStatus.enCurso:
      return 'Servicio en curso. Al terminar, márcalo como finalizado.';
    case RequestStatus.finalizada:
      return 'Servicio finalizado. El monto se sumó a tus ingresos (informativo).';
    case RequestStatus.rechazada:
    case RequestStatus.cancelada:
      return r.statusReason ?? 'Esta solicitud está cerrada.';
  }
}

class _PricePage extends StatelessWidget {
  const _PricePage({required this.request, required this.state});

  final ServiceRequest request;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final proposal = r.proposal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Overline('DETALLES DEL PRECIO'),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.range(r.estimateMin, r.estimateMax),
                  style: AppText.display.copyWith(fontSize: 40)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('MXN', style: AppText.heading),
              ),
            ],
          ),
        ),
        Text('Precio estimado por el cliente',
            textAlign: TextAlign.center,
            style: AppText.bodyStrong.copyWith(color: AppColors.inkMuted)),
        if (r.extraServicePrice > 0) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.money(r.extraServicePrice),
                  style: AppText.display.copyWith(fontSize: 30)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('MXN', style: AppText.label),
              ),
            ],
          ),
          Text('Servicio extra · ${r.extraService ?? ''}',
              textAlign: TextAlign.center,
              style: AppText.bodyStrong.copyWith(color: AppColors.inkMuted)),
        ],
        const SizedBox(height: 16),
        const Divider(color: AppColors.divider),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
                child: Text('Estado de la negociación',
                    style: AppText.subtitle)),
            StatusBadge(request: r),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: AppDurations.medium,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (proposal != null)
                InfoRow(
                  icon: Icons.sell_outlined,
                  label: 'Tu propuesta (v${proposal.version})',
                  value: '${Fmt.money(proposal.amount)} MXN',
                ),
              if (r.clientOffer != null && r.status == RequestStatus.enNegociacion)
                InfoRow(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Contraoferta del cliente',
                  value: '${Fmt.money(r.clientOffer!)} MXN',
                  valueStyle:
                      AppText.bodyStrong.copyWith(color: AppColors.warningFg),
                ),
              if (r.agreedPrice != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.handshake_outlined,
                          color: AppColors.successFg),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Precio acordado',
                            style: AppText.bodyStrong
                                .copyWith(color: AppColors.successFg)),
                      ),
                      Text('${Fmt.money(r.agreedPrice!)} MXN',
                          style: AppText.heading
                              .copyWith(color: AppColors.successFg)),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(negotiationHint(r), style: AppText.body),
            ],
          ),
        ),
        if (proposal != null) ...[
          const SizedBox(height: 14),
          AppButton(
            label: 'Ver detalles de la propuesta',
            icon: Icons.receipt_long_outlined,
            variant: AppButtonVariant.outline,
            height: 46,
            onPressed: () => showProposalDetails(context, r),
          ),
        ],
      ],
    );
  }
}

/// Modal con el detalle de la propuesta vigente.
Future<void> showProposalDetails(BuildContext context, ServiceRequest r) {
  final p = r.proposal;
  if (p == null) return Future.value();
  final now = AppScope.read(context).now;
  return showAppDialog<void>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Tu propuesta', style: AppText.title)),
              StatusBadge(request: r),
            ],
          ),
          const SizedBox(height: 12),
          Text('${Fmt.money(p.amount)} MXN',
              style: AppText.display.copyWith(fontSize: 34)),
          const SizedBox(height: 8),
          InfoRow(label: 'Versión', value: 'v${p.version}'),
          InfoRow(label: 'Enviada', value: Fmt.ago(p.sentAt, now)),
          InfoRow(
              label: 'Estimado del cliente',
              value: '${Fmt.range(r.estimateMin, r.estimateMax)} MXN'),
          if (r.clientOffer != null)
            InfoRow(
                label: 'Contraoferta',
                value: '${Fmt.money(r.clientOffer!)} MXN'),
          if (r.agreedPrice != null)
            InfoRow(
                label: 'Precio acordado',
                value: '${Fmt.money(r.agreedPrice!)} MXN'),
          const SizedBox(height: 8),
          Text('Nota', style: AppText.label),
          const SizedBox(height: 4),
          Text(p.note.isEmpty ? 'Sin nota.' : p.note, style: AppText.body),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    ),
  );
}

class _SpacePage extends StatelessWidget {
  const _SpacePage({required this.request, required this.state});

  final ServiceRequest request;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = request.space;
    final exact = state.showsExactAddress(request);
    final office = s.type == PropertyType.oficina;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Overline('DETALLES DEL ESPACIO'),
        Text('Tipo de inmueble', style: AppText.subtitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PropertyType.values.map((t) {
            final selected = t == s.type;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryStrong : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                    color: selected ? AppColors.primaryStrong : AppColors.divider),
              ),
              child: Text(
                t.label,
                style: AppText.label.copyWith(
                    color: selected ? Colors.white : AppColors.inkMuted),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        CounterRow(
            label: office ? 'Número de privados' : 'Número de habitaciones',
            value: '${s.rooms}'),
        CounterRow(label: 'Número de baños completos', value: '${s.fullBaths}'),
        CounterRow(label: 'Número de medios baños', value: '${s.halfBaths}'),
        CounterRow(label: 'Número de pisos o niveles', value: '${s.floors}'),
        CounterRow(label: 'Superficie aproximada', value: '${s.approxM2} m²'),
        const _Label('Áreas a limpiar'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: s.areas.map((a) => Pill(label: a)).toList(),
        ),
        _Label('Fotografías del cliente (${s.photos.length})'),
        PhotoStrip(photos: s.photos),
        const SizedBox(height: 4),
        Text('Toca una foto para verla completa.', style: AppText.caption),
        if (s.notes.isNotEmpty) ...[
          const _Label('Información del cliente'),
          NoticeBox(icon: Icons.sticky_note_2_outlined, message: s.notes),
        ],
        const _Label('Ubicación'),
        MiniMap(exact: exact, seed: request.id.hashCode),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(exact ? Icons.location_on_outlined : Icons.lock_outline_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(exact ? s.address : s.zone, style: AppText.bodyStrong),
                  Text(
                    exact
                        ? 'A ${s.distanceKm.toStringAsFixed(1)} km de tu zona.'
                        : 'Zona aproximada · ${s.distanceKm.toStringAsFixed(1)} km. La dirección exacta se muestra al confirmar el servicio.',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            if (exact)
              IconButton(
                tooltip: 'Copiar dirección',
                icon: const Icon(Icons.copy_rounded, color: AppColors.primaryStrong),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: s.address));
                  if (context.mounted) {
                    showToast(context, 'Dirección copiada.');
                  }
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _ServicePage extends StatelessWidget {
  const _ServicePage({required this.request, required this.state});

  final ServiceRequest request;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final d = r.scheduledAt;
    final within = state.isWithinSchedule(r);
    final conflict = (r.status == RequestStatus.disponible || r.status.isNegotiating)
        ? state.conflictFor(r)
        : null;

    Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadows.soft,
          ),
          child: Text(text, style: AppText.label),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Overline('DETALLES DEL SERVICIO'),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(Fmt.weekdayShort(d.weekday)),
            chip('${d.day} ${Fmt.monthShort(d)}'),
            chip('${d.year}'),
            chip(Fmt.time(d)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${Fmt.relativeDay(d, state.now)} · ${r.durationHours} h estimadas · termina ${Fmt.time(r.endsAt)}',
          textAlign: TextAlign.center,
          style: AppText.caption,
        ),
        const SizedBox(height: 8),
        Center(
          child: Pill(
            label: within ? 'Dentro de tu horario' : 'Fuera de tu horario',
            icon: within ? Icons.check_circle_outline : Icons.schedule_rounded,
            background: within ? AppColors.successBg : AppColors.warningBg,
            foreground: within ? AppColors.successFg : AppColors.warningFg,
          ),
        ),
        if (conflict != null) ...[
          const SizedBox(height: 10),
          NoticeBox.warning(
            message:
                'Se empalma con «${conflict.cleaningType}» (${Fmt.dateTime(conflict.scheduledAt)}). No podrás confirmar ambos.',
          ),
        ],
        const _Label('Tipo de limpieza'),
        _FieldBox(r.cleaningType, highlight: true),
        const _Label('Descripción'),
        _FieldBox(r.description),
        const _Label('Servicio extra'),
        _FieldBox(r.extraService == null
            ? 'Ninguno'
            : '${r.extraService} · +${Fmt.money(r.extraServicePrice)} MXN'),
        const _Label('Detalles extra'),
        _FieldBox(r.extraDetails.isEmpty ? 'Sin detalles adicionales' : r.extraDetails),
        if (r.conditions.isNotEmpty) ...[
          const _Label('Condiciones'),
          ...r.conditions.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: AppColors.lagoon),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c, style: AppText.body)),
                  ],
                ),
              )),
        ],
      ],
    );
  }
}
