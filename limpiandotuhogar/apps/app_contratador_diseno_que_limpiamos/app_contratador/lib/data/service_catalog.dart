/// Tipos de limpieza que ofrece la app (mismos títulos, descripciones y
/// precios base que antes; las fotos ahora viven en assets).
class CleaningService {
  const CleaningService({
    required this.title,
    required this.description,
    required this.basePrice,
    required this.image,
  });

  final String title;
  final String description;

  /// Precio base en MXN (ej. 400).
  final int basePrice;

  /// Ruta de la foto: un asset (`assets/...`) o una URL (`https://...`).
  final String image;

  /// Texto que se muestra en tarjetas y en el flujo: «Desde $400».
  String get price => 'Desde ${money(basePrice)}';
}

class ServiceCatalog {
  ServiceCatalog._();

  static const String _img = 'assets/images/spaces';

  static const List<CleaningService> services = [
    CleaningService(
      title: 'Limpieza regular',
      description:
          'Limpieza de mantenimiento que incluye barrer, trapear y aspirar.',
      basePrice: 400,
      image: '$_img/sala.jpg',
    ),
    CleaningService(
      title: 'Limpieza profunda',
      description:
          'Limpieza detallada de todas las áreas del espacio, incluyendo zonas de difícil acceso.',
      basePrice: 600,
      image: '$_img/cocina.jpg',
    ),
    CleaningService(
      title: 'Limpieza post-obra',
      description: 'Limpieza después de una remodelación o construcción.',
      basePrice: 650,
      image: '$_img/obra.jpg',
    ),
  ];

  /// Orden de «Paquetes más populares» en Inicio.
  static List<CleaningService> get popular => [
        services[1], // profunda
        services[0], // regular
        services[2], // post-obra
      ];

  /// Búsqueda sin acentos ni mayúsculas por título o descripción.
  static List<CleaningService> search(String query) {
    final q = _normalize(query.trim());
    if (q.isEmpty) return const [];
    return services
        .where((s) =>
            _normalize(s.title).contains(q) ||
            _normalize(s.description).contains(q))
        .toList();
  }

  static String _normalize(String s) {
    const from = 'áéíóúüñÁÉÍÓÚÜÑ';
    const to = 'aeiouunAEIOUUN';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i == -1 ? ch : to[i]);
    }
    return b.toString().toLowerCase();
  }
}

/// $1,250 (sin decimales).
String money(int amount) {
  final digits = amount.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    b.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) b.write(',');
  }
  return '${amount < 0 ? '-' : ''}\$$b';
}
