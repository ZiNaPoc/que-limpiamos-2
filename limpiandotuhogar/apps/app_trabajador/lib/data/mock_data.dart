import '../models/app_notification.dart';
import '../models/service_request.dart';
import '../models/worker_profile.dart';

/// Datos simulados coherentes entre pantallas. Las fechas se generan de forma
/// relativa al día actual para que la agenda siempre tenga contenido.
class MockData {
  MockData._();

  static const demoEmail = 'demo@quelimpiamos.mx';
  static const demoPassword = 'Demo1234';

  static const String _img = 'assets/images/spaces';
  static const String photoKitchen = '$_img/cocina.jpg';
  static const String photoBath = '$_img/bano.jpg';
  static const String photoLiving = '$_img/sala.jpg';
  static const String photoBedroom = '$_img/recamara.jpg';
  static const String photoOffice = '$_img/oficina.jpg';
  static const String photoApartment = '$_img/departamento.jpg';

  static const List<String> allSpecialties = [
    'Limpieza regular',
    'Limpieza profunda',
    'Cocinas',
    'Baños',
    'Ventanas',
    'Oficinas',
    'Post-obra',
    'Mudanzas',
    'Planchado',
    'Alfombras',
  ];

  static List<DaySchedule> defaultSchedule() => List.generate(
        7,
        (i) => DaySchedule(
          weekday: i + 1,
          enabled: i < 6, // lunes a sábado
          startMinutes: 8 * 60,
          endMinutes: 19 * 60,
        ),
      );

