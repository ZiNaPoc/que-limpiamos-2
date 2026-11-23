import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class NavItem {
  const NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Barra inferior con indicador en forma de píldora que se desplaza.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.badges = const {},
  });

  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Índice → cantidad para mostrar un punto de aviso.
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottom > 0 ? bottom : 10),
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
      child: Row(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final active = i == currentIndex;
          final badge = badges[i] ?? 0;
          return Expanded(
            child: Semantics(
              selected: active,
              button: true,
              label: item.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () {
                  if (!active) Haptics.tap(context);
                  onTap(i);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedContainer(
                            duration: AppDurations.medium,
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.symmetric(
                                horizontal: active ? 18 : 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: active ? AppColors.aqua : Colors.transparent,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Icon(
                              active ? item.activeIcon : item.icon,
                              size: 22,
                              color: active ? AppColors.ink : AppColors.inkMuted,
                            ),
                          ),
                          if (badge > 0)
                            Positioned(
                              right: active ? 10 : 4,
                              top: 2,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: AppColors.errorFg,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 1.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      AnimatedDefaultTextStyle(
                        duration: AppDurations.medium,
                        style: AppText.caption.copyWith(
                          fontSize: 11,
                          color: active ? AppColors.ink : AppColors.inkMuted,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                        ),
                        child: Text(item.label,
                            maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
