import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Tarjeta base con radio coherente, sombra suave y respuesta al toque.
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.color = AppColors.surface,
    this.radius = AppRadius.lg,
    this.shadow = true,
    this.border,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final bool shadow;
  final Color? border;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  void _set(bool v) {
    if (widget.onTap != null && _pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    return AnimatedScale(
      scale: _pressed ? 0.985 : 1,
      duration: AppDurations.fast,
      child: Container(
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: radius,
          border: widget.border == null
              ? null
              : Border.all(color: widget.border!, width: 1.2),
          boxShadow: widget.shadow ? AppShadows.soft : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap == null
                ? null
                : () {
                    Haptics.tap(context);
                    widget.onTap!();
                  },
            onTapDown: (_) => _set(true),
            onTapUp: (_) => _set(false),
            onTapCancel: () => _set(false),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Píldora de texto (insignias, etiquetas, chips informativos).
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.background = AppColors.frost,
    this.foreground = AppColors.ink,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.medium,
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 8 : 12, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: dense ? 11 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de sección con acción opcional a la derecha.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: AppText.heading)),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!,
                  style: AppText.label.copyWith(color: AppColors.primaryStrong)),
            ),
        ],
      ),
    );
  }
}

/// Fila «etiqueta — valor».
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueStyle,
  });

  final String label;
  final String value;
  final IconData? icon;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: AppText.body)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle ?? AppText.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vacío ilustrado.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: AppColors.ice,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text(title, style: AppText.heading, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(message, style: AppText.body, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Mensaje informativo/advertencia dentro de una pantalla.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.background = AppColors.ice,
    this.foreground = AppColors.inkSoft,
    this.action,
  });

  const NoticeBox.warning({super.key, required this.message, this.action})
      : icon = Icons.error_outline_rounded,
        background = AppColors.warningBg,
        foreground = AppColors.warningFg;

  const NoticeBox.success({super.key, required this.message, this.action})
      : icon = Icons.check_circle_outline_rounded,
        background = AppColors.successBg,
        foreground = AppColors.successFg;

  const NoticeBox.error({super.key, required this.message, this.action})
      : icon = Icons.block_rounded,
        background = AppColors.errorBg,
        foreground = AppColors.errorFg;

  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.medium,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message,
                    style: AppText.body.copyWith(color: foreground, height: 1.35)),
                if (action != null) action!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila con contador circular (como «Número de habitaciones  3»).
class CounterRow extends StatelessWidget {
  const CounterRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.bodyStrong)),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ice,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(value, style: AppText.label),
          ),
        ],
      ),
    );
  }
}

/// Avatar circular: foto local, o iniciales sobre un tono de la paleta.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    super.key,
    this.initials = '',
    this.photoPath,
    this.size = 48,
    this.background = AppColors.seafoam,
  });

  final String initials;
  final String? photoPath;
  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: initials.isEmpty
          ? Icon(Icons.person_rounded, size: size * 0.6, color: AppColors.ink)
          : Text(
              initials,
              style: AppText.heading
                  .copyWith(fontSize: size * 0.36, color: AppColors.ink),
            ),
    );
    final path = photoPath;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: path == null
          ? fallback
          : Image.file(
              File(path),
              fit: BoxFit.cover,
              cacheWidth: (size * 3).round(),
              errorBuilder: (context, error, stack) => fallback,
            ),
    );
  }
}

/// Calificación con escobas (1–5). Interactiva si [onChanged] no es nulo.
class BroomRating extends StatelessWidget {
  const BroomRating({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 34,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final selected = i < value;
        final icon = AnimatedScale(
          scale: selected ? 1.08 : 1,
          duration: AppDurations.medium,
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: AppDurations.medium,
            margin: EdgeInsets.symmetric(horizontal: size * 0.1),
            padding: EdgeInsets.all(size * 0.18),
            decoration: BoxDecoration(
              color: selected ? AppColors.mint : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              selected
                  ? Icons.cleaning_services_rounded
                  : Icons.cleaning_services_outlined,
              size: size,
              color: selected ? AppColors.successFg : AppColors.inkMuted,
            ),
          ),
        );
        if (onChanged == null) return icon;
        return Semantics(
          button: true,
          label: '${i + 1} escobas',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Haptics.tap(context);
              onChanged!(i + 1);
            },
            child: icon,
          ),
        );
      }),
    );
  }
}

/// Animación de entrada: aparece con desvanecido y desplazamiento corto.
/// Se usa con retrasos escalonados en listas para dar ritmo sin saturar.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 18,
  });

  /// Retraso escalonado para el elemento [index] de una lista.
  static Duration stagger(int index) =>
      Duration(milliseconds: 40 + (index > 8 ? 8 : index) * 55);

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curve.value) * widget.offset),
          child: child,
        ),
      ),
    );
  }
}

/// Selector de chips con indicador animado (filtros y pestañas).
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    this.countOf,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelOf;
  final int Function(T)? countOf;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: options.map((o) {
          final active = o == selected;
          final count = countOf?.call(o);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                Haptics.tap(context);
                onSelected(o);
              },
              child: AnimatedContainer(
                duration: AppDurations.medium,
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? AppColors.primaryStrong : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                      color: active ? AppColors.primaryStrong : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labelOf(o),
                      style: AppText.label.copyWith(
                          color: active ? Colors.white : AppColors.ink),
                    ),
                    if (count != null && count > 0) ...[
                      const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: AppDurations.medium,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.fade(Colors.white, 0.25)
                              : AppColors.frost,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