  static WorkerProfile demoProfile(DateTime now) => WorkerProfile(
        firstName: 'Mariana',
        lastName: 'Canché Uc',
        email: demoEmail,
        phone: '9981112233',
        password: demoPassword,
        specialties: const [
          'Limpieza profunda',
          'Limpieza regular',
          'Cocinas',
          'Ventanas',
        ],
        ineStatus: IneStatus.verificada,
        memberSince: DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 120)),
        schedule: defaultSchedule(),
      );

  // ── Clientes ────────────────────────────────────────────────────
  static const _c1 = ClientInfo(
      id: 'c1',
      firstName: 'María Fernanda',
      lastName: 'López Cruz',
      phone: '9981234567',
      email: 'mafer.lopez@ejemplo.com',
      ineVerified: true,
      rating: 4.9,
      servicesRequested: 12,
      memberSince: 'marzo 2025');
  static const _c2 = ClientInfo(
      id: 'c2',
      firstName: 'Jorge',
      lastName: 'Ramírez Pool',
      phone: '9987654321',
      email: 'jorge.ramirez@ejemplo.com',
      ineVerified: true,
      rating: 4.7,
      servicesRequested: 5,
      memberSince: 'enero 2026');
  static const _c3 = ClientInfo(
      id: 'c3',
      firstName: 'Ana Sofía',
      lastName: 'Martínez',
      phone: '9983456789',
      email: 'anasofia.mtz@ejemplo.com',
      ineVerified: true,
      rating: 5.0,
      servicesRequested: 3,
      memberSince: 'junio 2026');
  static const _c4 = ClientInfo(
      id: 'c4',
      firstName: 'Luis',
      lastName: 'Pech Canul',
      phone: '9985551234',
      email: 'luis.pech@ejemplo.com',
      ineVerified: false,
      rating: 4.5,
      servicesRequested: 1,
      memberSince: 'octubre 2026');
  static const _c5 = ClientInfo(
      id: 'c5',
      firstName: 'Carmen',
      lastName: 'Ortiz Vega',
      phone: '9982223344',
      email: 'carmen.ortiz@ejemplo.com',
      ineVerified: true,
      rating: 4.8,
      servicesRequested: 20,
      memberSince: 'agosto 2024');
  static const _c6 = ClientInfo(
      id: 'c6',
      firstName: 'Roberto',
      lastName: 'Chan Díaz',
      phone: '9986667788',
      email: 'roberto.chan@ejemplo.com',
      ineVerified: true,
      rating: 4.6,
      servicesRequested: 8,
      memberSince: 'noviembre 2025');
  static const _c7 = ClientInfo(
      id: 'c7',
      firstName: 'Daniela',
      lastName: 'Herrera Sosa',
      phone: '9984445566',
      email: 'dani.herrera@ejemplo.com',
      ineVerified: true,
      rating: 4.9,
      servicesRequested: 6,
      memberSince: 'febrero 2026');
  static const _c8 = ClientInfo(
      id: 'c8',
      firstName: 'Patricia',
      lastName: 'Gómez Euán',
      phone: '9983332211',
      email: 'paty.gomez@ejemplo.com',
      ineVerified: true,
      rating: 4.8,
      servicesRequested: 9,
      memberSince: 'mayo 2025');

  // ── Espacios ────────────────────────────────────────────────────
  static const _houseLarge = SpaceInfo(
    type: PropertyType.casa,
    rooms: 3,
    fullBaths: 1,
    halfBaths: 0,
    floors: 2,
    approxM2: 140,
    areas: ['Cocina', 'Baños', 'Ventanas'],
    photos: [photoKitchen, photoBath, photoLiving],
    notes: 'Hay dos perros amigables. La cocina tiene grasa acumulada en la campana.',
    zone: 'SM 15, Cancún',
    address: 'Calle Margaritas 23, SM 15, Cancún, Q. Roo',
    distanceKm: 3.2,
  );

  static const _apartment = SpaceInfo(
    type: PropertyType.departamento,
    rooms: 2,
    fullBaths: 1,
    halfBaths: 1,
    floors: 1,
    approxM2: 75,
    areas: ['Sala', 'Recámaras'],
    photos: [photoLiving, photoBedroom, photoApartment],
    notes: 'Departamento en piso 4 con elevador.',
    zone: 'Puerto Cancún',
    address: 'Av. Bonampak 120, Torre B, Depto. 402, Puerto Cancún',
    distanceKm: 5.8,
  );

  static const _office = SpaceInfo(
    type: PropertyType.oficina,
    rooms: 3,
    fullBaths: 2,
    halfBaths: 0,
    floors: 1,
    approxM2: 180,
    areas: ['Escritorios', 'Sala de juntas', 'Baños'],
    photos: [photoOffice, photoBath],
    notes: 'Oficina con 12 escritorios. Se trabaja antes de las 10:00 a.m.',
    zone: 'Malecón Tajamar',
    address: 'Blvd. Colosio km 2, Plaza Tajamar, Local 8',
    distanceKm: 7.4,
  );

  static const _houseMedium = SpaceInfo(
    type: PropertyType.casa,
    rooms: 2,
    fullBaths: 2,
    halfBaths: 0,
    floors: 1,
    approxM2: 95,
    areas: ['Cocina', 'Sala', 'Baños'],
    photos: [photoKitchen, photoLiving],
    notes: 'Casa de una planta, estacionamiento frente a la casa.',
    zone: 'Residencial Cumbres',
    address: 'Cerrada Ébano 7, Residencial Cumbres, Cancún',
    distanceKm: 4.1,
  );

  static const _apartmentSmall = SpaceInfo(
    type: PropertyType.departamento,
    rooms: 1,
    fullBaths: 1,
    halfBaths: 0,
    floors: 1,
    approxM2: 55,
    areas: ['Ventanas', 'Sala', 'Cocina'],
    photos: [photoApartment, photoKitchen],
    notes: 'Ventanales amplios hacia la terraza.',
    zone: 'SM 50',
    address: 'Calle Pargo 14, Depto. 3, SM 50, Cancún',
    distanceKm: 2.6,
  );

  // ── Solicitudes ─────────────────────────────────────────────────
  static List<ServiceRequest> requests(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int dayOffset, int hour, [int minute = 0]) =>
        today.add(Duration(days: dayOffset, hours: hour, minutes: minute));
    DateTime ago(Duration d) => now.subtract(d);

    ChatMessage msg(String id, bool worker, String text, DateTime time,
            {MessageKind kind = MessageKind.text, double? amount}) =>
        ChatMessage(
            id: id,
            fromWorker: worker,
            kind: kind,
            text: text,
            time: time,
            amount: amount);

    return [
      // ── Oportunidades disponibles ──
      ServiceRequest(
        id: 'r1',
        cleaningType: 'Limpieza profunda',
        description:
            'Limpieza a fondo de cocina y baños: desengrasado, sarro, azulejos y detrás de electrodomésticos.',
        scheduledAt: at(2, 15),
        durationHours: 4,
        estimateMin: 450,
        estimateMax: 550,
        createdAt: ago(const Duration(minutes: 48)),
        client: _c1,
        space: _houseLarge,
        status: RequestStatus.disponible,
        extraService: 'Limpieza de ventanas',
        extraServicePrice: 300,
        extraDetails: '2 perros',
        conditions: const [
          'El cliente proporciona productos de limpieza',
          'Estacionamiento disponible',
        ],
      ),
      ServiceRequest(
        id: 'r2',
        cleaningType: 'Limpieza regular',
        description:
            'Limpieza de mantenimiento que incluye barrer, trapear y aspirar.',
        scheduledAt: at(4, 10),
        durationHours: 3,
        estimateMin: 400,
        estimateMax: 480,
        createdAt: ago(const Duration(hours: 2)),
        client: _c2,
        space: _apartment,
        status: RequestStatus.disponible,
        extraDetails: 'Edificio con elevador',
        conditions: const [
          'Llevar productos de limpieza propios',
          'Registro en recepción',
        ],
      ),
      ServiceRequest(
        id: 'r3',
        cleaningType: 'Limpieza de oficina',
        description:
            'Limpieza general de escritorios, sala de juntas, cocineta y baños.',
        scheduledAt: at(6, 7, 30),
        durationHours: 4,
        estimateMin: 900,
        estimateMax: 1100,
        createdAt: ago(const Duration(minutes: 20)),
        client: _c6,
        space: _office,
        status: RequestStatus.disponible,
        extraService: 'Lavado de alfombra',
        extraServicePrice: 250,
        extraDetails: 'Llegar antes de las 8:00 a.m.',
        conditions: const ['El cliente proporciona productos de limpieza'],
      ),
      ServiceRequest(
        id: 'r4',
        cleaningType: 'Limpieza post-obra',
        description: 'Retiro de polvo, restos de pintura y cemento.',
        scheduledAt: at(3, 9),
        durationHours: 6,
        estimateMin: 1200,
        estimateMax: 1500,
        createdAt: ago(const Duration(hours: 5)),
        client: _c4,
        space: _houseMedium,
        status: RequestStatus.cancelada,
        statusReason: 'El cliente ya confirmó con otro colaborador.',
      ),

      // ── En negociación ──
      ServiceRequest(
        id: 'r5',
        cleaningType: 'Limpieza de cocina',
        description:
            'Desengrasado de estufa, campana, alacenas por fuera y refrigerador.',
        scheduledAt: at(3, 11),
        durationHours: 3,
        estimateMin: 350,
        estimateMax: 420,
        createdAt: ago(const Duration(hours: 6)),
        client: _c3,
        space: _houseMedium,
        status: RequestStatus.pendiente,
        extraDetails: '2 mascotas',
        conditions: const ['Llevar productos desengrasantes'],
        proposal: Proposal(
            amount: 400,
            note: 'Incluye productos desengrasantes.',
            sentAt: ago(const Duration(hours: 3)),
            version: 1),
        messages: [
          msg('r5-1', true, 'Aceptaste la oportunidad. Ya puedes conversar con el cliente.',
              ago(const Duration(hours: 4)),
              kind: MessageKind.system),
          msg('r5-2', true,
              '¡Hola! Gracias por la solicitud. ¿Hay algo que deba saber antes de llegar?',
              ago(const Duration(hours: 4))),
          msg('r5-3', false,
              'Hola. Tengo dos mascotas en casa, solo para avisar.',
              ago(const Duration(hours: 3, minutes: 30))),
          msg('r5-4', true, 'Perfecto, lo tomo en cuenta.',
              ago(const Duration(hours: 3, minutes: 20))),
          msg('r5-5', true, 'Propuesta enviada', ago(const Duration(hours: 3)),
              kind: MessageKind.price, amount: 400),
        ],
      ),
      ServiceRequest(
        id: 'r6',
        cleaningType: 'Limpieza de mudanza',
        description:
            'Limpieza completa del departamento vacío antes de entregar las llaves.',
        scheduledAt: at(5, 9),
        durationHours: 5,
        estimateMin: 700,
        estimateMax: 850,
        createdAt: ago(const Duration(days: 1, hours: 2)),
        client: _c5,
        space: _apartment,
        status: RequestStatus.enNegociacion,
        conditions: const ['Departamento sin muebles', 'Llevar escalera pequeña'],
        proposal: Proposal(
            amount: 850,
            note: 'Incluye limpieza de clósets y ventanas interiores.',
            sentAt: ago(const Duration(hours: 20)),
            version: 1),
        clientOffer: 760,
        messages: [
          msg('r6-1', true, 'Aceptaste la oportunidad. Ya puedes conversar con el cliente.',
              ago(const Duration(hours: 22)),
              kind: MessageKind.system),
          msg('r6-2', true, 'Propuesta enviada', ago(const Duration(hours: 20)),
              kind: MessageKind.price, amount: 850),
          msg('r6-3', false,
              '¿Podrías dejarlo en \$760? Es un departamento pequeño.',
              ago(const Duration(hours: 1))),
        ],
      ),
      ServiceRequest(
        id: 'r7',
        cleaningType: 'Limpieza de ventanas',
        description: 'Ventanales interiores y exteriores, cancelería y marcos.',
        scheduledAt: at(2, 9),
        durationHours: 2,
        estimateMin: 300,
        estimateMax: 380,
        createdAt: ago(const Duration(days: 1, hours: 6)),
        client: _c7,
        space: _apartmentSmall,
        status: RequestStatus.aceptada,
        proposal: Proposal(
            amount: 360,
            note: '',
            sentAt: ago(const Duration(hours: 8)),
            version: 1),
        agreedPrice: 360,
        statusReason: 'El cliente aceptó tu propuesta.',
        messages: [
          msg('r7-1', true, 'Aceptaste la oportunidad. Ya puedes conversar con el cliente.',
              ago(const Duration(hours: 9)),
              kind: MessageKind.system),
          msg('r7-2', true, 'Propuesta enviada', ago(const Duration(hours: 8)),
              kind: MessageKind.price, amount: 360),
          msg('r7-3', false, '¡Perfecto! Acepto tu propuesta.',
              ago(const Duration(hours: 3))),
        ],
      ),

      // ── Confirmados (agenda) ──
      ServiceRequest(
        id: 'r8',
        cleaningType: 'Limpieza profunda',
        description:
            'Limpieza a fondo de cocina, baños y recámaras. Incluye ventanas interiores.',
        scheduledAt: at(0, 15),
        durationHours: 3,
        estimateMin: 500,
        estimateMax: 600,
        createdAt: ago(const Duration(days: 3)),
        client: _c8,
        space: _houseLarge,
        status: RequestStatus.confirmada,
        extraDetails: 'Tocar el timbre dos veces',
        conditions: const ['El cliente proporciona productos de limpieza'],
        proposal: Proposal(
            amount: 550,
            note: '',
            sentAt: ago(const Duration(days: 2, hours: 20)),
            version: 1),
        agreedPrice: 550,
        messages: [
          msg('r8-1', true, 'Servicio confirmado.', ago(const Duration(days: 2)),
              kind: MessageKind.system),
          msg('r8-2', false, 'Te espero a las 3. ¡Gracias!',
              ago(const Duration(days: 1))),
        ],
      ),
      ServiceRequest(
        id: 'r9',
        cleaningType: 'Limpieza regular',
        description: 'Barrer, trapear, sacudir y aspirar sala y recámaras.',
        scheduledAt: at(1, 16),
        durationHours: 3,
        estimateMin: 400,
        estimateMax: 480,
        createdAt: ago(const Duration(days: 4)),
        client: _c6,
        space: _houseMedium,
        status: RequestStatus.confirmada,
        proposal: Proposal(
            amount: 450,
            note: '',
            sentAt: ago(const Duration(days: 3)),
            version: 1),
        agreedPrice: 450,
        messages: [
          msg('r9-1', true, 'Servicio confirmado.', ago(const Duration(days: 2)),
              kind: MessageKind.system),
        ],
      ),
      ServiceRequest(
        id: 'r10',
        cleaningType: 'Limpieza de terraza',
        description: 'Lavado de piso de terraza, barandal y muebles exteriores.',
        scheduledAt: at(8, 10),
        durationHours: 2,
        estimateMin: 320,
        estimateMax: 400,
        createdAt: ago(const Duration(days: 2)),
        client: _c1,
        space: _apartmentSmall,
        status: RequestStatus.confirmada,
        proposal: Proposal(
            amount: 380,
            note: '',
            sentAt: ago(const Duration(days: 2)),
            version: 1),
        agreedPrice: 380,
        messages: [
          msg('r10-1', true, 'Servicio confirmado.', ago(const Duration(days: 1)),
              kind: MessageKind.system),
        ],
      ),

      // ── Historial ──
      _done('h1', 'Limpieza simple', at(-3, 16), 3, 600, _c2, _houseMedium,
          received: 5, review: 'Muy puntual y detallista.'),
      _done('h2', 'Limpieza después de un evento', at(-7, 12), 4, 500, _c5,
          _houseLarge,
          received: 4, review: 'Todo quedó muy bien.'),
      _done('h3', 'Limpieza profunda', at(-12, 10), 3, 300, _c3, _apartmentSmall,
          given: 5, received: 5, review: '¡Excelente trabajo!'),
      _done('h4', 'Limpieza regular', at(-16, 9), 3, 450, _c1, _houseMedium,
          given: 4, received: 5, review: 'Muy amable.'),
      _done('h5', 'Limpieza de oficina', at(-20, 8), 4, 900, _c6, _office,
          given: 5, received: 5, review: 'Recomendada al 100%.'),
      _done('h6', 'Limpieza de cocina', at(-26, 11), 2, 350, _c7, _apartmentSmall,
          given: 5, received: 4),
      _done('h7', 'Limpieza profunda', at(-33, 10), 4, 700, _c8, _houseLarge,
          given: 4, received: 5, review: 'La casa quedó impecable.'),
      _done('h8', 'Limpieza de mudanza', at(-40, 9), 5, 700, _c5, _apartment,
          given: 5, received: 5),

      ServiceRequest(
        id: 'x1',
        cleaningType: 'Limpieza de alberca',
        description: 'Limpieza de bordes y área de camastros.',
        scheduledAt: at(-1, 10),
        durationHours: 2,
        estimateMin: 300,
        estimateMax: 350,
        createdAt: at(-3, 9),
        client: _c4,
        space: _houseMedium,
        status: RequestStatus.rechazada,
        statusReason: 'Rechazaste la solicitud: no es una de mis especialidades.',
      ),
    ];
  }

  static ServiceRequest _done(
    String id,
    String type,
    DateTime when,
    int hours,
    double price,
    ClientInfo client,
    SpaceInfo space, {
    int? given,
    int? received,
    String? review,
  }) =>
      ServiceRequest(
        id: id,
        cleaningType: type,
        description: 'Servicio de $type realizado en ${space.zone}.',
        scheduledAt: when,
        durationHours: hours,
        estimateMin: price - 50,
        estimateMax: price + 50,
        createdAt: when.subtract(const Duration(days: 3)),
        client: client,
        space: space,
        status: RequestStatus.finalizada,
        proposal: Proposal(
            amount: price,
            note: '',
            sentAt: when.subtract(const Duration(days: 2)),
            version: 1),
        agreedPrice: price,
        startedAt: when,
        finishedAt: when.add(Duration(hours: hours)),
        clientRatingGiven: given,
        ratingReceived: received,
        reviewReceived: review,
      );

  // ── Notificaciones ──────────────────────────────────────────────
  static List<AppNotification> notifications(DateTime now) => [
        AppNotification(
          id: 'n1',
          type: NotificationType.solicitud,
          title: 'Nueva solicitud cerca de ti',
          body: 'Limpieza de oficina en Malecón Tajamar. Revisa los detalles y decide si te interesa.',
          time: now.subtract(const Duration(minutes: 20)),
          requestId: 'r3',
        ),
        AppNotification(
          id: 'n2',
          type: NotificationType.propuesta,
          title: 'Contraoferta recibida',
          body: 'Carmen propone \$760 por la limpieza de mudanza. Puedes aceptarla o enviar una nueva propuesta.',
          time: now.subtract(const Duration(hours: 1)),
          requestId: 'r6',
        ),
        AppNotification(
          id: 'n3',
          type: NotificationType.propuesta,
          title: 'Acuerdo de precio listo',
          body: 'Daniela aceptó tu propuesta de \$360. Confirma el servicio para agregarlo a tu agenda.',
          time: now.subtract(const Duration(hours: 3)),
          requestId: 'r7',
        ),
        AppNotification(
          id: 'n4',
          type: NotificationType.servicio,
          title: 'Tienes un servicio hoy',
          body: 'Limpieza profunda a las 3:00 p.m. en SM 15. Revisa la dirección antes de salir.',
          time: now.subtract(const Duration(hours: 5)),
          requestId: 'r8',
          read: true,
        ),
        AppNotification(
          id: 'n5',
          type: NotificationType.calificacion,
          title: 'Recibiste una calificación',
          body: 'Jorge te calificó con 5 escobas por «Limpieza simple».',
          time: now.subtract(const Duration(days: 2)),
          requestId: 'h1',
          read: true,
        ),
        AppNotification(
          id: 'n6',
          type: NotificationType.sistema,
          title: 'Bienvenida a ¿Qué limpiamos?',
          body: 'Mantén tu disponibilidad actualizada para recibir solicitudes dentro de tu horario.',
          time: now.subtract(const Duration(days: 9)),
          read: true,
        ),
      ];
}
