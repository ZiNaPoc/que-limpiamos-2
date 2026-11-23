import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_logo.dart';
import 'buttons.dart';

/// Encabezado de pantalla: botón de regreso, acciones, logotipo y título.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.onBack,
    this.actions = const [],
    this.center = false,
    this.logoSize = 56,
    this.titleStyle,
    this.subtitleStyle,
    this.heroLogo = false,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool center;
  final double logoSize;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final bool heroLogo;

  @override
  Widget build(BuildContext context) {
    final align = center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = center ? TextAlign.center : TextAlign.start;
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          SizedBox(
            height: logoSize,
            child: Row(
              children: [
                if (onBack != null)
                  CircleIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: 'Regresar',
                    background: AppColors.fade(Colors.white, 0.7),
                    onPressed: onBack,
                  ),
                const Spacer(),
                ...actions.map((a) => Padding(
                    padding: const EdgeInsets.only(right: 10), child: a)),
                AppLogo(size: logoSize * 0.92, hero: heroLogo),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (eyebrow != null)
            Text(eyebrow!,
                textAlign: textAlign,
                style: AppText.subtitle.copyWith(color: AppColors.inkSoft)),
          Text(
            title,
            textAlign: textAlign,
            style: titleStyle ?? AppText.display,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                textAlign: textAlign, style: subtitleStyle ?? AppText.body),
          ],
        ],
      ),
    );
  }
}
