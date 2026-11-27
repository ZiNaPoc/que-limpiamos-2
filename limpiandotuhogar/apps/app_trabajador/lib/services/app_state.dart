import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mock_data.dart';
import '../models/app_notification.dart';
import '../models/service_request.dart';
import '../models/worker_profile.dart';
import 'api_client.dart';
import 'formatters.dart';
import 'requests_api.dart';
import 'resenas_reportes_api.dart';
import 'storage_service.dart';

/// Resultado de validar si una acción está permitida. Cuando no lo está,
/// [reason] explica por qué para mostrarlo en la interfaz.
class ActionCheck {
  const ActionCheck.ok()
      : allowed = true,
        reason = null;
  const ActionCheck.no(this.reason) : allowed = false;

  final bool allowed;
  final String? reason;
}

/// Respuestas del cliente que se pueden simular (modo demostración).
enum SimulatedResponse { acepta, contraoferta, rechaza }

/// Estado global de la aplicación del trabajador.
///
/// Hay dos tipos de solicitudes:
///  - REALES (id `api-…`, docs/backend/25 v2): vienen del backend (consulta cada 3 s) y TODAS sus
///    acciones van al servidor: aceptar, rechazar, iniciar, terminar con fotos y cancelar. Sin
///    negociación ni chat; la calificación y los reportes se hacen en «Mis servicios».
///  - De DEMOSTRACIÓN (datos simulados, «Restablecer demostración»): siguen siendo locales y se
///    guardan con [StorageService].
class AppState extends ChangeNotifier {
  AppState({StorageService? storage, DateTime Function()? clock})
      : _storage = storage,
        _clock = clock ?? DateTime.now {
    _seed();
  }

  final StorageService? _storage;
  final DateTime Function() _clock;
  int _seq = 0;

  bool _loggedIn = false;
  bool _online = true;
  late WorkerProfile _profile;
  late List<ServiceRequest> _requests;
  late List<AppNotification> _notifications;

  // ── Sincronización con el backend ──
  static const _remotePrefix = 'api-';
  static const _pollEvery = Duration(seconds: 3);

  int? _workerId;
  Timer? _timer;
  bool _syncing = false;
  bool _disposed = false;
  final Set<String> _accepting = {};

  DateTime get now => _clock();

  // ════════════════════════════════════════════════════════════════
  // Carga y persistencia
  // ════════════════════════════════════════════════════════════════

  void _seed() {
    final n = now;
    _profile = MockData.demoProfile(n);
    _requests = MockData.requests(n);
    _notifications = MockData.notifications(n);
    _online = true;
  }

  Future<void> load() async {
    final storage = _storage;
    if (storage == null) return;
    await storage.init();
    final data = storage.read();
    if (data == null) return;
    try {
      _loggedIn = (data['loggedIn'] as bool?) ?? false;
      _online = (data['online'] as bool?) ?? true;
      _workerId = (data['workerId'] as num?)?.toInt();
      _profile =
          WorkerProfile.fromJson(data['profile'] as Map<String, dynamic>);
      _requests = (data['requests'] as List)
          .map((e) => ServiceRequest.fromJson(e as Map<String, dynamic>))
          .toList();
      _notifications = (data['notifications'] as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Datos incompatibles: se vuelve a los datos simulados.
      _loggedIn = false;
      _workerId = null;
      _seed();
    }
    // Al reabrir la app con la sesión iniciada, se reanuda la sincronización.
    if (_loggedIn && _workerId != null) _startSync();
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'loggedIn': _loggedIn,
        'online': _online,
        'workerId': _workerId,
        'profile': _profile.toJson(),
        'requests': _requests.map((r) => r.toJson()).toList(),
        'notifications': _notifications.map((n) => n.toJson()).toList(),
      };

  /// Notifica a la interfaz y guarda los cambios.
  void _commit() {
    if (_disposed) return;
    notifyListeners();
    final storage = _storage;
    if (storage != null) unawaited(storage.write(toJson()));
  }

  String _newId(String prefix) =>
      '$prefix-${now.microsecondsSinceEpoch}-${_seq++}';

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════
  // Sesión
  // ════════════════════════════════════════════════════════════════

  bool get isLoggedIn => _loggedIn;
  WorkerProfile get profile => _profile;

  /// Id del trabajador en el backend (null si la sesión es local/demo).
  int? get workerId => _workerId;

  /// Inicia sesión localmente (cuenta de prueba). Devuelve un mensaje de error o `null`.
  String? login(String email, String password) {
    final e = email.trim().toLowerCase();
    if (e == _profile.email.toLowerCase() && password == _profile.password) {
      _stopSync();
      _workerId = null;
      _loggedIn = true;
      _commit();
      return null;
    }
    if (e == MockData.demoEmail && password == MockData.demoPassword) {
      _stopSync();
      _workerId = null;
      _profile = MockData.demoProfile(now).copyWith(
          schedule: _profile.schedule, preferences: _profile.preferences);
      _loggedIn = true;
      _commit();
      return null;
    }
    return 'Correo o contraseña incorrectos.';
  }

  /// Sesión con una cuenta real del backend (login).
  ///
  /// Guarda el id del trabajador, limpia los datos de demostración y
  /// arranca la sincronización de solicitudes.
  void loginRemote({
    required int workerId,
    required String name,
    required String email,
    required String phone,
  }) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final cleanEmail = email.trim().toLowerCase();
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');

    final sameAccount = _profile.email.toLowerCase() == cleanEmail;
    if (sameAccount) {
      // Misma cuenta: se conservan especialidades, horario y preferencias.
      _profile = _profile.copyWith(
        firstName: first,
        lastName: last,
        phone: cleanPhone,
      );
    } else {
      _profile = WorkerProfile(
        firstName: first,
        lastName: last,
        email: cleanEmail,
        phone: cleanPhone,
        password: '',
        specialties: <String>[],
        ineStatus: IneStatus.enRevision,
        memberSince: now,
        schedule: MockData.defaultSchedule(),
      );
    }

    if (_workerId != workerId) {
      // Otra cuenta (o venimos de los datos demo): se empieza limpio.
      _requests = <ServiceRequest>[];
      _notifications = <AppNotification>[];
    }
    _workerId = workerId;
    _loggedIn = true;
    _online = true;
    _commit();
    _startSync();
  }

