import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Fondo con ondas orgánicas inspirado en los mockups.
///
/// [headerHeight] es la altura (en píxeles) aproximada donde termina la onda
/// superior. [phase] permite animar suavemente las ondas (solo en el splash).
class WaveBackground extends StatelessWidget {
  const WaveBackground({
    super.key,
    required this.headerHeight,
    this.bottomWaves = false,
    this.phase = 0,
    this.child,
  });

  final double headerHeight;
  final bool bottomWaves;
  final double phase;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _WavePainter(
                headerHeight: headerHeight,
                bottomWaves: bottomWaves,
                phase: phase,
              ),
            ),
          ),
        ),
        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.headerHeight,
    required this.bottomWaves,
    required this.phase,
  });

  final double headerHeight;
  final bool bottomWaves;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = headerHeight;
    final shift = math.sin(phase * math.pi * 2) * 10;

    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.background);

    if (h > 0) {
      // Onda trasera (profundidad).
      final back = Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h * 0.86 + shift)
        ..cubicTo(w * 0.72, h * 0.70 - shift, w * 0.38, h * 1.12 + shift, 0,
            h * 1.04)
        ..close();
      canvas.drawPath(
          back, Paint()..color = AppColors.fade(AppColors.steel, 0.45));

      // Onda principal.
      final front = Path()
        ..moveTo(0, 0)
        ..lineTo(w, 0)
        ..lineTo(w, h * 0.76 - shift)
        ..cubicTo(w * 0.70, h * 0.60 + shift, w * 0.40, h * 1.06 - shift, 0,
            h * 0.96)
        ..close();
      canvas.drawPath(
        front,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.sky, AppColors.aqua],
          ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    }

    if (bottomWaves) {
      final fullH = size.height;
      _bottomWave(canvas, w, fullH, 0.84, AppColors.fade(AppColors.aqua, 0.55),
          shift);
      _bottomWave(canvas, w, fullH, 0.89, AppColors.fade(AppColors.lagoon, 0.6),
          -shift);
      _bottomWave(canvas, w, fullH, 0.94, AppColors.fade(AppColors.sky, 0.85),
          shift * 0.6);
    }
  }

  void _bottomWave(
      Canvas canvas, double w, double h, double level, Color color, double s) {
    final top = h * level;
    final path = Path()
      ..moveTo(0, top + 26 + s)
      ..cubicTo(w * 0.30, top - 14 - s, w * 0.62, top + 46 + s, w, top - 6)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.headerHeight != headerHeight ||
      old.bottomWaves != bottomWaves ||
      old.phase != phase;
}
