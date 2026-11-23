import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'app_bottom_nav.dart';
import 'collaborators_screen.dart';
import 'cotizacion_screen.dart';
import 'service_request_data.dart';

/// Perfil del colaborador con el botón «Enviar solicitud».
class CollaboratorProfileScreen extends StatelessWidget {
  const CollaboratorProfileScreen({
    super.key,
    required this.request,
    required this.collaborator,
  });

  final ServiceRequestData request;
  final Collaborator collaborator;

  void _enviarSolicitud(BuildContext context) {
    AppRoutes.push(
      context,
      CotizacionScreen(
        request: request.copyWith(collaborator: collaborator.nombre),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = collaborator;
    final pad = AppSpacing.screen(context);

    return Scaffold(
      extendBody: true,
      body: WaveBackground(
        headerHeight: 260,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              pad, 0, pad, AppBottomNav.reservedHeight(context)),
          children: [
            const StepHeader(title: '', step: 3),
            const SizedBox(height: 8),
            Center(
              child: FadeSlideIn(
                child:
                    BlobAvatar(seed: c.seed, initials: c.iniciales, size: 140),
              ),
            ),
            const SizedBox(height: 14),
            Text(c.nombre, textAlign: TextAlign.center, style: AppText.display),
            const SizedBox(height: 20),

            // ESPECIALIDADES
            FadeSlideIn(
              delay: FadeSlideIn.stagger(1),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Especialidades', style: AppText.heading),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final e in c.especialidades)
                          Pill(label: e, background: AppColors.ice),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // HORARIOS
            FadeSlideIn(
              delay: FadeSlideIn.stagger(2),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Horarios', style: AppText.heading),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.event_available_outlined,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.dias,
                            style: AppText.bodyStrong
                                .copyWith(color: AppColors.primaryStrong),
                          ),
                        ),
                        Text(
                          c.horario,
                          style: AppText.bodyStrong
                              .copyWith(color: AppColors.primaryStrong),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Enviar solicitud',
              icon: Icons.send_rounded,
              onPressed: () => _enviarSolicitud(context),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}
