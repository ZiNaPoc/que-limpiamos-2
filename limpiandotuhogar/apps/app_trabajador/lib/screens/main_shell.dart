import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../widgets/bottom_nav.dart';
import 'agenda_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'requests_screen.dart';

/// Filtros de la pantalla de solicitudes (compartidos con el inicio).
enum RequestFilter { todas, nuevas, porAcordar }

/// Contenedor principal con la barra de navegación inferior.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialTab = 0});

  final int initialTab;

  /// Acceso al contenedor desde cualquier pestaña.
  static MainShellState? of(BuildContext context) =>
      context.findAncestorStateOfType<MainShellState>();

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  static const tabHome = 0;
  static const tabRequests = 1;
  static const tabAgenda = 2;
  static const tabHistory = 3;
  static const tabProfile = 4;

  static const _items = [
    NavItem('Inicio', Icons.home_outlined, Icons.home_rounded),
    NavItem('Solicitudes', Icons.inbox_outlined, Icons.inbox_rounded),
    NavItem('Agenda', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
    NavItem('Historial', Icons.history_rounded, Icons.history_toggle_off_rounded),
    NavItem('Perfil', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  late int _index = widget.initialTab;

  /// Filtro activo en Solicitudes (puede fijarse desde el inicio).
  final ValueNotifier<RequestFilter> requestFilter =
      ValueNotifier(RequestFilter.todas);

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  late final Animation<double> _fadeCurve =
      CurvedAnimation(parent: _fade, curve: Curves.easeOut);

  int get currentTab => _index;

  void goTo(int index, {RequestFilter? filter}) {
    if (filter != null) requestFilter.value = filter;
    if (index == _index) return;
    setState(() => _index = index);
    _fade.forward(from: 0.2);
  }

  @override
  void dispose() {
    _fade.dispose();
    requestFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final requestsBadge = state.availableRequests.length + state.needsAction.length;

    return PopScope(
      canPop: _index == tabHome,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) goTo(tabHome);
      },
      child: Scaffold(
        extendBody: false,
        body: FadeTransition(
          opacity: _fadeCurve,
          child: IndexedStack(
            index: _index,
            children: const [
              HomeScreen(),
              RequestsScreen(),
              AgendaScreen(),
              HistoryScreen(),
              ProfileScreen(),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomNav(
          items: _items,
          currentIndex: _index,
          onTap: goTo,
          badges: {tabRequests: requestsBadge},
        ),
      ),
    );
  }
}
