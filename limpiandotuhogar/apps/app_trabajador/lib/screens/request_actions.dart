import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/service_request.dart';
import '../navigation/app_routes.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/formatters.dart';
import '../services/haptics.dart';
import '../services/resenas_reportes_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/proposal_sheet.dart';
import 'rate_client_screen.dart';

/// Acciones de una solicitud. Se comparten entre el detalle y el chat para
/// que las reglas de negocio sean las mismas en toda la app.
class RequestActions {
  RequestActions._();

  static void _done(BuildContext context, String message,
      {IconData icon = Icons.check_circle_rounded}) {
    Haptics.success(context);
    showToast(context, message, icon: icon);
  }

  static void _fail(BuildContext context, String? error) {
    if (error != null) showToast(context, error, error: true);
  }

  /// Aceptar una solicitud: se avisa al servidor y, si nadie más la tomó,
  /// queda confirmada en la agenda.
  static Future<void> accept(BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final check = state.canAccept(r);
    if (!check.allowed) return _fail(context, check.reason);

    final warnings = <String>[
      if (!state.isWithinSchedule(r)) 'El servicio está fuera de tu horario.',
      if (state.conflictFor(r) != null)
        'Se empalma con otro servicio confirmado.',
    ];
    final ok = await confirmAction(
      context,
      title: 'Aceptar solicitud',
      message:
          '${warnings.isEmpty ? '' : '${warnings.join(' ')}\n\n'}Al aceptar, el servicio queda confirmado en tu agenda por ${Fmt.money(r.estimateMin)} MXN.',
      confirmLabel: 'Aceptar solicitud',
      icon: Icons.handshake_outlined,
    );
    if (!ok || !context.mounted) return;
    final error = await state.acceptOpportunity(r.id);
    if (!context.mounted) return;
    if (error != null) return _fail(context, error);
    _done(context, 'Solicitud aceptada. Quedó confirmada en tu agenda.');
  }

  static Future<void> reject(BuildContext context, ServiceRequest r,
      {bool popAfter = true}) async {
    final state = AppScope.read(context);
    final reason = await pickReason(
      context,
      title: 'Rechazar solicitud',
      description:
          'La solicitud dejará de aparecer en tus oportunidades. Cuéntanos el motivo.',
      reasons: const [
        'No estoy disponible en ese horario',
        'Está fuera de mi zona de trabajo',
        'No es una de mis especialidades',
        'El presupuesto no me conviene',
      ],
      confirmLabel: 'Rechazar solicitud',
    );
    if (reason == null || !context.mounted) return;
    if (state.isRemote(r)) {
      // Solicitud real: el rechazo va al servidor (si era invitación, avisa al cliente).
      final error = await state.rejectRemote(r.id);
      if (!context.mounted) return;
      if (error != null) return _fail(context, error);
    } else {
      state.rejectRequest(r.id, reason.toLowerCase());
    }
    _done(context, 'Solicitud rechazada.', icon: Icons.close_rounded);
    if (popAfter) Navigator.of(context).maybePop();
  }

  static Future<void> withdraw(BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final ok = await confirmAction(
      context,
      title: 'Retirar propuesta',
      message:
          'La solicitud se marcará como rechazada y ya no podrás negociarla.',
      confirmLabel: 'Retirar',
      destructive: true,
      icon: Icons.undo_rounded,
    );
    if (!ok || !context.mounted) return;
    state.rejectRequest(r.id, 'retiré mi propuesta');
    _done(context, 'Propuesta retirada.', icon: Icons.undo_rounded);
  }

  static Future<void> propose(BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final check = state.canPropose(r);
    if (!check.allowed) return _fail(context, check.reason);
    final editing = r.status == RequestStatus.pendiente;
    final result = await showProposalSheet(context, r);
    if (result == null || !context.mounted) return;
    final error = state.sendProposal(r.id, result.amount, result.note);
    if (error != null) return _fail(context, error);
    _done(
        context,
        editing
            ? 'Propuesta actualizada a ${Fmt.money(result.amount)}.'
            : 'Propuesta de ${Fmt.money(result.amount)} enviada. Queda pendiente de respuesta.',
        icon: Icons.send_rounded);
  }

  static Future<void> acceptCounterOffer(
      BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final offer = r.clientOffer;
    if (offer == null) return;
    final ok = await confirmAction(
      context,
      title: 'Aceptar contraoferta',
      message:
          'Aceptarás ${Fmt.money(offer)} MXN como precio del servicio. Después deberás confirmar el servicio.',
      confirmLabel: 'Aceptar ${Fmt.money(offer)}',
      icon: Icons.swap_horiz_rounded,
    );
    if (!ok || !context.mounted) return;
    final error = state.acceptCounterOffer(r.id);
    if (error != null) return _fail(context, error);
    _done(context, 'Hay acuerdo de precio. Ahora confirma el servicio.');
  }

