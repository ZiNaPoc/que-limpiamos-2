import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Mapa ilustrado (sin servicios externos). Con [exact] muestra un pin;
/// sin él, un área aproximada para proteger la privacidad del cliente.
class MiniMap extends StatelessWidget {
  const MiniMap({super.key, this.exact = false, this.height = 130, this.seed = 0});

  final bool exact;
  final double height;

  /// Varía ligeramente el trazo de calles entre solicitudes.
  final int seed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _MapPainter(exact: exact, seed: seed)),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.exact, required this.seed});

  final bool exact;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.ice);

    // Manzanas.
    final block = Paint()..color = AppColors.mist;
    final park = Paint()..color = AppColors.fade(AppColors.mint, 0.9);
    final offset = (seed % 3) * 14.0;
    for (var x = -20.0 + offset; x < w; x += 70) {
      for (var y = -10.0; y < h; y += 52) {
        final isPark = ((x + y + seed * 7) ~/ 61) % 5 == 0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x + 8, y + 8, 54, 36), const Radius.circular(6)),
          isPark ? park : block,
        );
      }
    }

    // Avenida curva y agua.
    final water = Path()
      ..moveTo(w * 0.78, 0)
      ..quadraticBezierTo(w * 0.70, h * 0.5, w, h * 0.9)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(water, Paint()..color = AppColors.fade(AppColors.lagoon, 0.55));

    final avenue = Paint()
      ..color = Colors.white
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final road = Path()
      ..moveTo(0, h * 0.72)
      ..cubicTo(w * 0.3, h * 0.55, w * 0.5, h * 0.95, w * 0.74, h * 0.35);
    canvas.drawPath(road, avenue);

    final center = Offset(w * 0.45, h * 0.48);
    if (exact) {
      canvas.drawCircle(center.translate(0, 14), 10,
          Paint()..color = AppColors.fade(AppColors.ink, 0.15));
      final pin = Path()
        ..moveTo(center.dx, center.dy + 14)
        ..cubicTo(center.dx - 22, center.dy - 6, center.dx - 12, center.dy - 30,
            center.dx, center.dy - 30)
        ..cubicTo(center.dx + 12, center.dy - 30, center.dx + 22, center.dy - 6,
            center.dx, center.dy + 14)
        ..close();
      canvas.drawPath(pin, Paint()..color = AppColors.primaryStrong);
      canvas.drawCircle(center.translate(0, -12), 6, Paint()..color = Colors.white);
    } else {
      canvas.drawCircle(
          center, 38, Paint()..color = AppColors.fade(AppColors.primary, 0.22));
      canvas.drawCircle(
          center,
          38,
          Paint()
            ..color = AppColors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      canvas.drawCircle(center, 5, Paint()..color = AppColors.primaryStrong);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.exact != exact || old.seed != seed;
}
