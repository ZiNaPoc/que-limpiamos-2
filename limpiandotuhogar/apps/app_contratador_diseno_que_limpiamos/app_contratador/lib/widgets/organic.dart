import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Forma orgánica (mancha suave) generada a partir de una semilla, para que
/// cada colaborador tenga una silueta propia pero estable.
Path blobPath(Size size, int seed, {int points = 7, double variance = 0.14}) {
  final rnd = math.Random(seed);
  final c = Offset(size.width / 2, size.height / 2);
  final r = math.min(size.width, size.height) / 2;
  final pts = <Offset>[];
  for (var i = 0; i < points; i++) {
    final a = (math.pi * 2 / points) * i - math.pi / 2;
    final k = 1 - variance + rnd.nextDouble() * variance;
    pts.add(c + Offset(math.cos(a), math.sin(a)) * r * k);
  }
  final path = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < points; i++) {
    final p0 = pts[(i - 1 + points) % points];
    final p1 = pts[i];
    final p2 = pts[(i + 1) % points];
    final p3 = pts[(i + 2) % points];
    // Catmull-Rom → Bézier cúbica para un contorno continuo.
    final c1 = p1 + (p2 - p0) / 6;
    final c2 = p2 - (p3 - p1) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path..close();
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.seed, this.colors);

  final int seed;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final path = blobPath(size, seed);
    canvas.drawPath(
      path.shift(const Offset(0, 4)),
      Paint()
        ..color = AppColors.fade(AppColors.primaryStrong, 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.seed != seed || old.colors != colors;
}

/// Paletas suaves para avatares (todas tomadas de la paleta oficial).
const List<List<Color>> blobPalettes = [
  [AppColors.mint, AppColors.seafoam],
  [AppColors.aqua, AppColors.lagoon],
  [AppColors.periwinkle, AppColors.sky],
  [AppColors.sage, AppColors.aqua],
  [AppColors.frost, AppColors.steel],
];

/// Avatar con forma orgánica e iniciales.
class BlobAvatar extends StatelessWidget {
  const BlobAvatar({
    super.key,
    required this.seed,
    this.initials = '',
    this.size = 64,
    this.icon,
  });

  final int seed;
  final String initials;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = blobPalettes[seed.abs() % blobPalettes.length];
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BlobPainter(seed, colors),
        child: Center(
          child: icon != null
              ? Icon(icon, size: size * 0.42, color: AppColors.ink)
              : Text(
                  initials,
                  style: AppText.heading
                      .copyWith(fontSize: size * 0.32, color: AppColors.ink),
                ),
        ),
      ),
    );
  }
}

/// Burbujas decorativas con un vaivén muy lento. Se detienen si el sistema
/// pide reducir el movimiento.
class BubbleField extends StatefulWidget {
  const BubbleField({super.key, this.seed = 1, this.count = 9, this.opacity = 1});

  final int seed;
  final int count;
  final double opacity;

  @override
  State<BubbleField> createState() => _BubbleFieldState();
}

class _BubbleFieldState extends State<BubbleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _BubblePainter(
              _c, widget.seed, widget.count, widget.opacity),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.anim, this.seed, this.count, this.opacity)
      : super(repaint: anim);

  final Animation<double> anim;
  final int seed;
  final int count;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final t = anim.value * math.pi * 2;
    for (var i = 0; i < count; i++) {
      final bx = size.width * (0.45 + rnd.nextDouble() * 0.6);
      final by = size.height * rnd.nextDouble();
      final r = 6 + rnd.nextDouble() * 22;
      final phase = rnd.nextDouble() * math.pi * 2;
      final c = Offset(bx + math.sin(t + phase) * 4, by + math.cos(t + phase) * 6);
      canvas.drawCircle(
          c, r, Paint()..color = AppColors.fade(Colors.white, 0.10 * opacity));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.fade(Colors.white, 0.45 * opacity),
      );
      canvas.drawCircle(c + Offset(-r * 0.35, -r * 0.35), r * 0.18,
          Paint()..color = AppColors.fade(Colors.white, 0.7 * opacity));
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.seed != seed || old.count != count || old.opacity != opacity;
}

/// Tarjeta destacada con degradado de la marca y burbujas.
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.child,
    this.seed = 1,
    this.padding = const EdgeInsets.fromLTRB(22, 22, 22, 22),
  });

  final Widget child;
  final int seed;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryStrong, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppRadius.xl),
          topRight: Radius.circular(AppRadius.md),
          bottomLeft: Radius.circular(AppRadius.md),
          bottomRight: Radius.circular(AppRadius.xl),
        ),
        boxShadow: AppShadows.lifted,
      ),
      child: Stack(
        children: [
          Positioned.fill(child: BubbleField(seed: seed)),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