  static Future<void> simulateResponse(
      BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final response = await showAppSheet<SimulatedResponse>(
      context,
      title: 'Simular respuesta del cliente',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const NoticeBox(
            icon: Icons.science_outlined,
            message:
                'Modo demostración: no existe conexión con la app de clientes. Esta opción solo cambia los datos en este dispositivo para probar el flujo.',
          ),
          const SizedBox(height: 14),
          _OptionTile(
            icon: Icons.thumb_up_alt_outlined,
            title: 'El cliente acepta la propuesta',
            subtitle: 'Pasa a «Aceptada»: faltará tu confirmación.',
            onTap: () => Navigator.of(ctx).pop(SimulatedResponse.acepta),
          ),
          _OptionTile(
            icon: Icons.swap_horiz_rounded,
            title: 'El cliente hace una contraoferta',
            subtitle: 'Vuelve a «En negociación» con un nuevo monto.',
            onTap: () => Navigator.of(ctx).pop(SimulatedResponse.contraoferta),
          ),
          _OptionTile(
            icon: Icons.thumb_down_alt_outlined,
            title: 'El cliente rechaza la propuesta',
            subtitle: 'La solicitud pasa a «Rechazada».',
            onTap: () => Navigator.of(ctx).pop(SimulatedResponse.rechaza),
          ),
        ],
      ),
    );
    if (response == null || !context.mounted) return;
    state.simulateClientResponse(r.id, response);
    _done(context, 'Respuesta simulada aplicada.', icon: Icons.science_outlined);
  }

  static Future<void> confirm(BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final check = state.canConfirm(r);
    if (!check.allowed) return _fail(context, check.reason);
    final ok = await confirmAction(
      context,
      title: 'Confirmar servicio',
      message:
          'Te comprometes a realizar «${r.cleaningType}» el ${Fmt.longDate(r.scheduledAt)} a las ${Fmt.time(r.scheduledAt)} por ${Fmt.money(r.agreedPrice ?? 0)} MXN. Se agregará a tu agenda.',
      confirmLabel: 'Confirmar servicio',
      icon: Icons.event_available_rounded,
    );
    if (!ok || !context.mounted) return;
    final error = state.confirmService(r.id);
    if (error != null) return _fail(context, error);
    _done(context, 'Servicio confirmado y agregado a tu agenda.',
        icon: Icons.event_available_rounded);
  }

  static Future<void> cancel(BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final check = state.canCancel(r);
    if (!check.allowed) return _fail(context, check.reason);
    final reason = await pickReason(
      context,
      title: 'Cancelar servicio',
      description:
          'Cancelar afecta tu confiabilidad. Elige el motivo de la cancelación.',
      reasons: const [
        'Tuve un imprevisto',
        'Me empalmé con otro servicio',
        'El cliente pidió cancelar',
      ],
      confirmLabel: 'Cancelar servicio',
    );
    if (reason == null || !context.mounted) return;
    final error = state.isRemote(r) ? await state.cancelRemote(r.id, reason) : state.cancelService(r.id, reason.toLowerCase());
    if (!context.mounted) return;
    if (error != null) return _fail(context, error);
    _done(context, 'Servicio cancelado.', icon: Icons.event_busy_rounded);
  }

  static Future<void> start(BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final check = state.canStart(r);
    if (!check.allowed) return _fail(context, check.reason);
    final ok = await confirmAction(
      context,
      title: 'Iniciar servicio',
      message: 'Marca el inicio cuando llegues con el cliente.',
      confirmLabel: 'Iniciar ahora',
      icon: Icons.play_circle_outline_rounded,
    );
    if (!ok || !context.mounted) return;
    final error = state.isRemote(r) ? await state.startRemote(r.id) : state.startJob(r.id);
    if (!context.mounted) return;
    if (error != null) return _fail(context, error);
    _done(context, 'Servicio en curso. ¡Éxito!', icon: Icons.timelapse_rounded);
  }

  static Future<void> finish(BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final check = state.canFinish(r);
    if (!check.allowed) return _fail(context, check.reason);
    if (state.isRemote(r)) return _finishRemote(context, r);
    final ok = await confirmAction(
      context,
      title: 'Finalizar servicio',
      message:
          'Confirma que terminaste «${r.cleaningType}». Pasará a tu historial.',
      confirmLabel: 'Finalizar servicio',
      icon: Icons.task_alt_rounded,
    );
    if (!ok || !context.mounted) return;
    final error = state.finishJob(r.id);
    if (error != null) return _fail(context, error);
    Haptics.success(context);
    final rateNow = await confirmAction(
      context,
      title: '¡Servicio finalizado!',
      message:
          'Se agregó a tu historial por ${Fmt.money(r.agreedPrice ?? 0)} MXN. ¿Quieres calificar al cliente ahora?',
      confirmLabel: 'Calificar ahora',
      cancelLabel: 'Más tarde',
      icon: Icons.cleaning_services_rounded,
    );
    if (rateNow && context.mounted) {
      AppRoutes.push(context, RateClientScreen(requestId: r.id));
    }
  }

  /// Solicitud real: «Marcar terminado» exige de 1 a 5 fotos del trabajo (D54). Después el cliente
  /// confirma o, si no responde, el sistema lo confirma con tu evidencia.
  static Future<void> _finishRemote(BuildContext context, ServiceRequest r) async {
    final state = AppScope.read(context);
    final ok = await confirmAction(
      context,
      title: 'Marcar terminado',
      message: 'Sube de 1 a 5 fotos del trabajo terminado. El cliente las verá para confirmar el servicio.',
      confirmLabel: 'Elegir fotos',
      icon: Icons.photo_library_outlined,
    );
    if (!ok || !context.mounted) return;
    List<XFile> elegidas;
    try {
      elegidas = await ImagePicker().pickMultiImage(limit: ReportesApi.maxFotos, imageQuality: 85, maxWidth: 2000);
    } catch (_) {
      if (context.mounted) _fail(context, 'No se pudieron abrir tus fotos.');
      return;
    }
    if (!context.mounted || elegidas.isEmpty) return;
    if (elegidas.length > ReportesApi.maxFotos) return _fail(context, 'Elige como máximo ${ReportesApi.maxFotos} fotos.');
    final fotos = <FotoDeReporte>[for (final f in elegidas) (nombre: f.name, bytes: await f.readAsBytes())];
    if (!context.mounted) return;
    final error = await state.finishRemote(r.id, fotos);
    if (!context.mounted) return;
    if (error != null) return _fail(context, error);
    _done(context, 'Marcaste el servicio como terminado. Falta la confirmación del cliente.', icon: Icons.task_alt_rounded);
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        shadow: false,
        border: AppColors.divider,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryStrong),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong),
                  Text(subtitle, style: AppText.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel inferior con las acciones disponibles según el estado.
class RequestActionPanel extends StatelessWidget {
  const RequestActionPanel({super.key, required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = request;
    final key = ValueKey('${r.status.name}-${r.clientOffer}-${r.clientRatingGiven}');

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          AppSpacing.screen(context), 14, AppSpacing.screen(context), 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [
          BoxShadow(
            color: AppColors.fade(AppColors.primaryStrong, 0.10),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AnimatedSize(
          duration: AppDurations.medium,
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: AppDurations.medium,
            child: KeyedSubtree(key: key, child: _content(context, state, r)),
          ),
        ),
      ),
    );
  }

  Widget _secondary(String label, VoidCallback onTap, {Color? color}) =>
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color ?? AppColors.ink,
          minimumSize: const Size(0, 40),
        ),
        child: Text(label,
            style: AppText.label
                .copyWith(color: color ?? AppColors.ink, fontWeight: FontWeight.w700)),
      );

  Widget _reason(String? text) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.warningFg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text,
                    style: AppText.caption.copyWith(color: AppColors.warningFg)),
              ),
            ],
          ),
        );

  Widget _summary(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppText.body)),
            Text(value,
                style: AppText.heading.copyWith(color: color ?? AppColors.ink)),
          ],
        ),
      );

  Widget _content(BuildContext context, AppState state, ServiceRequest r) {
    switch (r.status) {
      case RequestStatus.disponible:
        final check = state.canAccept(r);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _reason(check.reason),
            AppButton(
              label: 'Aceptar solicitud',
              variant: AppButtonVariant.soft,
              onPressed: check.allowed
                  ? () => RequestActions.accept(context, r)
                  : null,
            ),
            _secondary('Rechazar', () => RequestActions.reject(context, r)),
          ],
        );

      case RequestStatus.enNegociacion:
        final offer = r.clientOffer;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (offer != null) ...[
              _summary('Contraoferta del cliente', '${Fmt.money(offer)} MXN',
                  color: AppColors.warningFg),
              AppButton(
                label: 'Aceptar contraoferta',
                icon: Icons.check_rounded,
                onPressed: () => RequestActions.acceptCounterOffer(context, r),
              ),
              Row(
                children: [
                  Expanded(
                    child: _secondary('Nueva propuesta',
                        () => RequestActions.propose(context, r),
                        color: AppColors.primaryStrong),
                  ),
                  Expanded(
                    child: _secondary(
                        'Rechazar',
                        () => RequestActions.reject(context, r,
                            popAfter: false),
                        color: AppColors.errorFg),
                  ),
                ],
              ),
            ] else ...[
              AppButton(
                label: 'Enviar propuesta',
                icon: Icons.sell_outlined,
                onPressed: () => RequestActions.propose(context, r),
              ),
              _secondary(
                  'Rechazar', () => RequestActions.reject(context, r, popAfter: false),
                  color: AppColors.errorFg),
            ],
          ],
        );

      case RequestStatus.pendiente:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summary(
                'Esperando respuesta · v${r.proposal?.version ?? 1}',
                '${Fmt.money(r.proposal?.amount ?? 0)} MXN'),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Editar propuesta',
                    icon: Icons.edit_outlined,
                    variant: AppButtonVariant.outline,
                    height: 48,
                    onPressed: () => RequestActions.propose(context, r),
                  ),
                ),
                const SizedBox(width: 8),
                _secondary('Retirar', () => RequestActions.withdraw(context, r),
                    color: AppColors.errorFg),
              ],
            ),
            AppLinkButton(
              label: 'Simular respuesta del cliente (demo)',
              fontSize: 12,
              color: AppColors.inkSoft,
              onPressed: () => RequestActions.simulateResponse(context, r),
            ),
          ],
        );

      case RequestStatus.aceptada:
        final check = state.canConfirm(r);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summary('Precio acordado', '${Fmt.money(r.agreedPrice ?? 0)} MXN',
                color: AppColors.successFg),
            _reason(check.reason),
            AppButton(
              label: 'Confirmar servicio',
              icon: Icons.event_available_rounded,
              onPressed:
                  check.allowed ? () => RequestActions.confirm(context, r) : null,
            ),
            _secondary('Cancelar', () => RequestActions.cancel(context, r),
                color: AppColors.errorFg),
          ],
        );

      case RequestStatus.confirmada:
        final check = state.canStart(r);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _reason(check.reason),
            AppButton(
              label: 'Iniciar servicio',
              icon: Icons.play_arrow_rounded,
              onPressed:
                  check.allowed ? () => RequestActions.start(context, r) : null,
            ),
            _secondary('Cancelar servicio', () => RequestActions.cancel(context, r),
                color: AppColors.errorFg),
          ],
        );

      case RequestStatus.enCurso:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.timelapse_rounded, color: AppColors.progressFg),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Tiempo transcurrido', style: AppText.body)),
                  ElapsedClock(since: r.startedAt ?? state.now),
                ],
              ),
            ),
            AppButton(
              label: 'Finalizar servicio',
              icon: Icons.task_alt_rounded,
              onPressed: () => RequestActions.finish(context, r),
            ),
            const SizedBox(height: 8),
          ],
        );

      case RequestStatus.finalizada:
        final rated = r.clientRatingGiven != null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summary('Total del servicio', '${Fmt.money(r.agreedPrice ?? 0)} MXN'),
            AppButton(
              label: rated ? 'Ver calificación' : 'Calificar cliente',
              icon: Icons.cleaning_services_rounded,
              variant: rated ? AppButtonVariant.outline : AppButtonVariant.primary,
              onPressed: () => rated
                  ? showRatingDetails(context, r)
                  : AppRoutes.push(context, RateClientScreen(requestId: r.id)),
            ),
            const SizedBox(height: 8),
          ],
        );

      case RequestStatus.rechazada:
      case RequestStatus.cancelada:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            r.takenByOther
                ? NoticeBox(
                    icon: Icons.block_rounded,
                    message: r.statusReason ?? 'Esta solicitud ya no está disponible.')
                : NoticeBox.error(
                    message: r.statusReason ?? 'Esta solicitud está cerrada.'),
            const SizedBox(height: 10),
            AppButton(
              label: 'Volver',
              variant: AppButtonVariant.outline,
              height: 46,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(height: 8),
          ],
        );
    }
  }
}

/// Reloj que muestra el tiempo transcurrido desde [since].
class ElapsedClock extends StatefulWidget {
  const ElapsedClock({super.key, required this.since});

  final DateTime since;

  @override
  State<ElapsedClock> createState() => _ElapsedClockState();
}

class _ElapsedClockState extends State<ElapsedClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var elapsed = DateTime.now().difference(widget.since);
    if (elapsed.isNegative) elapsed = Duration.zero;
    return Text(Fmt.clock(elapsed),
        style: AppText.heading.copyWith(
            color: AppColors.progressFg,
            fontFeatures: const [FontFeature.tabularFigures()]));
  }
}