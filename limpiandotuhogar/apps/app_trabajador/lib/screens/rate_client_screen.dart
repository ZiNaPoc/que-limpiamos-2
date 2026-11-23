import 'package:flutter/material.dart';

import '../models/service_request.dart';
import '../services/app_scope.dart';
import '../services/formatters.dart';
import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_modals.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';

/// Calificación del cliente después de un servicio finalizado.
class RateClientScreen extends StatefulWidget {
  const RateClientScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<RateClientScreen> createState() => _RateClientScreenState();
}

class _RateClientScreenState extends State<RateClientScreen> {
  static const _labels = ['Mala', 'Regular', 'Buena', 'Muy buena', 'Excelente'];
  static const _tags = [
    'Puntual',
    'Amable',
    'Espacio listo',
    'Instrucciones claras',
    'Buen trato',
    'Pago acordado sin cambios',
  ];

  int _stars = 0;
  final Set<String> _selectedTags = {};
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send(ServiceRequest r) async {
    final state = AppScope.read(context);
    setState(() => _sending = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final text = [
      if (_selectedTags.isNotEmpty) _selectedTags.join(', '),
      _comment.text.trim(),
    ].where((t) => t.isNotEmpty).join('. ');
    final error = state.rateClient(r.id, _stars, text);
    setState(() => _sending = false);
    if (error != null) {
      showToast(context, error, error: true);
      return;
    }
    Haptics.success(context);
    showToast(context, 'Gracias. Tu calificación quedó guardada.',
        icon: Icons.cleaning_services_rounded);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final r = state.byId(widget.requestId);
    final pad = AppSpacing.screen(context) + 8;

    if (r == null) {
      return const Scaffold(
        body: Center(child: Text('Servicio no encontrado')),
      );
    }
    final check = state.canRate(r);

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            pad, MediaQuery.paddingOf(context).top + 8, pad, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Regresar',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                const AppLogo(size: 50),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 140,
                height: 140,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.aqua, AppColors.ice, AppColors.mint],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(r.client.initials,
                    style: AppText.display.copyWith(fontSize: 46)),
              ),
            ),
            const SizedBox(height: 12),
            Text(r.client.fullName,
                textAlign: TextAlign.center, style: AppText.title),
            Text(
              '${r.cleaningType} · ${Fmt.date(r.scheduledAt)} · ${Fmt.money(r.agreedPrice ?? 0)} MXN',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
            const SizedBox(height: 26),
            if (!check.allowed) ...[
              NoticeBox(message: check.reason!),
              const SizedBox(height: 14),
              AppButton(
                label: 'Ver calificación',
                variant: AppButtonVariant.outline,
                onPressed: () => showRatingDetails(context, r),
              ),
            ] else ...[
              Text('Califica tu experiencia', style: AppText.heading),
              const SizedBox(height: 12),
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BroomRating(
                    value: _stars,
                    size: 36,
                    onChanged: (v) => setState(() => _stars = v),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: AppDurations.fast,
                child: Text(
                  _stars == 0 ? 'Toca las escobas para calificar' : _labels[_stars - 1],
                  key: ValueKey(_stars),
                  textAlign: TextAlign.center,
                  style: AppText.label.copyWith(
                      color: _stars == 0 ? AppColors.inkMuted : AppColors.successFg),
                ),
              ),
              const SizedBox(height: 22),
              Text('¿Qué destacarías?', style: AppText.heading),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags.map((t) {
                  final selected = _selectedTags.contains(t);
                  return FilterChip(
                    label: Text(t),
                    selected: selected,
                    showCheckmark: false,
                    labelStyle: AppText.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppColors.ink,
                    ),
                    selectedColor: AppColors.primaryStrong,
                    backgroundColor: Colors.white,
                    side: BorderSide(
                        color: selected
                            ? AppColors.primaryStrong
                            : AppColors.border),
                    shape: const StadiumBorder(),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedTags.add(t);
                      } else {
                        _selectedTags.remove(t);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),
              Text('Cuéntanos cómo te fue', style: AppText.heading),
              const SizedBox(height: 10),
              AppTextField(
                controller: _comment,
                hint: 'Escribe un comentario (opcional)',
                maxLines: 5,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: 'Enviar calificación',
                  expand: false,
                  loading: _sending,
                  onPressed: _stars == 0 ? null : () => _send(r),
                ),
              ),
              if (_stars == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Selecciona al menos una escoba para enviar.',
                      textAlign: TextAlign.end, style: AppText.caption),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hoja con la calificación dada al cliente y la recibida.
Future<void> showRatingDetails(BuildContext context, ServiceRequest r) {
  return showAppSheet<void>(
    context,
    title: 'Calificaciones del servicio',
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${r.cleaningType} · ${Fmt.date(r.scheduledAt)}',
            style: AppText.body),
        const SizedBox(height: 14),
        AppCard(
          shadow: false,
          border: AppColors.divider,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tu calificación a ${r.client.shortName}',
                  style: AppText.label),
              const SizedBox(height: 6),
              r.clientRatingGiven == null
                  ? Text('Aún no calificas a este cliente.', style: AppText.body)
                  : BroomRating(value: r.clientRatingGiven!, size: 20),
              if (r.clientReviewGiven != null) ...[
                const SizedBox(height: 6),
                Text('“${r.clientReviewGiven}”', style: AppText.body),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          shadow: false,
          border: AppColors.divider,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Calificación que recibiste', style: AppText.label),
              const SizedBox(height: 6),
              r.ratingReceived == null
                  ? Text('El cliente todavía no te ha calificado.',
                      style: AppText.body)
                  : BroomRating(value: r.ratingReceived!, size: 20),
              if (r.reviewReceived != null) ...[
                const SizedBox(height: 6),
                Text('“${r.reviewReceived}”', style: AppText.body),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
