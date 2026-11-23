import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Campo de texto con etiqueta superior, estilo de los mockups (píldora
/// blanca con sombra suave), validación y modos de contraseña/edición.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.onTap,
    this.obscure = false,
    this.editable = true,
    this.readOnly = false,
    this.lockable = false,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.prefixIcon,
    this.suffix,
    this.focusNode,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool obscure;
  final bool editable;
  final bool readOnly;

  /// Muestra un lápiz: el campo queda bloqueado hasta que se pulsa.
  final bool lockable;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final Widget? suffix;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;
  late bool _locked = widget.lockable;
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ownFocus?.dispose();
    super.dispose();
  }

  void _unlock() {
    setState(() => _locked = !_locked);
    if (!_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  Widget? _buildSuffix() {
    if (widget.suffix != null) return widget.suffix;
    if (widget.obscure) {
      return IconButton(
        tooltip: _hidden ? 'Mostrar contraseña' : 'Ocultar contraseña',
        onPressed: () => setState(() => _hidden = !_hidden),
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: AppColors.inkMuted,
        ),
      );
    }
    if (widget.lockable) {
      return IconButton(
        tooltip: _locked ? 'Editar' : 'Bloquear',
        onPressed: _unlock,
        icon: AnimatedSwitcher(
          duration: AppDurations.fast,
          child: Icon(
            _locked ? Icons.edit_outlined : Icons.check_rounded,
            key: ValueKey(_locked),
            color: _locked ? AppColors.inkSoft : AppColors.primaryStrong,
          ),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final multiline = widget.maxLines > 1;
    final radius =
        BorderRadius.circular(multiline ? AppRadius.lg : AppRadius.pill);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );

    final field = TextFormField(
      controller: widget.controller,
      focusNode: _focus,
      validator: widget.validator,
      keyboardType: multiline ? TextInputType.multiline : widget.keyboardType,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      onTap: widget.onTap,
      obscureText: _hidden,
      enabled: widget.editable,
      readOnly: widget.readOnly || _locked,
      maxLines: multiline ? widget.maxLines : 1,
      minLines: multiline ? (widget.maxLines > 3 ? 3 : widget.maxLines) : 1,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: AppText.bodyStrong.copyWith(
          color: _locked ? AppColors.inkSoft : AppColors.ink),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: AppText.body.copyWith(color: AppColors.inkMuted),
        filled: true,
        fillColor: widget.editable ? Colors.white : AppColors.surfaceAlt,
        isDense: true,
        counterText: '',
        contentPadding: EdgeInsets.symmetric(
            horizontal: 20, vertical: multiline ? 16 : 15),
        prefixIcon: widget.prefixIcon == null
            ? null
            : Icon(widget.prefixIcon, color: AppColors.inkMuted, size: 20),
        suffixIcon: _buildSuffix(),
        errorMaxLines: 2,
        errorStyle: AppText.caption.copyWith(color: AppColors.errorFg),
        border: border(AppColors.border),
        enabledBorder: border(_locked ? AppColors.divider : AppColors.border),
        disabledBorder: border(AppColors.divider),
        focusedBorder: border(AppColors.primary, 1.6),
        errorBorder: border(AppColors.errorFg),
        focusedErrorBorder: border(AppColors.errorFg, 1.6),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Text(widget.label!, style: AppText.subtitle),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: AppColors.fade(AppColors.primaryStrong, 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: field,
        ),
      ],
    );
  }
}
