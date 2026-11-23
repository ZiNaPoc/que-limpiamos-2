/// Notificaciones locales de la aplicación.
library;

enum NotificationType {
  solicitud,
  propuesta,
  servicio,
  calificacion,
  sistema,
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.time,
    this.read = false,
    this.requestId,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime time;
  bool read;

  /// Solicitud relacionada (permite navegar al detalle).
  final String? requestId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'time': time.toIso8601String(),
        'read': read,
        'requestId': requestId,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: NotificationType.values.byName(j['type'] as String),
        title: j['title'] as String,
        body: j['body'] as String,
        time: DateTime.parse(j['time'] as String),
        read: j['read'] as bool,
        requestId: j['requestId'] as String?,
      );
}
