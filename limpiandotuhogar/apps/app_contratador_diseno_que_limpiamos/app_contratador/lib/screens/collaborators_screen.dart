import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
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
    required this.nombre,
    required this.inicio,
    required this.fin,
    required this.dias,
    required this.especialidades,
  });

  final String nombre;
  final int inicio; // hora de entrada (formato 24 h)
  final int fin; // hora de salida (formato 24 h)
  final String dias;
  final List<String> especialidades;

  static String _hora(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final periodo = h < 12 ? 'am' : 'pm';
    return '$h12:00$periodo';
  }

  String get horario => '${_hora(inicio)}-${_hora(fin)}';

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

  // Datos de ejemplo, en lo que se agrega la base de datos
  static const List<Collaborator> colaboradores = [
    Collaborator(
      nombre: 'Ana López',
      inicio: 8,
      fin: 15,
      dias: 'Lunes-Sábado',
      especialidades: ['Limpieza profunda', 'Cocina'],
    ),
    Collaborator(
      nombre: 'Carlos Ruiz',
      inicio: 9,
      fin: 18,
      dias: 'Lunes-Sábado',
      especialidades: ['Limpieza regular', 'Baños'],
    ),
    Collaborator(
      nombre: 'María Pérez',
      inicio: 13,
      fin: 20,
      dias: 'Lunes-Viernes',
      especialidades: ['Limpieza post-obra', 'Patio'],
    ),
    Collaborator(
      nombre: 'Luis Hernández',
      inicio: 7,
      fin: 13,
      dias: 'Lunes-Sábado',
      especialidades: ['Limpieza regular', 'Recámaras'],
    ),
    Collaborator(
      nombre: 'Sofía Ramírez',
      inicio: 12,
      fin: 19,
      dias: 'Martes-Sábado',
      especialidades: ['Limpieza profunda', 'Áreas comunes'],
    ),
  ];

  String filtro = filtros.first;

  List<Collaborator> get _visibles {
    switch (filtro) {
      case 'Mañana':
        return colaboradores.where((c) => c.inicio < 12).toList();
      case 'Tarde':
        return colaboradores.where((c) => c.fin > 12).toList();
      default:
        return colaboradores;
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
            ChoiceChips<String>(
              options: filtros,
              selected: filtro,
              labelOf: (f) => f,
              onSelected: (f) => setState(() => filtro = f),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: AppDurations.medium,
              child: Column(
                key: ValueKey(filtro),
                children: [
                  if (visibles.isEmpty)
                    const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'No hay colaboradores en ese horario',
                      message: 'Prueba con otro horario.',
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
                const SizedBox(height: 2),
                Text(
                  'Horario: ${c.horario}',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 6),
                Pill(
                  label: c.dias,
                  icon: Icons.event_available_outlined,
                  background: AppColors.mint,
                  foreground: AppColors.successFg,
                  dense: true,
                ),
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
