import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/ciclo_api.dart';
import '../services/historial_api.dart';
import '../services/validaciones_contenido.dart';
import '../widgets/buttons.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'app_bottom_nav.dart';
import 'collaborator_profile_screen.dart';
import 'service_request_data.dart';

class Collaborator {
  const Collaborator({
    this.id,
    required this.nombre,
    this.inicio,
    this.fin,
    this.dias,
    required this.especialidades,
    this.promedio,
    this.cantidadResenas = 0,
  });

  /// Trabajador real de GET /api/cliente/trabajadores (activo y verificado).
  factory Collaborator.desdeApi(TrabajadorSeleccionable t) => Collaborator(
        id: t.id,
        nombre: t.nombre,
        especialidades: t.especialidades,
        promedio: t.reputacion.promedio,
        cantidadResenas: t.reputacion.cantidad,
      );

  final int? id;
  final String nombre;
  final int? inicio; // hora de entrada (24 h); null si el backend no la da
  final int? fin; // hora de salida (24 h)
  final String? dias;
  final List<String> especialidades;

  /// Promedio de reseñas válidas (null = sin calificaciones).
  final double? promedio;
  final int cantidadResenas;

  bool get tieneHorario => inicio != null && fin != null;

  static String _hora(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final periodo = h < 12 ? 'am' : 'pm';
    return '$h12:00$periodo';
  }

  String get horario => tieneHorario ? '${_hora(inicio!)}-${_hora(fin!)}' : 'Se confirma al solicitar';

  /// «AL» para «Ana López».
  String get iniciales {
    final partes =
        nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  /// Semilla estable para la forma y el color del avatar.
  int get seed => nombre.codeUnits.fold<int>(0, (a, b) => a + b);
}

class CollaboratorsScreen extends StatefulWidget {
  const CollaboratorsScreen({super.key, required this.request});

  final ServiceRequestData request;

  @override
  State<CollaboratorsScreen> createState() => _CollaboratorsScreenState();
}

class _CollaboratorsScreenState extends State<CollaboratorsScreen> {
  static const List<String> filtros = ['Cualquier horario', 'Mañana', 'Tarde'];

  List<Collaborator>? colaboradores;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      // Elegibles para ESTE servicio y ESTA fecha (especialidades y sin traslapes).
      final cat = await Catalogo.obtener();
      final lista = await HistorialApi.trabajadores(servicioId: cat.servicioId(widget.request.serviceTitle), fecha: widget.request.scheduledAt);
      if (mounted) setState(() => colaboradores = lista.map(Collaborator.desdeApi).toList());
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  String filtro = filtros.first;

  /// El filtro por horario solo aplica si el backend entrega horarios (hoy no).
  bool get _hayHorarios => (colaboradores ?? const []).any((c) => c.tieneHorario);

  List<Collaborator> get _visibles {
    final todos = colaboradores ?? const <Collaborator>[];
    switch (filtro) {
      case 'Mañana':
        return todos.where((c) => !c.tieneHorario || c.inicio! < 12).toList();
      case 'Tarde':
        return todos.where((c) => !c.tieneHorario || c.fin! > 12).toList();
      default:
        return todos;
    }
  }

  void _abrirPerfil(Collaborator c) {
    AppRoutes.push(
      context,
      CollaboratorProfileScreen(request: widget.request, collaborator: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final pad = AppSpacing.screen(context);
    final req = widget.request;

    return Scaffold(
      extendBody: true,
      body: WaveBackground(
        headerHeight: 200,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              pad, 0, pad, AppBottomNav.reservedHeight(context)),
          children: [
            const StepHeader(
              title: 'Colaboradores',
              step: 3,
              subtitle: 'Elige a tu colaborador',
            ),
            if (req.date != null && req.time != null) ...[
              const SizedBox(height: 6),
              Text(
                'Para el ${req.dateText} a las ${req.timeText}',
                style: AppText.caption.copyWith(color: AppColors.ink),
              ),
            ],
            const SizedBox(height: 14),
            if (_hayHorarios) ...[
              ChoiceChips<String>(
                options: filtros,
                selected: filtro,
                labelOf: (f) => f,
                onSelected: (f) => setState(() => filtro = f),
              ),
              const SizedBox(height: 16),
            ],
            if (_error != null) NoticeBox.error(message: _error!, action: AppLinkButton(label: 'Reintentar', onPressed: _cargar)),
            if (colaboradores == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: Column(
                key: ValueKey(filtro),
                children: [
                  if (colaboradores != null && visibles.isEmpty)
                    const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'No hay colaboradores disponibles',
                      message: 'Por ahora no hay colaboradores verificados. Puedes elegir la asignación automática.',
                    ),
                  for (var i = 0; i < visibles.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: FadeSlideIn(
                        delay: FadeSlideIn.stagger(i),
                        child: _CollaboratorCard(
                          collaborator: visibles[i],
                          onTap: () => _abrirPerfil(visibles[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

class _CollaboratorCard extends StatelessWidget {
  const _CollaboratorCard({required this.collaborator, required this.onTap});

  final Collaborator collaborator;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = collaborator;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      child: Row(
        children: [
          BlobAvatar(seed: c.seed, initials: c.iniciales, size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.heading),
                const SizedBox(height: 4),
                EstrellasDeColaborador(promedio: c.promedio, cantidad: c.cantidadResenas),
                if (c.tieneHorario) ...[
                  const SizedBox(height: 2),
                  Text('Horario: ${c.horario}', style: AppText.caption.copyWith(color: AppColors.inkSoft)),
                ],
                if (c.dias != null) ...[
                  const SizedBox(height: 6),
                  Pill(label: c.dias!, icon: Icons.event_available_outlined, background: AppColors.mint, foreground: AppColors.successFg, dense: true),
                ] else if (c.especialidades.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(c.especialidades.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.primaryStrong, size: 28),
        ],
      ),
    );
  }
}

/// Estrellas (escobas) con el promedio y la cantidad de reseñas; "Sin calificaciones" si no hay.
class EstrellasDeColaborador extends StatelessWidget {
  const EstrellasDeColaborador({super.key, required this.promedio, required this.cantidad, this.size = 16});

  final double? promedio;
  final int cantidad;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = promedio;
    if (p == null) return Text('Sin calificaciones', style: AppText.caption);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BroomRating(value: p.round(), size: size),
        const SizedBox(width: 6),
        Text('${p.toStringAsFixed(1)} ($cantidad)', style: AppText.caption.copyWith(color: AppColors.ink)),
      ],
    );
  }
}
