import 'package:flutter/material.dart';

import '../data/service_catalog.dart';
import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'buttons.dart';
import 'common.dart';

/// Foto de un servicio: acepta un asset (`assets/...`) o una URL.
class ServiceImage extends StatelessWidget {
  const ServiceImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String path;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    Widget error(BuildContext c, Object e, StackTrace? s) => Container(
          color: AppColors.ice,
          alignment: Alignment.center,
          child: const Icon(Icons.cleaning_services_outlined,
              color: AppColors.primary, size: 28),
        );
    if (path.startsWith('http')) {
      return Image.network(path,
          fit: fit, cacheWidth: cacheWidth, errorBuilder: error);
    }
    return Image.asset(path,
        fit: fit, cacheWidth: cacheWidth, errorBuilder: error);
  }
}

/// Encabezado de los pasos del flujo «Solicitar» con indicador de progreso.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.step,
    this.totalSteps = 4,
    this.onBack,
    this.showLogo = true,
  });

  final String title;
  final String? subtitle;
  final int? step;
  final int totalSteps;
  final VoidCallback? onBack;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    final s = step;
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Regresar',
                background: AppColors.fade(Colors.white, 0.8),
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(fontSize: 24)),
              ),
              if (showLogo) ...[
                const SizedBox(width: 8),
                const AppLogo(size: 40),
              ],
            ],
          ),
          if (s != null) ...[
            const SizedBox(height: 14),
            Row(
              children: List.generate(totalSteps, (i) {
                final done = i < s;
                return Expanded(
                  child: AnimatedContainer(
                    duration: AppDurations.slow,
                    curve: Curves.easeOutCubic,
                    margin: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 6),
                    height: 5,
                    decoration: BoxDecoration(
                      color: done
                          ? AppColors.primaryStrong
                          : AppColors.fade(Colors.white, 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: 10),
            Text(subtitle!,
                style: AppText.subtitle.copyWith(color: AppColors.inkSoft)),
          ],
        ],
      ),
    );
  }
}

/// Encabezado de las pestañas principales (Servicios, Avisos, Mi perfil).
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.display),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: AppText.subtitle.copyWith(color: AppColors.inkSoft)),
              ],
            ],
          ),
        ),
        trailing ?? const AppLogo(size: 50),
      ],
    );
  }
}

/// Chip «Historial» oscuro (Inicio y Mi perfil).
class HistoryChip extends StatelessWidget {
  const HistoryChip({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.history_rounded, size: 18, color: Colors.white),
      label: const Text('Historial'),
      labelStyle: AppText.label.copyWith(color: Colors.white),
      backgroundColor: AppColors.primaryStrong,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      onPressed: onPressed,
    );
  }
}

/// Tarjeta de servicio con imagen de borde orgánico (pantalla «Servicios»).
class ServiceTile extends StatelessWidget {
  const ServiceTile({super.key, required this.service, required this.onTap});

  final CleaningService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      color: AppColors.fade(AppColors.mint, 0.55),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(AppRadius.lg),
                bottomRight: Radius.circular(AppRadius.xl),
                topRight: Radius.circular(AppRadius.sm),
              ),
              child: SizedBox(
                width: 104,
                child: ServiceImage(path: service.image, cacheWidth: 320),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(service.title, style: AppText.heading),
                    const SizedBox(height: 4),
                    Text(service.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppText.caption.copyWith(color: AppColors.inkSoft)),
                    const SizedBox(height: 10),
                    Pill(
                      label: service.price,
                      background: Colors.white,
                      foreground: AppColors.primaryStrong,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.chevron_right_rounded,
                  color: AppColors.primaryStrong, size: 28),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta del carrusel «Paquetes más populares».
class PackageCard extends StatelessWidget {
  const PackageCard({super.key, required this.service, required this.onTap});

  final CleaningService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      color: AppColors.ice,
      radius: AppRadius.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.xl),
                topRight: Radius.circular(AppRadius.xl),
                bottomRight: Radius.circular(AppRadius.xl),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ServiceImage(path: service.image, cacheWidth: 600),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.subtitle
                              .copyWith(fontWeight: FontWeight.w700)),
                      Text(money(service.basePrice),
                          style: AppText.title
                              .copyWith(color: AppColors.primaryStrong)),
                    ],
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                      color: AppColors.primaryStrong, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip seleccionable (tipo de inmueble, áreas, servicios extra, filtros).
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = false,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Estilo menta para servicios extra (selección «suave»).
  final bool accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (accent ? AppColors.mint : AppColors.primaryStrong)
        : Colors.white;
    final fg = selected
        ? (accent ? AppColors.successFg : Colors.white)
        : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: () {
          Haptics.tap(context);
          onTap();
        },
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected
                  ? (accent ? AppColors.seafoam : AppColors.primaryStrong)
                  : AppColors.primary,
              width: 1.2,
            ),
            boxShadow: selected && !accent ? AppShadows.soft : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: AppDurations.fast,
                child: selected || icon != null
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          selected ? Icons.check_rounded : icon,
                          size: 16,
                          color: fg,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Flexible(
                child: Text(label,
                    style: AppText.label.copyWith(color: fg, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra inferior con el precio estimado y la acción principal.
class PriceBar extends StatelessWidget {
  const PriceBar({
    super.key,
    required this.min,
    required this.max,
    required this.actionLabel,
    required this.onAction,
  });

  final int min;
  final int max;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          22, 16, 18, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [
          BoxShadow(
            color: AppColors.fade(AppColors.primaryStrong, 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Precio estimado', style: AppText.caption),
                AnimatedSwitcher(
                  duration: AppDurations.medium,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position:
                          Tween(begin: const Offset(0, 0.3), end: Offset.zero)
                              .animate(a),
                      child: child,
                    ),
                  ),
                  child: FittedBox(
                    key: ValueKey('$min-$max'),
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        text: '${money(min)}-${money(max).substring(1)}',
                        style: AppText.title.copyWith(fontSize: 24),
                        children: [
                          TextSpan(
                              text: ' MXN',
                              style: AppText.caption
                                  .copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: actionLabel,
            expand: false,
            height: 48,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// Fila del resumen («Tipo», «Áreas»…).
class SummaryRow extends StatelessWidget {
  const SummaryRow(this.label, this.value, {super.key, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 10),
          ],
          SizedBox(
            width: 104,
            child: Text(label, style: AppText.body.copyWith(fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: AppText.bodyStrong.copyWith(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Campo de texto multilínea de los formularios del flujo (dirección, notas).
class FlowTextArea extends StatelessWidget {
  const FlowTextArea({
    super.key,
    required this.controller,
    required this.hint,
    this.minLines = 2,
    this.maxLines = 4,
    this.maxLength,
  });

  final TextEditingController controller;
  final String hint;
  final int minLines;
  final int maxLines;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.sentences,
      style: AppText.bodyStrong,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.body.copyWith(color: AppColors.inkMuted),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide:
              const BorderSide(color: AppColors.primaryStrong, width: 1.8),
        ),
      ),
    );
  }
}