  /// Vincula la cuenta recién registrada en el backend y empieza a recibir
  /// solicitudes. Se llama justo después de [register].
  void bindRemoteWorker(int workerId) {
    // Se borran las solicitudes de demostración para que no se mezclen
    // con las reales. (Quita esta línea si quieres conservarlas.)
    _requests = <ServiceRequest>[];
    _notifications = _notifications
        .where((n) => n.requestId == null || byId(n.requestId!) != null)
        .toList();
    _workerId = workerId;
    _loggedIn = true;
    _commit();
    _startSync();
  }

  void register({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String ineFrontPath,
    required String ineBackPath,
    required List<String> specialties,
  }) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.first;
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    // La INE es opcional: si no se subió, las rutas llegan vacías.
    final hasIne = ineFrontPath.isNotEmpty && ineBackPath.isNotEmpty;
    _profile = WorkerProfile(
      firstName: first,
      lastName: last,
      email: email.trim().toLowerCase(),
      phone: phone.replaceAll(RegExp(r'\D'), ''),
      password: password,
      specialties: specialties,
      // OJO: si tu enum IneStatus tiene un valor como "sinSubir", úsalo
      // aquí cuando !hasIne. Con el enum actual se queda en enRevision.
      ineStatus: IneStatus.enRevision,
      memberSince: now,
      schedule: MockData.defaultSchedule(),
      ineFrontPath: ineFrontPath,
      ineBackPath: ineBackPath,
    );
    _loggedIn = true;
    _online = true;
    _addNotification(
      NotificationType.sistema,
      '¡Te damos la bienvenida, $first!',
      hasIne
          ? 'Tu cuenta se creó correctamente. Tu INE aparece «En revisión» (simulado).'
          : 'Tu cuenta se creó correctamente. Sube tu INE cuando quieras para verificar tu cuenta.',
    );
    _commit();
  }

  /// Simula la recuperación de contraseña. Indica si el correo existe.
  bool requestPasswordReset(String email) =>
      email.trim().toLowerCase() == _profile.email.toLowerCase() ||
      email.trim().toLowerCase() == MockData.demoEmail;

  void logout() {
    _stopSync();
    _loggedIn = false;
    _commit();
  }

  /// Restablece los datos de demostración sin cerrar la sesión.
  void resetDemo() {
    _stopSync();
    _workerId = null;
    _seed();
    _loggedIn = true;
    _commit();
  }

  // ════════════════════════════════════════════════════════════════
  // Sincronización con el backend (polling)
  // ════════════════════════════════════════════════════════════════

  bool _isRemote(ServiceRequest r) => r.id.startsWith(_remotePrefix);

  int? _remoteId(ServiceRequest r) =>
      int.tryParse(r.id.substring(_remotePrefix.length));

  void _startSync() {
    _stopSync();
    debugPrint('[sync] start, workerId=$_workerId');
    if (_workerId == null) return;
    unawaited(_restoreAccepted());
    unawaited(_syncOnce());
    _timer = Timer.periodic(_pollEvery, (_) => unawaited(_syncOnce()));
  }

  void _stopSync() {
    _timer?.cancel();
    _timer = null;
  }

  /// Consulta las solicitudes disponibles y las mezcla con las locales.
  Future<void> _syncOnce() async {
    final wid = _workerId;
    if (wid == null || _syncing || _disposed) return;
    _syncing = true;
    try {
      final list = await RequestsApi.disponibles();
      debugPrint('[sync] disponibles: ${list.length}');
      if (_disposed || _workerId != wid) return;
      _applyDisponibles(list);
      // Estado de las asignadas (el cliente pudo cancelar o confirmar; D54 pudo cerrarla).
      final asignadas = await RequestsApi.asignadas();
      if (_disposed || _workerId != wid) return;
      _applyAsignadas(asignadas);
    } catch (e, st) {
      // Sin conexión un momento: se reintenta en el siguiente ciclo.
      debugPrint('[sync] ERROR: $e\n$st');
    } finally {
      _syncing = false;
    }
  }

  /// ¿Es una solicitud REAL del backend (no de demostración)?
  bool isRemote(ServiceRequest r) => _isRemote(r);

  void _applyDisponibles(List<RemoteRequest> list) {
    var changed = false;
    final remoteIds = <String>{for (final r in list) '$_remotePrefix${r.id}'};

    // 1) Solicitudes nuevas.
    final nuevas = <ServiceRequest>[];
    for (final remote in list) {
      final id = '$_remotePrefix${remote.id}';
      if (byId(id) != null) continue;
      final req = _fromRemote(remote, RequestStatus.disponible);
      nuevas.add(req);
      _addNotification(
        NotificationType.servicio,
        'Nueva solicitud de limpieza',
        '${req.client.shortName} pidió «${req.cleaningType}» para ${Fmt.dateTime(req.scheduledAt)}.',
        requestId: id,
      );
    }
    if (nuevas.isNotEmpty) {
      debugPrint('[sync] nuevas agregadas: ${nuevas.length}');
      _requests = [..._requests, ...nuevas];
      changed = true;
    }

    // 2) Las que seguían "nuevas" y ya no vienen: las tomó otro colaborador.
    for (final r in _requests) {
      if (_isRemote(r) &&
          r.status == RequestStatus.disponible &&
          !remoteIds.contains(r.id) &&
          !_accepting.contains(r.id)) {
        r.status = RequestStatus.cancelada;
        r.statusReason = 'Tomada por otro colaborador.';
        changed = true;
      }
    }

    if (changed) _commit();
  }

  /// Estado local que corresponde al estado del servidor de una solicitud ASIGNADA.
  RequestStatus _estadoLocal(RemoteRequest r) => switch (r.estado) {
        'EN_PROCESO' => r.trabajadorTerminoEn != null ? RequestStatus.finalizada : RequestStatus.enCurso,
        'REALIZADO' => RequestStatus.finalizada,
        'CANCELADO' || 'RECHAZADO' => RequestStatus.cancelada,
        _ => RequestStatus.confirmada,
      };

  /// Pone al día las solicitudes reales asignadas con lo que dice el servidor.
  void _applyAsignadas(List<RemoteRequest> list) {
    var changed = false;
    final vistas = <String>{};
    for (final remote in list) {
      final id = '$_remotePrefix${remote.id}';
      vistas.add(id);
      final local = byId(id);
      final estado = _estadoLocal(remote);
      if (local == null) {
        final req = _fromRemote(remote, estado);
        req.agreedPrice = remote.total;
        _requests = [..._requests, req];
        changed = true;
      } else if (local.status != estado) {
        local.status = estado;
        local.agreedPrice ??= remote.total;
        local.statusReason = switch (remote.estado) {
          'CANCELADO' => 'La solicitud se canceló.',
          'REALIZADO' => 'Servicio realizado.',
          'EN_PROCESO' when remote.trabajadorTerminoEn != null => 'Marcaste terminado: falta la confirmación del cliente.',
          _ => null,
        };
        changed = true;
      }
    }
    // Asignada aquí pero ya no en el servidor (p. ej. la cancelaste y volvió a la bolsa).
    for (final r in _requests) {
      if (_isRemote(r) && r.status.isScheduled && !vistas.contains(r.id)) {
        r.status = RequestStatus.cancelada;
        r.statusReason = 'Ya no está asignada a ti.';
        changed = true;
      }
    }
    if (changed) _commit();
  }

  /// Recupera las solicitudes que este trabajador ya aceptó en el backend
  /// (por ejemplo, al iniciar sesión en otro dispositivo).
  Future<void> _restoreAccepted() async {
    final wid = _workerId;
    if (wid == null) return;
    try {
      final list = await RequestsApi.asignadas();
      debugPrint('[sync] asignadas: ${list.length}');
      if (_disposed || _workerId != wid) return;
      _applyAsignadas(list);
    } catch (e, st) {
      // No es crítico, pero se registra para depurar.
      debugPrint('[sync] restoreAccepted ERROR: $e\n$st');
    }
  }

  /// Convierte una solicitud del backend al modelo que usan las pantallas.
  ServiceRequest _fromRemote(RemoteRequest r, RequestStatus status) {
    final nameParts = r.clienteNombre.trim().split(RegExp(r'\s+'));
    final first = nameParts.first.isEmpty ? 'Cliente' : nameParts.first;
    final last = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final client = ClientInfo(
      id: 'c-api-${r.id}',
      firstName: first,
      lastName: last,
      phone: '', // el teléfono del cliente no se comparte
      email: '',
      ineVerified: false,
      rating: 5.0,
      servicesRequested: 1,
      memberSince: 'Reciente',
    );

    final PropertyType type;
    switch (r.casa.tipo.toUpperCase()) {
      case 'OFICINA':
        type = PropertyType.oficina;
      case 'DEPARTAMENTO':
        type = PropertyType.departamento;
      default:
        type = PropertyType.casa;
    }

    final space = SpaceInfo(
      type: type,
      rooms: r.casa.habitaciones,
      fullBaths: r.casa.banos,
      halfBaths: r.casa.mediosBanos,
      floors: r.casa.pisos,
      approxM2: 0,
      areas: r.areas,
      photos: const [],
      notes: r.notas,
      zone: 'Cancún',
      // La dirección exacta solo llega cuando la solicitud está asignada a ti.
      address: r.direccion ?? 'Se muestra al aceptar',
      distanceKm: 0,
    );

    return ServiceRequest(
      id: '$_remotePrefix${r.id}',
      cleaningType: r.servicio,
      description: r.relacion == 'INVITADO' ? 'Solicitud real · te invitaron' : 'Solicitud real · bolsa abierta',
      scheduledAt: r.fecha,
      durationHours: (r.duracionMin / 60).ceil(),
      estimateMin: r.total,
      estimateMax: r.total,
      createdAt: now,
      client: client,
      space: space,
      status: status,
      extraService: r.extras.isEmpty ? null : r.extras.map((e) => e.nombre).join(', '),
      extraServicePrice: r.extras.fold<double>(0, (s, e) => s + e.precio),
      extraDetails: '',
      conditions: const [],
    );
  }

  // ════════════════════════════════════════════════════════════════
  // Perfil, disponibilidad y preferencias
  // ════════════════════════════════════════════════════════════════

  bool get isOnline => _online;

  void setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    _commit();
  }

  void updateProfile(WorkerProfile profile) {
    _profile = profile;
    _commit();
  }

  void updateSchedule(List<DaySchedule> schedule) {
    _profile = _profile.copyWith(schedule: schedule);
    _commit();
  }

  void updatePreferences(WorkerPreferences prefs) {
    _profile = _profile.copyWith(preferences: prefs);
    _commit();
  }

  /// ¿El servicio completo cabe dentro del horario configurado?
  bool isWithinSchedule(ServiceRequest r) {
    final day = _profile.dayFor(r.scheduledAt.weekday);
    final start = r.scheduledAt.hour * 60 + r.scheduledAt.minute;
    final end = start + r.durationHours * 60;
    return day.enabled && start >= day.startMinutes && end <= day.endMinutes;
  }

  bool get isNowWithinSchedule {
    final n = now;
    return _profile.dayFor(n.weekday).containsMinutes(n.hour * 60 + n.minute);
  }

  /// Texto corto del horario de disponibilidad, p. ej. «Lun–Sáb · 8:00 a.m.–7:00 p.m.».
  String get scheduleSummary {
    final enabled = _profile.schedule.where((d) => d.enabled).toList()
      ..sort((a, b) => a.weekday.compareTo(b.weekday));
    if (enabled.isEmpty) return 'Sin días activos';
    final sameHours = enabled.every((d) =>
        d.startMinutes == enabled.first.startMinutes &&
        d.endMinutes == enabled.first.endMinutes);
    final consecutive =
        enabled.last.weekday - enabled.first.weekday == enabled.length - 1;
    final days = enabled.length == 7
        ? 'Todos los días'
        : consecutive && enabled.length > 1
            ? '${Fmt.weekdayShort(enabled.first.weekday)}–${Fmt.weekdayShort(enabled.last.weekday)}'
            : enabled.map((d) => Fmt.weekdayShort(d.weekday)).join(', ');
    if (!sameHours) return '$days · horario variable';
    return '$days · ${Fmt.minutes(enabled.first.startMinutes)}–${Fmt.minutes(enabled.first.endMinutes)}';
  }

  // ════════════════════════════════════════════════════════════════
  // Consultas
  // ════════════════════════════════════════════════════════════════

  List<ServiceRequest> get requests => List.unmodifiable(_requests);

  ServiceRequest? byId(String id) {
    for (final r in _requests) {
      if (r.id == id) return r;
    }
    return null;
  }

  bool _passesPreferences(ServiceRequest r) {
    final p = _profile.preferences;
    if (r.space.distanceKm > p.maxDistanceKm) return false;
    if (p.onlyWithinSchedule && !isWithinSchedule(r)) return false;
    return true;
  }

  /// Oportunidades nuevas que cumplen las preferencias del trabajador.
  List<ServiceRequest> get availableRequests => _requests
      .where(
          (r) => r.status == RequestStatus.disponible && _passesPreferences(r))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Oportunidades ocultas por distancia u horario.
  int get hiddenByPreferences => _requests
      .where(
          (r) => r.status == RequestStatus.disponible && !_passesPreferences(r))
      .length;

  List<ServiceRequest> get negotiatingRequests =>
      _requests.where((r) => r.status.isNegotiating).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  /// Solicitudes recientes que ya no están disponibles (otro colaborador).
  List<ServiceRequest> get unavailableRequests => _requests
      .where((r) => r.takenByOther && r.scheduledAt.isAfter(now))
      .toList();

  /// Servicios en la agenda: con acuerdo, confirmados y en curso.
  List<ServiceRequest> get agendaRequests => _requests
      .where((r) => r.status == RequestStatus.aceptada || r.status.isScheduled)
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  ServiceRequest? get activeJob {
    for (final r in _requests) {
      if (r.status == RequestStatus.enCurso) return r;
    }
    return null;
  }

  /// Siguiente servicio confirmado (o el que está en curso).
  ServiceRequest? get nextService {
    final active = activeJob;
    if (active != null) return active;
    final upcoming = _requests
        .where((r) =>
            r.status == RequestStatus.confirmada && r.endsAt.isAfter(now))
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  List<ServiceRequest> get completedJobs =>
      _requests.where((r) => r.status == RequestStatus.finalizada).toList()
        ..sort((a, b) => (b.finishedAt ?? b.scheduledAt)
            .compareTo(a.finishedAt ?? a.scheduledAt));

  List<ServiceRequest> get closedRequests =>
      _requests.where((r) => r.status.isClosed).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  /// Solicitudes que esperan una acción del trabajador.
  List<ServiceRequest> get needsAction => _requests
      .where((r) =>
          r.status == RequestStatus.aceptada ||
          (r.status == RequestStatus.enNegociacion && r.clientOffer != null))
      .toList();

  double get totalEarnings =>
      completedJobs.fold(0, (sum, r) => sum + (r.agreedPrice ?? 0));

  double earningsBetween(DateTime start, DateTime end) =>
      completedJobs.where((r) {
        final d = r.finishedAt ?? r.scheduledAt;
        return !d.isBefore(start) && d.isBefore(end);
      }).fold(0, (sum, r) => sum + (r.agreedPrice ?? 0));

  int completedBetween(DateTime start, DateTime end) =>
      completedJobs.where((r) {
        final d = r.finishedAt ?? r.scheduledAt;
        return !d.isBefore(start) && d.isBefore(end);
      }).length;

  DateTime get weekStart {
    final n = now;
    final today = DateTime(n.year, n.month, n.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  /// Servicios de la semana actual (realizados, confirmados o en curso).
  int get servicesThisWeek {
    final start = weekStart;
    final end = start.add(const Duration(days: 7));
    return _requests
        .where((r) =>
            (r.status == RequestStatus.finalizada || r.status.isScheduled) &&
            !r.scheduledAt.isBefore(start) &&
            r.scheduledAt.isBefore(end))
        .length;
  }

  List<ServiceRequest> get receivedReviews =>
      completedJobs.where((r) => r.ratingReceived != null).toList();

  double get averageRating {
    final rated = receivedReviews;
    if (rated.isEmpty) return 0;
    return rated.fold<int>(0, (s, r) => s + r.ratingReceived!) / rated.length;
  }

  double get totalHoursWorked =>
      completedJobs.fold(0, (s, r) => s + r.durationHours);

  // ════════════════════════════════════════════════════════════════
  // Reglas de negocio (qué acciones están permitidas y por qué)
  // ════════════════════════════════════════════════════════════════

  ServiceRequest? _conflictWith(ServiceRequest r) {
    for (final other in _requests) {
      if (other.id == r.id || !other.status.isScheduled) continue;
      final overlaps = r.scheduledAt.isBefore(other.endsAt) &&
          other.scheduledAt.isBefore(r.endsAt);
      if (overlaps) return other;
    }
    return null;
  }

  /// Servicio confirmado que se empalma con [r], si existe.
  ServiceRequest? conflictFor(ServiceRequest r) => _conflictWith(r);

  ActionCheck canAccept(ServiceRequest r) {
    if (r.status != RequestStatus.disponible) {
      return const ActionCheck.no('Esta solicitud ya no está disponible.');
    }
    if (!_online) {
      return const ActionCheck.no(
          'Activa tu disponibilidad para aceptar solicitudes.');
    }
    if (!r.scheduledAt.isAfter(now)) {
      return const ActionCheck.no('La fecha de este servicio ya pasó.');
    }
    return const ActionCheck.ok();
  }

  ActionCheck canPropose(ServiceRequest r) {
    if (_isRemote(r)) {
      return const ActionCheck.no(
          'En las solicitudes reales el precio lo calcula QueLimpiamos: solo aceptas o rechazas.');
    }
    if (r.status == RequestStatus.enNegociacion ||
        r.status == RequestStatus.pendiente) {
      return const ActionCheck.ok();
    }
    if (r.status == RequestStatus.disponible) {
      return const ActionCheck.no(
          'Primero acepta la oportunidad para poder enviar una propuesta.');
    }
    if (r.status == RequestStatus.aceptada) {
      return const ActionCheck.no(
          'Ya existe un acuerdo de precio. Solo falta confirmar el servicio.');
    }
    return const ActionCheck.no(
        'La propuesta ya no se puede modificar en este estado.');
  }

  ActionCheck canConfirm(ServiceRequest r) {
    if (r.status != RequestStatus.aceptada || r.agreedPrice == null) {
      return const ActionCheck.no(
          'Para confirmar se necesita un acuerdo de precio con el cliente.');
    }
    if (!r.scheduledAt.isAfter(now)) {
      return const ActionCheck.no('La fecha de este servicio ya pasó.');
    }
    final conflict = _conflictWith(r);
    if (conflict != null) {
      return ActionCheck.no(
          'Se empalma con «${conflict.cleaningType}» del ${Fmt.date(conflict.scheduledAt)} a las ${Fmt.time(conflict.scheduledAt)}.');
    }
    return const ActionCheck.ok();
  }

  ActionCheck canStart(ServiceRequest r) {
    if (r.status != RequestStatus.confirmada) {
      return const ActionCheck.no('Solo puedes iniciar servicios confirmados.');
    }
    if (_isRemote(r)) {
      // Misma regla que el servidor: de 30 min antes a 30 min después de la hora programada.
      final desde = r.scheduledAt.subtract(const Duration(minutes: 30));
      final hasta = r.scheduledAt.add(const Duration(minutes: 30));
      if (now.isBefore(desde)) return ActionCheck.no('Podrás iniciar desde las ${Fmt.time(desde)}.');
      if (now.isAfter(hasta)) return const ActionCheck.no('Pasaron más de 30 min de la hora programada: ya no se puede iniciar. La administración revisará el caso.');
      return const ActionCheck.ok();
    }
    final active = activeJob;
    if (active != null) {
      return ActionCheck.no(
          'Primero finaliza «${active.cleaningType}», que está en curso.');
    }
    // Se puede iniciar desde el día programado (también si se va con retraso).
    if (Fmt.dayDiff(now, r.scheduledAt) > 0) {
      return ActionCheck.no(
          'Podrás iniciarlo el día del servicio (${Fmt.longDate(r.scheduledAt)}).');
    }
    return const ActionCheck.ok();
  }

  ActionCheck canFinish(ServiceRequest r) => r.status == RequestStatus.enCurso
      ? const ActionCheck.ok()
      : const ActionCheck.no(
          'El servicio debe estar en curso para finalizarlo.');

  ActionCheck canCancel(ServiceRequest r) {
    if (r.status == RequestStatus.aceptada ||
        r.status == RequestStatus.confirmada) {
      return const ActionCheck.ok();
    }
    if (r.status == RequestStatus.enCurso) {
      return const ActionCheck.no(
          'El servicio ya inició. Finalízalo para cerrarlo.');
    }
    return const ActionCheck.no('Este servicio no se puede cancelar.');
  }

  ActionCheck canChat(ServiceRequest r) {
    if (_isRemote(r)) {
      return const ActionCheck.no('El chat no está disponible en las solicitudes reales.');
    }
    if (r.status == RequestStatus.disponible) {
      return const ActionCheck.no(
          'El chat se habilita cuando aceptas la oportunidad.');
    }
    if (r.status.isClosed || r.status == RequestStatus.finalizada) {
      return const ActionCheck.no('La conversación está cerrada.');
    }
    return const ActionCheck.ok();
  }

  ActionCheck canRate(ServiceRequest r) {
    if (_isRemote(r)) {
      return const ActionCheck.no('Califica al cliente desde «Mis servicios» cuando el servicio quede realizado.');
    }
    if (r.status != RequestStatus.finalizada) {
      return const ActionCheck.no(
          'Solo puedes calificar servicios finalizados.');
    }
    if (r.clientRatingGiven != null) {
      return const ActionCheck.no('Ya calificaste a este cliente.');
    }
    return const ActionCheck.ok();
  }

  /// La dirección exacta solo se muestra con el servicio confirmado.
  bool showsExactAddress(ServiceRequest r) =>
      r.status.isScheduled || r.status == RequestStatus.finalizada;

  // ════════════════════════════════════════════════════════════════
  // Acciones sobre solicitudes
  // ════════════════════════════════════════════════════════════════

  ServiceRequest _require(String id) {
    final r = byId(id);
    if (r == null) throw StateError('Solicitud $id no encontrada');
    return r;
  }

  void _addMessage(ServiceRequest r, MessageKind kind, String text,
      {bool fromWorker = true,
      double? amount,
      String? imagePath,
      bool isAsset = false}) {
    r.messages.add(ChatMessage(
      id: _newId('m'),
      fromWorker: fromWorker,
      kind: kind,
      text: text,
      time: now,
      amount: amount,
      imagePath: imagePath,
      imageIsAsset: isAsset,
    ));
  }

  void _addNotification(NotificationType type, String title, String body,
      {String? requestId}) {
    _notifications.insert(
      0,
      AppNotification(
        id: _newId('n'),
        type: type,
        title: title,
        body: body,
        time: now,
        requestId: requestId,
        // Si las alertas están desactivadas se guardan como leídas.
        read: !_profile.preferences.notificationsEnabled,
      ),
    );
  }

  /// Aceptación de una oportunidad.
  ///
  /// - Solicitudes del backend (`api-…`): llama a `PATCH /hoyo-negro/:id/aceptar`.
  ///   Si sale bien queda **Confirmada** (agenda) con el `total` del cliente.
  ///   Si responde 409, la marca como tomada por otro colaborador.
  /// - Solicitudes locales (demo): abre la negociación como antes.
  ///
  /// Devuelve un mensaje de error o `null` si todo salió bien.
  Future<String?> acceptOpportunity(String id) async {
    final r = _require(id);
    final check = canAccept(r);
    if (!check.allowed) return check.reason;

    // ── Solicitud local (datos de demostración) ──
    if (!_isRemote(r)) {
      r.status = RequestStatus.enNegociacion;
      r.statusReason = null;
      _addMessage(r, MessageKind.system,
          'Aceptaste la oportunidad. Ya puedes conversar con el cliente.');
      _commit();
      return null;
    }

    // ── Solicitud del backend ──
    final wid = _workerId;
    final remoteId = _remoteId(r);
    if (wid == null || remoteId == null) {
      return 'Inicia sesión con tu cuenta de trabajador para aceptar.';
    }
    if (_accepting.contains(id)) return 'Procesando tu aceptación…';

    _accepting.add(id);
    try {
      await RequestsApi.aceptar(remoteId);
    } on ApiException catch (e) {
      if (e.codigo == 'SOLICITUD_YA_TOMADA' || e.codigo == 'SOLICITUD_VENCIDA') {
        r.status = RequestStatus.cancelada;
        r.statusReason = 'Tomada por otro colaborador.';
        _commit();
        return e.message;
      }
      return e.message;
    } catch (_) {
      return 'No se pudo conectar con el servidor.';
    } finally {
      _accepting.remove(id);
    }

    r.status = RequestStatus.confirmada;
    r.agreedPrice = r.estimateMin;
    r.statusReason = null;
    _addMessage(r, MessageKind.system,
        'Aceptaste el servicio por ${Fmt.money(r.agreedPrice!)}.');
    _addNotification(NotificationType.servicio, 'Servicio confirmado',
        '«${r.cleaningType}» quedó en tu agenda: ${Fmt.dateTime(r.scheduledAt)}.',
        requestId: id);
    _commit();
    return null;
  }

  // ── Acciones de las solicitudes REALES (van al servidor; devuelven el error o null) ──

  Future<String?> _remota(String id, Future<void> Function(int remoteId) llamada, void Function(ServiceRequest r) alTerminar) async {
    final r = _require(id);
    final remoteId = _remoteId(r);
    if (!_isRemote(r) || remoteId == null) return 'Esta acción es solo para solicitudes reales.';
    try {
      await llamada(remoteId);
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'No se pudo conectar con el servidor.';
    }
    alTerminar(r);
    _commit();
    return null;
  }

  /// Rechazar una invitación o una de la bolsa (definitivo).
  Future<String?> rejectRemote(String id) => _remota(id, RequestsApi.rechazar, (r) {
        r.status = RequestStatus.rechazada;
        r.statusReason = 'Rechazaste la solicitud.';
      });

  Future<String?> startRemote(String id) => _remota(id, (rid) => RequestsApi.iniciar(rid), (r) {
        r.status = RequestStatus.enCurso;
        r.startedAt = now;
      });

  /// «Terminado» con 1 a 5 fotos. Queda esperando la confirmación del cliente (D54).
  Future<String?> finishRemote(String id, List<FotoDeReporte> fotos) => _remota(id, (rid) => RequestsApi.terminar(rid, fotos), (r) {
        r.status = RequestStatus.finalizada;
        r.finishedAt = now;
        r.statusReason = 'Marcaste terminado: falta la confirmación del cliente.';
      });

  /// Cancelar sin cargo (24 h o más antes). Vuelve a la bolsa.
  Future<String?> cancelRemote(String id, String motivo) => _remota(id, (rid) => RequestsApi.cancelar(rid, motivo), (r) {
        r.status = RequestStatus.cancelada;
        r.statusReason = 'Cancelaste el servicio: volvió a la bolsa.';
      });

  void rejectRequest(String id, String reason) {
    final r = _require(id);
    r.status = RequestStatus.rechazada;
    r.statusReason = 'Rechazaste la solicitud: $reason';
    _commit();
  }

  /// Envía o edita la propuesta económica.
  String? sendProposal(String id, double amount, String note) {
    final r = _require(id);
    final check = canPropose(r);
    if (!check.allowed) return check.reason;
    final editing = r.status == RequestStatus.pendiente;
    r.proposal = Proposal(
      amount: amount,
      note: note.trim(),
      sentAt: now,
      version: (r.proposal?.version ?? 0) + 1,
    );
    r.clientOffer = null;
    r.status = RequestStatus.pendiente;
    r.statusReason = null;
    _addMessage(r, MessageKind.price,
        editing ? 'Propuesta actualizada' : 'Propuesta enviada',
        amount: amount);
    _commit();
    return null;
  }

  /// Simula la respuesta del cliente (solo para demostración local).
  void simulateClientResponse(String id, SimulatedResponse response) {
    final r = _require(id);
    if (r.status != RequestStatus.pendiente || r.proposal == null) return;
    final amount = r.proposal!.amount;
    final name = r.client.firstName.split(' ').first;
    switch (response) {
      case SimulatedResponse.acepta:
        r.agreedPrice = amount;
        r.status = RequestStatus.aceptada;
        r.statusReason = 'El cliente aceptó tu propuesta.';
        _addMessage(r, MessageKind.text, 'Acepto tu propuesta. ¡Gracias!',
            fromWorker: false);
        _addNotification(NotificationType.propuesta, 'Acuerdo de precio listo',
            '$name aceptó tu propuesta de ${Fmt.money(amount)}. Confirma el servicio para agregarlo a tu agenda.',
            requestId: id);
      case SimulatedResponse.contraoferta:
        final offer = ((amount * 0.88) / 10).round() * 10.0;
        r.clientOffer = offer < r.estimateMin ? r.estimateMin : offer;
        r.status = RequestStatus.enNegociacion;
        r.statusReason = null;
        _addMessage(r, MessageKind.price, 'Contraoferta del cliente',
            fromWorker: false, amount: r.clientOffer);
        _addNotification(NotificationType.propuesta, 'Contraoferta recibida',
            '$name propone ${Fmt.money(r.clientOffer!)} por «${r.cleaningType}».',
            requestId: id);
      case SimulatedResponse.rechaza:
        r.status = RequestStatus.rechazada;
        r.statusReason = 'El cliente rechazó la propuesta.';
        _addMessage(r, MessageKind.text,
            'Gracias, por ahora no podré aceptar la propuesta.',
            fromWorker: false);
        _addNotification(NotificationType.propuesta, 'Propuesta rechazada',
            '$name no aceptó tu propuesta para «${r.cleaningType}».',
            requestId: id);
    }
    _commit();
  }

  String? acceptCounterOffer(String id) {
    final r = _require(id);
    if (r.status != RequestStatus.enNegociacion || r.clientOffer == null) {
      return 'No hay una contraoferta vigente.';
    }
    r.agreedPrice = r.clientOffer;
    r.status = RequestStatus.aceptada;
    r.statusReason = 'Aceptaste la contraoferta del cliente.';
    _addMessage(r, MessageKind.system,
        'Aceptaste la contraoferta de ${Fmt.money(r.clientOffer!)}.');
    _commit();
    return null;
  }

  /// Confirmación definitiva: el servicio pasa a la agenda.
  String? confirmService(String id) {
    final r = _require(id);
    final check = canConfirm(r);
    if (!check.allowed) return check.reason;
    r.status = RequestStatus.confirmada;
    r.statusReason = null;
    _addMessage(r, MessageKind.system,
        'Confirmaste el servicio por ${Fmt.money(r.agreedPrice!)}.');
    _addNotification(NotificationType.servicio, 'Servicio confirmado',
        '«${r.cleaningType}» quedó en tu agenda: ${Fmt.dateTime(r.scheduledAt)}.',
        requestId: id);
    _commit();
    return null;
  }

  String? cancelService(String id, String reason) {
    final r = _require(id);
    final check = canCancel(r);
    if (!check.allowed) return check.reason;
    r.status = RequestStatus.cancelada;
    r.statusReason = 'Cancelaste el servicio: $reason';
    _addMessage(r, MessageKind.system, 'Cancelaste el servicio.');
    _commit();
    return null;
  }

  String? startJob(String id) {
    final r = _require(id);
    final check = canStart(r);
    if (!check.allowed) return check.reason;
    r.status = RequestStatus.enCurso;
    r.startedAt = now;
    _addMessage(r, MessageKind.system, 'Iniciaste el servicio.');
    _commit();
    return null;
  }

  String? finishJob(String id) {
    final r = _require(id);
    final check = canFinish(r);
    if (!check.allowed) return check.reason;
    r.status = RequestStatus.finalizada;
    r.finishedAt = now;
    _addMessage(r, MessageKind.system, 'Finalizaste el servicio.');
    _addNotification(NotificationType.servicio, 'Servicio finalizado',
        '«${r.cleaningType}» se agregó a tu historial (${Fmt.money(r.agreedPrice ?? 0)}). Califica al cliente cuando quieras.',
        requestId: id);
    _commit();
    return null;
  }

  String? rateClient(String id, int stars, String comment) {
    final r = _require(id);
    final check = canRate(r);
    if (!check.allowed) return check.reason;
    if (stars < 1 || stars > 5) return 'Selecciona de 1 a 5 escobas.';
    r.clientRatingGiven = stars;
    r.clientReviewGiven = comment.trim().isEmpty ? null : comment.trim();
    _commit();
    return null;
  }

  // ── Chat ──
  void sendMessage(String id, String text) {
    final r = _require(id);
    if (text.trim().isEmpty || !canChat(r).allowed) return;
    _addMessage(r, MessageKind.text, text.trim());
    _commit();
  }

  void shareLocation(String id) {
    final r = _require(id);
    if (!canChat(r).allowed) return;
    _addMessage(r, MessageKind.location, 'Ubicación compartida');
    _commit();
  }

  void sendPhoto(String id, String path) {
    final r = _require(id);
    if (!canChat(r).allowed) return;
    _addMessage(r, MessageKind.photo, 'Foto', imagePath: path);
    _commit();
  }

  // ════════════════════════════════════════════════════════════════
  // Notificaciones
  // ════════════════════════════════════════════════════════════════

  List<AppNotification> get notifications => List.unmodifiable(
      [..._notifications]..sort((a, b) => b.time.compareTo(a.time)));

  int get unreadCount => _notifications.where((n) => !n.read).length;

  void markNotificationRead(String id) {
    for (final n in _notifications) {
      if (n.id == id && !n.read) {
        n.read = true;
        _commit();
        return;
      }
    }
  }

  void markAllNotificationsRead() {
    if (unreadCount == 0) return;
    for (final n in _notifications) {
      n.read = true;
    }
    _commit();
  }

  void deleteNotification(String id) {
    _notifications.removeWhere((n) => n.id == id);
    _commit();
  }
}
