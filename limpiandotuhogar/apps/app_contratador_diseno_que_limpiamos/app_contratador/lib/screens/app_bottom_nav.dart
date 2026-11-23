import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'avisos_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'services_screen.dart';

/// Barra de navegación flotante con indicador en forma de gota
/// (diseño de ¿Qué limpiamos?).
///
/// Úsala como `bottomNavigationBar` de un `Scaffold` con `extendBody: true`.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int>? onTap;

  static const List<_NavEntry> _items = [
    _NavEntry('Inicio', Icons.home_outlined, Icons.home_rounded),
    _NavEntry('Solicitar', Icons.auto_awesome_outlined, Icons.auto_awesome),
    _NavEntry('Avisos', Icons.notifications_none_rounded,
        Icons.notifications_rounded),
    _NavEntry('Perfil', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  /// Espacio que conviene dejar al final de las listas para que la barra
  /// flotante no tape el contenido.
  static double reservedHeight(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return 68 + (bottom > 0 ? bottom : 12) + 16;
  }

  void _navegar(BuildContext context, int destino) {
    if (destino == currentIndex) return;

    switch (destino) {
      case 0:
        _ir(context, const HomeScreen());
        break;
      case 1:
        _ir(context, const ServicesScreen());
        break;
      case 2:
        _ir(context, const AvisosScreen());
        break;
      case 3:
        _ir(context, const PerfilScreen());
        break;
    }
  }

  // Cambia de pestaña quitando todo lo anterior, así Welcome ya no queda debajo
  void _ir(BuildContext context, Widget pantalla) {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => pantalla,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (context, animation, _, child) {
          if (MediaQuery.disableAnimationsOf(context)) return child;
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final side = MediaQuery.sizeOf(context).width < 360 ? 12.0 : 20.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 0, side, bottom > 0 ? bottom : 12),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
              color: AppColors.fade(AppColors.primaryStrong, 0.16),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _NavItem(
                  entry: _items[i],
                  selected: i == currentIndex,
                  onTap: () {
                    if (i != currentIndex) Haptics.tap(context);
                    if (onTap != null) {
                      onTap!(i);
                    } else {
                      _navegar(context, i);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavEntry {
  const _NavEntry(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _NavEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: entry.label,
      child: InkResponse(
        radius: 34,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: AppDurations.medium,
              curve: Curves.easeOutBack,
              width: selected ? 46 : 34,
              height: selected ? 34 : 30,
              decoration: BoxDecoration(
                color: selected ? AppColors.ice : Colors.transparent,
                borderRadius: BorderRadius.circular(17),
                border: selected
                    ? Border.all(color: AppColors.aqua, width: 1.2)
                    : null,
              ),
              child: Icon(
                selected ? entry.activeIcon : entry.icon,
                size: 22,
                color: selected ? AppColors.primaryStrong : AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppDurations.medium,
              style: AppText.caption.copyWith(
                fontSize: 11,
                color: selected ? AppColors.ink : AppColors.inkMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(entry.label,
                  maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
          ],
        ),
      ),
    );
  }
}
