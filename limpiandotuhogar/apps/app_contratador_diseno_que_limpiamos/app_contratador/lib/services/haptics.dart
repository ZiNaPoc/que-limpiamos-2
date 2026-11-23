import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Retroalimentación táctil ligera en botones y acciones.
class Haptics {
  Haptics._();

  static void tap(BuildContext context) => HapticFeedback.selectionClick();

  static void success(BuildContext context) => HapticFeedback.mediumImpact();
}
