/// Modelos de solicitudes de servicio, cliente, espacio, propuesta y chat.
library;

/// Ciclo de vida de una solicitud desde el punto de vista del trabajador.
///
/// disponible → (aceptación inicial) → enNegociacion → (propuesta) → pendiente
/// → (acuerdo de precio) → aceptada → (confirmación definitiva) → confirmada
/// → enCurso → finalizada. En cualquier punto previo al servicio puede pasar a
/// rechazada o cancelada.
enum RequestStatus {
  disponible,
  enNegociacion,
  pendiente,
  aceptada,
  confirmada,
  enCurso,
  finalizada,
  rechazada,
  cancelada;

  /// Estados que todavía no tienen acuerdo (pestaña «Por acordar»).
  bool get isNegotiating =>
      this == enNegociacion || this == pendiente || this == aceptada;

  /// Estados que forman parte de la agenda de trabajo.
  bool get isScheduled => this == confirmada || this == enCurso;

  /// Estados cerrados que ya no admiten acciones.
  bool get isClosed => this == rechazada || this == cancelada;
}

enum PropertyType {
  casa('Casa'),
  departamento('Departamento'),
  oficina('Oficina');

  const PropertyType(this.label);
  final String label;
}

enum MessageKind { text, system, price, location, photo }

class ClientInfo {
  const ClientInfo({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    required this.ineVerified,
    required this.rating,
    required this.servicesRequested,
    required this.memberSince,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final bool ineVerified;
  final double rating;
  final int servicesRequested;
  final String memberSince;

  String get fullName => '$firstName $lastName';
  String get shortName => '$firstName ${lastName.isNotEmpty ? lastName[0] : ''}.';
  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
          .toUpperCase();

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'email': email,
        'ineVerified': ineVerified,
        'rating': rating,
        'servicesRequested': servicesRequested,
        'memberSince': memberSince,
      };

  factory ClientInfo.fromJson(Map<String, dynamic> j) => ClientInfo(
        id: j['id'] as String,
        firstName: j['firstName'] as String,
        lastName: j['lastName'] as String,
        phone: j['phone'] as String,
        email: j['email'] as String,
        ineVerified: j['ineVerified'] as bool,
        rating: (j['rating'] as num).toDouble(),
        servicesRequested: j['servicesRequested'] as int,
        memberSince: j['memberSince'] as String,
      );
}

class SpaceInfo {
  const SpaceInfo({
    required this.type,
    required this.rooms,
    required this.fullBaths,
    required this.halfBaths,
    required this.floors,
    required this.approxM2,
    required this.areas,
    required this.photos,
    required this.notes,
    required this.zone,
    required this.address,
    required this.distanceKm,
  });

  final PropertyType type;
  final int rooms;
  final int fullBaths;
  final int halfBaths;
  final int floors;
  final int approxM2;
  final List<String> areas;

  /// Rutas de assets con las fotografías que compartió el cliente.
  final List<String> photos;
  final String notes;

  /// Zona aproximada (visible siempre).
  final String zone;

  /// Dirección exacta (visible solo cuando el servicio está confirmado).
  final String address;
  final double distanceKm;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'rooms': rooms,
        'fullBaths': fullBaths,
        'halfBaths': halfBaths,
        'floors': floors,
        'approxM2': approxM2,
        'areas': areas,
        'photos': photos,
        'notes': notes,
        'zone': zone,
        'address': address,
        'distanceKm': distanceKm,
      };

  factory SpaceInfo.fromJson(Map<String, dynamic> j) => SpaceInfo(
        type: PropertyType.values.byName(j['type'] as String),
        rooms: j['rooms'] as int,
        fullBaths: j['fullBaths'] as int,
        halfBaths: j['halfBaths'] as int,
        floors: j['floors'] as int,
        approxM2: j['approxM2'] as int,
        areas: List<String>.from(j['areas'] as List),
        photos: List<String>.from(j['photos'] as List),
        notes: j['notes'] as String,
        zone: j['zone'] as String,
        address: j['address'] as String,
        distanceKm: (j['distanceKm'] as num).toDouble(),
      );
}

class Proposal {
  const Proposal({
    required this.amount,
    required this.note,
    required this.sentAt,
    required this.version,
  });

  final double amount;
  final String note;
  final DateTime sentAt;

  /// Número de veces que se ha enviado/editado la propuesta.
  final int version;

  Map<String, dynamic> toJson() => {
        'amount': amount,
        'note': note,
        'sentAt': sentAt.toIso8601String(),
        'version': version,
      };

  factory Proposal.fromJson(Map<String, dynamic> j) => Proposal(
        amount: (j['amount'] as num).toDouble(),
        note: j['note'] as String,
        sentAt: DateTime.parse(j['sentAt'] as String),
        version: j['version'] as int,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.fromWorker,
    required this.kind,
    required this.text,
    required this.time,
    this.amount,
    this.imagePath,
    this.imageIsAsset = false,
  });

  final String id;
  final bool fromWorker;
  final MessageKind kind;
  final String text;
  final DateTime time;
  final double? amount;
  final String? imagePath;
  final bool imageIsAsset;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromWorker': fromWorker,
        'kind': kind.name,
        'text': text,
        'time': time.toIso8601String(),
        'amount': amount,
        'imagePath': imagePath,
        'imageIsAsset': imageIsAsset,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        fromWorker: j['fromWorker'] as bool,
        kind: MessageKind.values.byName(j['kind'] as String),
        text: j['text'] as String,
        time: DateTime.parse(j['time'] as String),
        amount: (j['amount'] as num?)?.toDouble(),
        imagePath: j['imagePath'] as String?,
        imageIsAsset: (j['imageIsAsset'] as bool?) ?? false,
      );
}

