import 'package:flutter/material.dart';

/// Datos del inmueble que captura «Datos del inmueble». La solicitud guarda su PROPIA copia
/// (docs/backend/25 v2 §3): con [inmuebleId] se usa uno de «Mis inmuebles»; si no, se manda
/// el inmueble capturado y, con [guardarComo], además se guarda en «Mis inmuebles».
class PropertyData {
  const PropertyData({
    this.type = 'Casa',
    this.rooms = 0,
    this.fullBaths = 0,
    this.halfBaths = 0,
    this.floors = 1,
    this.address = '',
    this.inmuebleId,
    this.alias,
    this.guardarComo,
  });

  /// Inmueble guardado elegido (null = capturado en el formulario).
  final int? inmuebleId;

  /// Nombre del inmueble guardado (solo para mostrarlo).
  final String? alias;

  /// Si no es null, el inmueble capturado también se guarda con este nombre.
  final String? guardarComo;

  final String type; // 'Casa' | 'Oficina' | 'Departamento'
  final int rooms;
  final int fullBaths;
  final int halfBaths;
  final int floors;
  final String address;

  /// Valor que espera el backend: CASA | OFICINA | DEPARTAMENTO.
  String get apiType {
    switch (type) {
      case 'Oficina':
        return 'OFICINA';
      case 'Departamento':
        return 'DEPARTAMENTO';
      default:
        return 'CASA';
    }
  }
}

/// Datos de la solicitud que se van juntando a lo largo del flujo:
/// Servicios → Datos del inmueble → Áreas/extras → Horario → Colaborador → Cotización.
class ServiceRequestData {
  const ServiceRequestData({
    required this.serviceTitle,
    required this.areas,
    required this.extras,
    required this.notes,
    required this.priceMin,
    required this.priceMax,
    this.extrasTotal = 0,
    this.property = const PropertyData(),
    this.date,
    this.time,
    this.collaborator,
    this.collaboratorId,
  });

  final String serviceTitle;
  final List<String> areas;
  final List<String> extras;
  final String notes;
  final int priceMin;
  final int priceMax;

  /// Suma de los precios de los servicios extra elegidos.
  final int extrasTotal;

  /// Datos del inmueble y dirección del servicio.
  final PropertyData property;

  final DateTime? date;
  final TimeOfDay? time;
  final String? collaborator; // solo si lo eligió personalmente

  /// Id del colaborador elegido (se le manda la invitación). null = bolsa.
  final int? collaboratorId;

  ServiceRequestData copyWith({
    DateTime? date,
    TimeOfDay? time,
    String? collaborator,
    int? collaboratorId,
    int? precioServidor,
  }) {
    return ServiceRequestData(
      serviceTitle: serviceTitle,
      areas: areas,
      extras: extras,
      notes: notes,
      // El precio del SERVIDOR (D4) reemplaza la estimación de la app.
      priceMin: precioServidor ?? priceMin,
      priceMax: precioServidor ?? priceMax,
      extrasTotal: extrasTotal,
      property: property,
      date: date ?? this.date,
      time: time ?? this.time,
      collaborator: collaborator ?? this.collaborator,
      collaboratorId: collaboratorId ?? this.collaboratorId,
    );
  }

  /// Fecha y hora elegidas combinadas en un solo valor (hora local).
  DateTime? get scheduledAt {
    final d = date;
    final t = time;
    if (d == null || t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  /// dd/mm/aa
  String get dateText {
    final d = date;
    if (d == null) return '-';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy';
  }

  /// 10:00 am
  String get timeText {
    final t = time;
    if (t == null) return '-';
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final periodo = t.period == DayPeriod.am ? 'am' : 'pm';
    return '$h:$m $periodo';
  }
}