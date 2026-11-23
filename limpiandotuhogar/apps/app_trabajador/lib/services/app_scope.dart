import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Expone [AppState] al árbol de widgets sin paquetes externos.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  /// Obtiene el estado y reconstruye el widget cuando cambia.
  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope no encontrado en el árbol.');
    return scope!.notifier!;
  }

  /// Obtiene el estado sin suscribirse a cambios (para callbacks).
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope no encontrado en el árbol.');
    return scope!.notifier!;
  }
}