class ServiceRequest {
  ServiceRequest({
    required this.id,
    required this.cleaningType,
    required this.description,
    required this.scheduledAt,
    required this.durationHours,
    required this.estimateMin,
    required this.estimateMax,
    required this.createdAt,
    required this.client,
    required this.space,
    required this.status,
    this.extraService,
    this.extraServicePrice = 0,
    this.extraDetails = '',
    this.conditions = const [],
    this.proposal,
    this.clientOffer,
    this.agreedPrice,
    this.statusReason,
    this.startedAt,
    this.finishedAt,
    List<ChatMessage>? messages,
    this.clientRatingGiven,
    this.clientReviewGiven,
    this.ratingReceived,
    this.reviewReceived,
  }) : messages = messages ?? [];

  final String id;
  final String cleaningType;
  final String description;
  final DateTime scheduledAt;
  final int durationHours;

  /// Rango estimado por el cliente (la plataforma no fija el precio).
  final double estimateMin;
  final double estimateMax;
  final DateTime createdAt;
  final ClientInfo client;
  final SpaceInfo space;
  final String? extraService;
  final double extraServicePrice;
  final String extraDetails;
  final List<String> conditions;

  // ── Estado mutable ──
  RequestStatus status;
  Proposal? proposal;

  /// Contraoferta del cliente (datos simulados).
  double? clientOffer;

  /// Precio acordado cuando existe acuerdo.
  double? agreedPrice;

  /// Motivo del rechazo/cancelación o comentario del estado.
  String? statusReason;
  DateTime? startedAt;
  DateTime? finishedAt;
  final List<ChatMessage> messages;

  /// Calificación que el trabajador dio al cliente.
  int? clientRatingGiven;
  String? clientReviewGiven;

  /// Calificación que el trabajador recibió (datos simulados).
  int? ratingReceived;
  String? reviewReceived;

  /// Precio que se muestra en listados según el estado.
  double get displayPrice =>
      agreedPrice ?? proposal?.amount ?? (estimateMin + estimateMax) / 2;

  bool get hasAgreement => agreedPrice != null;

  DateTime get endsAt => scheduledAt.add(Duration(hours: durationHours));

  /// La solicitud fue tomada por otro colaborador.
  bool get takenByOther =>
      status == RequestStatus.cancelada &&
      (statusReason ?? '').contains('otro colaborador');

  Map<String, dynamic> toJson() => {
        'id': id,
        'cleaningType': cleaningType,
        'description': description,
        'scheduledAt': scheduledAt.toIso8601String(),
        'durationHours': durationHours,
        'estimateMin': estimateMin,
        'estimateMax': estimateMax,
        'createdAt': createdAt.toIso8601String(),
        'client': client.toJson(),
        'space': space.toJson(),
        'status': status.name,
        'extraService': extraService,
        'extraServicePrice': extraServicePrice,
        'extraDetails': extraDetails,
        'conditions': conditions,
        'proposal': proposal?.toJson(),
        'clientOffer': clientOffer,
        'agreedPrice': agreedPrice,
        'statusReason': statusReason,
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'clientRatingGiven': clientRatingGiven,
        'clientReviewGiven': clientReviewGiven,
        'ratingReceived': ratingReceived,
        'reviewReceived': reviewReceived,
      };

  factory ServiceRequest.fromJson(Map<String, dynamic> j) => ServiceRequest(
        id: j['id'] as String,
        cleaningType: j['cleaningType'] as String,
        description: j['description'] as String,
        scheduledAt: DateTime.parse(j['scheduledAt'] as String),
        durationHours: j['durationHours'] as int,
        estimateMin: (j['estimateMin'] as num).toDouble(),
        estimateMax: (j['estimateMax'] as num).toDouble(),
        createdAt: DateTime.parse(j['createdAt'] as String),
        client: ClientInfo.fromJson(j['client'] as Map<String, dynamic>),
        space: SpaceInfo.fromJson(j['space'] as Map<String, dynamic>),
        status: RequestStatus.values.byName(j['status'] as String),
        extraService: j['extraService'] as String?,
        extraServicePrice: (j['extraServicePrice'] as num?)?.toDouble() ?? 0,
        extraDetails: (j['extraDetails'] as String?) ?? '',
        conditions: List<String>.from((j['conditions'] as List?) ?? const []),
        proposal: j['proposal'] == null
            ? null
            : Proposal.fromJson(j['proposal'] as Map<String, dynamic>),
        clientOffer: (j['clientOffer'] as num?)?.toDouble(),
        agreedPrice: (j['agreedPrice'] as num?)?.toDouble(),
        statusReason: j['statusReason'] as String?,
        startedAt: j['startedAt'] == null
            ? null
            : DateTime.parse(j['startedAt'] as String),
        finishedAt: j['finishedAt'] == null
            ? null
            : DateTime.parse(j['finishedAt'] as String),
        messages: ((j['messages'] as List?) ?? const [])
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
        clientRatingGiven: j['clientRatingGiven'] as int?,
        clientReviewGiven: j['clientReviewGiven'] as String?,
        ratingReceived: j['ratingReceived'] as int?,
        reviewReceived: j['reviewReceived'] as String?,
      );
}
