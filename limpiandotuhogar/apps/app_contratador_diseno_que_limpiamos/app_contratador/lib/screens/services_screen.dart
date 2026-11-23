import 'package:flutter/material.dart';

import '../data/service_catalog.dart';
import '../navigation/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';
import 'app_bottom_nav.dart';
import 'service_details_screen.dart';

/// «Servicios»: elige el tipo de limpieza.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  static const List<CleaningService> services = ServiceCatalog.services;

  void _abrirServicio(CleaningService service) {
    AppRoutes.push(context, ServiceDetailsScreen.fromService(service));
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);

    return Scaffold(
      extendBody: true,
      body: WaveBackground(
        headerHeight: 210,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, MediaQuery.paddingOf(context).top + 16,
              pad, AppBottomNav.reservedHeight(context)),
          children: [
            const TabHeader(
              title: 'Servicios',
              subtitle: 'Elige el tipo de limpieza que necesitas.',
            ),
            const SizedBox(height: 18),
            const _HowItWorks(),
            const SizedBox(height: 18),
            for (var i = 0; i < services.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FadeSlideIn(
                  delay: FadeSlideIn.stagger(i),
                  child: ServiceTile(
                    service: services[i],
                    onTap: () => _abrirServicio(services[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.home_work_outlined, 'Tu espacio'),
      (Icons.event_outlined, 'Fecha y hora'),
      (Icons.person_search_outlined, 'Colaborador'),
      (Icons.receipt_long_outlined, 'Cotización'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.fade(Colors.white, 0.75),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                        color: AppColors.ice, shape: BoxShape.circle),
                    child: Icon(steps[i].$1,
                        size: 18, color: AppColors.primaryStrong),
                  ),
                  const SizedBox(height: 4),
                  Text('${i + 1}. ${steps[i].$2}',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: AppText.caption.copyWith(
                          fontSize: 10.5, color: AppColors.inkSoft)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
