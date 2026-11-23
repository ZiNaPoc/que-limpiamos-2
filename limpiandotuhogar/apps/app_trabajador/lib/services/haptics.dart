import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app_scope.dart';

/// Retroalimentación táctil ligera respetando la preferencia del usuario.
class Haptics {
  Haptics._();

  static bool _enabled(BuildContext context) =>
      AppScope.read(context).profile.preferences.soundsEnabled;

  static void tap(BuildContext context) {
    if (_enabled(context)) HapticFeedback.selectionClick();
  }

  static void success(BuildContext context) {
    if (_enabled(context)) HapticFeedback.mediumImpact();
  }
}
