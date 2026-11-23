import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

enum AppButtonVariant {
  /// Acción principal (tono profundo del color principal).
  primary,

  /// Acción destacada suave (como «Aceptar solicitud» en los mockups).
  soft,

  /// Botón blanco con borde (acciones secundarias).
  outline,

  /// Acción destructiva.
  danger,
}

/// Botón con respuesta al toque (escala), estado de carga y deshabilitado.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final double height;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  (Color, Color, Color?) _colors() {
    if (!_enabled && !widget.loading) {
      return (AppColors.disabled, AppColors.inkMuted, null);
    }
    return switch (widget.variant) {
      AppButtonVariant.primary => (AppColors.primaryStrong, Colors.white, null),
      AppButtonVariant.soft => (AppColors.aqua, AppColors.ink, null),
      AppButtonVariant.outline => (
          Colors.white,
          AppColors.primaryStrong,
          AppColors.border
        ),
      AppButtonVariant.danger => (AppColors.errorBg, AppColors.errorFg, null),
    };
  }

  void _setPressed(bool value) {
    if (_enabled && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _colors();
    final radius = BorderRadius.circular(AppRadius.pill);

    final content = AnimatedSwitcher(
      duration: AppDurations.fast,
      child: widget.loading
          ? SizedBox(
              key: const ValueKey('loading'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.button.copyWith(color: fg),
                  ),
                ),
              ],
            ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: AppDurations.fast,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: AppDurations.medium,
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: border == null ? null : Border.all(color: border),
            boxShadow: _enabled && widget.variant == AppButtonVariant.primary
                ? AppShadows.soft
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: _enabled
                  ? () {
                      Haptics.tap(context);
                      widget.onPressed!();
                    }
                  : null,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(widthFactor: 1, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enlace de texto (p. ej. «¿Olvidaste tu contraseña?»).
class AppLinkButton extends StatelessWidget {
  const AppLinkButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.primaryStrong,
    this.underline = true,
    this.fontSize = 14,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool underline;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          label,
          style: AppText.label.copyWith(
            fontSize: fontSize,
            color: enabled ? color : AppColors.inkMuted,
            fontWeight: FontWeight.w700,
            decoration: underline ? TextDecoration.underline : null,
            decorationColor: enabled ? color : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// Botón circular de icono (volver, notificaciones, llamar…) con insignia.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.badge = 0,
    this.background = Colors.white,
    this.foreground = AppColors.ink,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final int badge;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed == null
            ? null
            : () {
                Haptics.tap(context);
                onPressed!();
              },
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon,
              color: onPressed == null ? AppColors.inkMuted : foreground,
              size: size * 0.5),
        ),
      ),
    );

    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: -2,
          top: -2,
          child: AnimatedScale(
            scale: badge > 0 ? 1 : 0,
            duration: AppDurations.medium,
            curve: Curves.easeOutBack,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.errorFg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: AppText.caption.copyWith(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1),
              ),
            ),
          ),
        ),
      ],
    );
    final t = tooltip;
    return t == null ? stack : Tooltip(message: t, child: stack);
  }
}
