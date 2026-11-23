import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_request.dart';
import '../services/formatters.dart';
import '../services/validators.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_modals.dart';
import 'buttons.dart';
import 'common.dart';

class ProposalResult {
  const ProposalResult(this.amount, this.note);
  final double amount;
  final String note;
}

/// Hoja para presentar o editar una propuesta económica.
Future<ProposalResult?> showProposalSheet(
    BuildContext context, ServiceRequest r) {
  final editing = r.status == RequestStatus.pendiente;
  return showAppSheet<ProposalResult>(
    context,
    title: editing ? 'Editar propuesta' : 'Tu propuesta económica',
    builder: (ctx) => _ProposalForm(request: r, editing: editing),
  );
}

class _ProposalForm extends StatefulWidget {
  const _ProposalForm({required this.request, required this.editing});

  final ServiceRequest request;
  final bool editing;

  @override
  State<_ProposalForm> createState() => _ProposalFormState();
}

class _ProposalFormState extends State<_ProposalForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;

  ServiceRequest get r => widget.request;

  @override
  void initState() {
    super.initState();
    final initial = r.proposal?.amount ??
        r.clientOffer ??
        ((r.estimateMin + r.estimateMax) / 2 / 10).round() * 10.0;
    _amount = TextEditingController(text: initial.toStringAsFixed(0));
    _note = TextEditingController(text: r.proposal?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_amount.text.trim());

  void _set(double v) {
    final clamped = v.clamp(100.0, 20000.0).toDouble();
    setState(() => _amount.text = clamped.toStringAsFixed(0));
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(ProposalResult(_value!, _note.text));
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final mid = ((r.estimateMin + r.estimateMax) / 2 / 10).round() * 10.0;
    final quick = <String, double>{
      'Mínimo': r.estimateMin,
      'Medio': mid,
      'Máximo': r.estimateMax,
      if (r.extraServicePrice > 0) 'Con extra': r.estimateMax + r.extraServicePrice,
      if (r.clientOffer != null) 'Contraoferta': r.clientOffer!,
    };
    final upper = r.estimateMax + r.extraServicePrice;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'La plataforma no fija el precio: tú propones y el cliente decide. '
            'Puedes editar la propuesta mientras esté pendiente.',
            style: AppText.body,
          ),
          const SizedBox(height: 14),
          AppCard(
            shadow: false,
            border: AppColors.divider,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                InfoRow(
                    label: 'Estimado del cliente',
                    value: '${Fmt.range(r.estimateMin, r.estimateMax)} MXN'),
                if (r.extraService != null)
                  InfoRow(
                      label: r.extraService!,
                      value: '+${Fmt.money(r.extraServicePrice)} MXN'),
                if (r.clientOffer != null)
                  InfoRow(
                      label: 'Contraoferta',
                      value: '${Fmt.money(r.clientOffer!)} MXN',
                      valueStyle: AppText.bodyStrong
                          .copyWith(color: AppColors.warningFg)),
                if (widget.editing && r.proposal != null)
                  InfoRow(
                      label: 'Propuesta actual (v${r.proposal!.version})',
                      value: '${Fmt.money(r.proposal!.amount)} MXN'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Monto total (MXN)', style: AppText.subtitle),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleIconButton(
                icon: Icons.remove_rounded,
                tooltip: 'Restar \$10',
                background: AppColors.ice,
                onPressed: value == null ? null : () => _set(value - 10),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _amount,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(5),
                  ],
                  validator: (v) => Validators.amount(v),
                  onChanged: (_) => setState(() {}),
                  style: AppText.display.copyWith(fontSize: 28),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: AppText.title,
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    errorMaxLines: 2,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide:
                          const BorderSide(color: AppColors.primary, width: 1.6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CircleIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Sumar \$10',
                background: AppColors.ice,
                onPressed: value == null ? null : () => _set(value + 10),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: quick.entries.map((e) {
              final active = value == e.value;
              return ChoiceChip(
                label: Text('${e.key} ${Fmt.money(e.value)}'),
                selected: active,
                showCheckmark: false,
                labelStyle: AppText.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppColors.ink,
                ),
                selectedColor: AppColors.primaryStrong,
                backgroundColor: Colors.white,
                side: BorderSide(
                    color: active ? AppColors.primaryStrong : AppColors.border),
                shape: const StadiumBorder(),
                onSelected: (_) => _set(e.value),
              );
            }).toList(),
          ),
          AnimatedSize(
            duration: AppDurations.medium,
            child: value != null && value > upper * 1.15
                ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: NoticeBox.warning(
                        message:
                            'Tu monto supera bastante el estimado del cliente. Explica en la nota qué incluye.'),
                  )
                : value != null && value < r.estimateMin
                    ? const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: NoticeBox(
                            message:
                                'Tu monto está por debajo del estimado del cliente.'),
                      )
                    : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 16),
          Text('Nota para el cliente (opcional)', style: AppText.subtitle),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLength: 140,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            style: AppText.bodyStrong,
            decoration: InputDecoration(
              hintText: 'Ej. Incluye productos y limpieza de ventanas.',
              hintStyle: AppText.body,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AppButton(
            label: widget.editing ? 'Actualizar propuesta' : 'Enviar propuesta',
            icon: Icons.send_rounded,
            onPressed: value == null ? null : _submit,
          ),
        ],
      ),
    );
  }
}
