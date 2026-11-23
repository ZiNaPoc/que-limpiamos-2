/// Perfil del trabajador, horario de disponibilidad y preferencias.
library;

enum IneStatus {
  verificada('Verificada'),
  enRevision('En revisión');

  const IneStatus(this.label);
  final String label;
}

/// Horario de un día. Las horas se guardan en minutos desde medianoche.
class DaySchedule {
  const DaySchedule({
    required this.weekday,
    required this.enabled,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// 1 = lunes … 7 = domingo (igual que [DateTime.weekday]).
  final int weekday;
  final bool enabled;
  final int startMinutes;
  final int endMinutes;

  DaySchedule copyWith({bool? enabled, int? startMinutes, int? endMinutes}) =>
      DaySchedule(
        weekday: weekday,
        enabled: enabled ?? this.enabled,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );

  bool containsMinutes(int minutes) =>
      enabled && minutes >= startMinutes && minutes < endMinutes;

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'enabled': enabled,
        'start': startMinutes,
        'end': endMinutes,
      };

  factory DaySchedule.fromJson(Map<String, dynamic> j) => DaySchedule(
        weekday: j['weekday'] as int,
        enabled: j['enabled'] as bool,
        startMinutes: j['start'] as int,
        endMinutes: j['end'] as int,
      );
}

class WorkerPreferences {
  const WorkerPreferences({
    this.notificationsEnabled = true,
    this.soundsEnabled = true,
    this.maxDistanceKm = 10,
    this.onlyWithinSchedule = false,
  });

  final bool notificationsEnabled;
  final bool soundsEnabled;
  final double maxDistanceKm;

  /// Si está activo, solo se muestran solicitudes dentro del horario.
  final bool onlyWithinSchedule;

  WorkerPreferences copyWith({
    bool? notificationsEnabled,
    bool? soundsEnabled,
    double? maxDistanceKm,
    bool? onlyWithinSchedule,
  }) =>
      WorkerPreferences(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        soundsEnabled: soundsEnabled ?? this.soundsEnabled,
        maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
        onlyWithinSchedule: onlyWithinSchedule ?? this.onlyWithinSchedule,
      );

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'soundsEnabled': soundsEnabled,
        'maxDistanceKm': maxDistanceKm,
        'onlyWithinSchedule': onlyWithinSchedule,
      };

  factory WorkerPreferences.fromJson(Map<String, dynamic> j) =>
      WorkerPreferences(
        notificationsEnabled: (j['notificationsEnabled'] as bool?) ?? true,
        soundsEnabled: (j['soundsEnabled'] as bool?) ?? true,
        maxDistanceKm: ((j['maxDistanceKm'] as num?) ?? 10).toDouble(),
        onlyWithinSchedule: (j['onlyWithinSchedule'] as bool?) ?? false,
      );
}

class WorkerProfile {
  const WorkerProfile({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.password,
    required this.specialties,
    required this.ineStatus,
    required this.memberSince,
    required this.schedule,
    this.photoPath,
    this.ineFrontPath,
    this.ineBackPath,
    this.preferences = const WorkerPreferences(),
  });

  final String firstName;
  final String lastName;
  final String email;
  final String phone;

  /// Solo para la sesión local simulada; no existe autenticación real.
  final String password;
  final List<String> specialties;
  final IneStatus ineStatus;
  final DateTime memberSince;
  final List<DaySchedule> schedule;
  final String? photoPath;
  final String? ineFrontPath;
  final String? ineBackPath;
  final WorkerPreferences preferences;

  String get fullName => '$firstName $lastName'.trim();

  DaySchedule dayFor(int weekday) =>
      schedule.firstWhere((d) => d.weekday == weekday,
          orElse: () => DaySchedule(
              weekday: weekday,
              enabled: false,
              startMinutes: 480,
              endMinutes: 1080));

  WorkerProfile copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? password,
    List<String>? specialties,
    IneStatus? ineStatus,
    List<DaySchedule>? schedule,
    String? photoPath,
    String? ineFrontPath,
    String? ineBackPath,
    WorkerPreferences? preferences,
  }) =>
      WorkerProfile(
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        password: password ?? this.password,
        specialties: specialties ?? this.specialties,
        ineStatus: ineStatus ?? this.ineStatus,
        memberSince: memberSince,
        schedule: schedule ?? this.schedule,
        photoPath: photoPath ?? this.photoPath,
        ineFrontPath: ineFrontPath ?? this.ineFrontPath,
        ineBackPath: ineBackPath ?? this.ineBackPath,
        preferences: preferences ?? this.preferences,
      );

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'password': password,
        'specialties': specialties,
        'ineStatus': ineStatus.name,
        'memberSince': memberSince.toIso8601String(),
        'schedule': schedule.map((d) => d.toJson()).toList(),
        'photoPath': photoPath,
        'ineFrontPath': ineFrontPath,
        'ineBackPath': ineBackPath,
        'preferences': preferences.toJson(),
      };

  factory WorkerProfile.fromJson(Map<String, dynamic> j) => WorkerProfile(
        firstName: j['firstName'] as String,
        lastName: j['lastName'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
        password: j['password'] as String,
        specialties: List<String>.from(j['specialties'] as List),
        ineStatus: IneStatus.values.byName(j['ineStatus'] as String),
        memberSince: DateTime.parse(j['memberSince'] as String),
        schedule: (j['schedule'] as List)
            .map((d) => DaySchedule.fromJson(d as Map<String, dynamic>))
            .toList(),
        photoPath: j['photoPath'] as String?,
        ineFrontPath: j['ineFrontPath'] as String?,
        ineBackPath: j['ineBackPath'] as String?,
        preferences: j['preferences'] == null
            ? const WorkerPreferences()
            : WorkerPreferences.fromJson(
                j['preferences'] as Map<String, dynamic>),
      );
}
