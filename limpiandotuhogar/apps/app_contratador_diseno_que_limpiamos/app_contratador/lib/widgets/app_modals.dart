import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'buttons.dart';

/// Hoja inferior con asa, esquinas redondeadas y soporte de teclado.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  String? title,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.fade(AppColors.ink, 0.35),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.fog,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                      child: Text(title, style: AppText.title),
                    ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: builder(sheetContext),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Diálogo centrado con animación de escala y desvanecido.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Cerrar',
    barrierColor: AppColors.fade(AppColors.ink, 0.45),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final width = MediaQuery.sizeOf(dialogContext).width;
      return SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: width < 360 ? 16 : 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                clipBehavior: Clip.antiAlias,
                child: builder(dialogContext),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Diálogo de confirmación. Devuelve `true` si el usuario confirma.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Volver',
  IconData icon = Icons.help_outline_rounded,
  bool destructive = false,
}) async {
  final result = await showAppDialog<bool>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: destructive ? AppColors.errorBg : AppColors.ice,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 30,
                  color: destructive ? AppColors.errorFg : AppColors.primaryStrong),
            ),
            const SizedBox(height: 16),
            Text(title, style: AppText.title, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: AppText.body, textAlign: TextAlign.center),
            const SizedBox(height: 22),
            AppButton(
              label: confirmLabel,
              variant:
                  destructive ? AppButtonVariant.danger : AppButtonVariant.primary,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(cancelLabel,
                  style: AppText.label.copyWith(color: AppColors.inkSoft)),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Hoja para elegir un motivo (rechazo/cancelación). Devuelve el texto.
Future<String?> pickReason(
  BuildContext context, {
  required String title,
  required String description,
  required List<String> reasons,
  required String confirmLabel,
}) {
  return showAppSheet<String>(
    context,
    title: title,
    builder: (ctx) => _ReasonPicker(
      description: description,
      reasons: reasons,
      confirmLabel: confirmLabel,
    ),
  );
}

class _ReasonPicker extends StatefulWidget {
  const _ReasonPicker({
    required this.description,
    required this.reasons,
    required this.confirmLabel,
  });

  final String description;
  final List<String> reasons;
  final String confirmLabel;

  @override
  State<_ReasonPicker> createState() => _ReasonPickerState();
}

class _ReasonPickerState extends State<_ReasonPicker> {
  static const _other = 'Otro motivo';
  String? _selected;
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String? get _value {
    if (_selected == null) return null;
    if (_selected == _other) {
      final t = _otherController.text.trim();
      return t.length < 4 ? null : t;
    }
    return _selected;
  }

  @override
  Widget build(BuildContext context) {
    final options = [...widget.reasons, _other];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.description, style: AppText.body),
        const SizedBox(height: 12),
        ...options.map((o) {
          final active = o == _selected;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => setState(() => _selected = o),
              child: AnimatedContainer(
                duration: AppDurations.fast,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: active ? AppColors.ice : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: active ? AppColors.primary : AppColors.border,
                      width: active ? 1.6 : 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      active
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: active ? AppColors.primaryStrong : AppColors.inkMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(o, style: AppText.bodyStrong)),
                  ],
                ),
              ),
            ),
          );
        }),
        AnimatedSize(
          duration: AppDurations.medium,
          child: _selected == _other
              ? Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: TextField(
                    controller: _otherController,
                    autofocus: true,
                    maxLength: 120,
                    onChanged: (_) => setState(() {}),
                    style: AppText.bodyStrong,
                    decoration: InputDecoration(
                      hintText: 'Escribe el motivo (mínimo 4 caracteres)',
                      hintStyle: AppText.body,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 8),
        AppButton(
          label: widget.confirmLabel,
          variant: AppButtonVariant.danger,
          onPressed: _value == null ? null : () => Navigator.of(context).pop(_value),
        ),
      ],
    );
  }
}

/// Mensaje breve en la parte inferior.
void showToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  bool error = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 2600),
      backgroundColor: error ? AppColors.errorFg : AppColors.ink,
      content: Row(
        children: [
          Icon(error ? Icons.info_outline_rounded : icon,
              color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: AppText.body.copyWith(color: Colors.white)),
          ),
        ],
      ),
    ),
  );
}
