import 'package:flutter/material.dart';

/// Logotipo oficial. Usa la versión con fondo transparente para colocarse
/// sobre las ondas; la proporción original se conserva con BoxFit.contain.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64, this.hero = false});

  static const String asset = 'assets/images/logo.png';
  static const String heroTag = 'app-logo';

  /// Ancho del logotipo. El alto se ajusta solo (proporción 851 × 921).
  final double size;
  /// Solo debe activarse cuando hay un único logotipo en la ruta.
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      width: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'Logotipo de ¿Qué limpiamos?',
    );
    return hero ? Hero(tag: heroTag, child: image) : image;
  }
}
