/// Formato de fechas, horas y montos en español (sin dependencias externas).
class Fmt {
  Fmt._();

  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', //
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const _monthsShort = [
    'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', //
    'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
  ];
  static const _weekdays = [
    'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
  ];
  static const _weekdaysShort = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  static String weekdayName(int weekday) => _weekdays[weekday - 1];
  static String weekdayShort(int weekday) => _weekdaysShort[weekday - 1];
  static String monthShort(DateTime d) => _monthsShort[d.month - 1];
  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// 03/11/26
  static String date(DateTime d) =>
      '${_two(d.day)}/${_two(d.month)}/${_two(d.year % 100)}';

  /// 3 de noviembre
  static String longDate(DateTime d) => '${d.day} de ${_months[d.month - 1]}';

  /// 3:00 p.m.
  static String time(DateTime d) => minutes(d.hour * 60 + d.minute);

  /// Convierte minutos desde medianoche a «3:00 p.m.».
  static String minutes(int totalMinutes) {
    final h = (totalMinutes ~/ 60) % 24;
    final m = totalMinutes % 60;
    final suffix = h < 12 ? 'a.m.' : 'p.m.';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${_two(m)} $suffix';
  }

  /// 03/11/26 · 3:00 p.m.
  static String dateTime(DateTime d) => '${date(d)} · ${time(d)}';

  /// «Hoy», «Mañana», «Ayer» o la fecha corta.
  static String relativeDay(DateTime d, DateTime now) {
    final diff = dayDiff(now, d);
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Mañana';
    if (diff == -1) return 'Ayer';
    return '${weekdayShort(d.weekday)} ${date(d)}';
  }

  /// Hace cuánto ocurrió algo: «Hace 5 min», «Hace 3 h», «Ayer», fecha.
  static String ago(DateTime d, DateTime now) {
    final diff = now.difference(d);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24 && dayDiff(d, now) == 0) {
      return 'Hace ${diff.inHours} h';
    }
    if (dayDiff(d, now) == 1) return 'Ayer · ${time(d)}';
    return date(d);
  }

  /// Diferencia en días naturales entre dos fechas.
  static int dayDiff(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return (b.difference(a).inHours / 24).round();
  }

  /// $4,500.00
  static String money(double amount, {bool decimals = false}) {
    final fixed = amount.toStringAsFixed(decimals ? 2 : 0);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final fromEnd = intPart.length - i;
      buffer.write(intPart[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1 && intPart[i] != '-') {
        buffer.write(',');
      }
    }
    return decimals ? '\$${buffer.toString()}.${parts[1]}' : '\$$buffer';
  }

  /// $450–550
  static String range(double min, double max) =>
      '${money(min)}–${money(max).substring(1)}';

  /// 1 h 25 min
  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// 00:12:45
  static String clock(Duration d) =>
      '${_two(d.inHours)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
}
