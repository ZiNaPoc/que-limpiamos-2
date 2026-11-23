import 'package:flutter/material.dart';

import '../data/service_catalog.dart';
import '../navigation/app_routes.dart';
import '../services/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'app_bottom_nav.dart';
import 'historial_screen.dart';
import 'service_details_screen.dart';
import 'services_screen.dart';

/// Inicio: búsqueda, saludo y paquetes populares.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.userName = 'Usuario'});

  final String userName;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _packages = PageController(viewportFraction: 0.78);
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _packages.dispose();
    super.dispose();
  }

  /// Nombre de la sesión activa (también al volver por la barra inferior).
  String get _nombre => Session.instance.user?.nombre ?? widget.userName;

  void openServices() {
    AppRoutes.push(context, const ServicesScreen());
  }

  void _openService(CleaningService s) {
    AppRoutes.push(context, ServiceDetailsScreen.fromService(s));
  }

  void _clearSearch() {
    _search.clear();
    _searchFocus.unfocus();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);
    final results = ServiceCatalog.search(_query);
    final popular = ServiceCatalog.popular;

    return Scaffold(
      extendBody: true,
      body: WaveBackground(
        headerHeight: 250,
        child: ListView(
          padding: EdgeInsets.fromLTRB(0, MediaQuery.paddingOf(context).top + 12,
              0, AppBottomNav.reservedHeight(context)),
          children: [
            // BUSCADOR
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Row(
                children: [
                  Expanded(
                    child: _SearchField(
                      controller: _search,
                      focusNode: _searchFocus,
                      onChanged: (v) => setState(() => _query = v),
                      onClear: _clearSearch,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const AppLogo(size: 46),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: AnimatedSize(
                duration: AppDurations.medium,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _query.trim().isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          boxShadow: AppShadows.lifted,
                        ),
                        child: Column(
                          children: [
                            if (results.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(18),
                                child: Text(
                                    'No encontramos «${_query.trim()}». Prueba con «profunda» o «regular».',
                                    style: AppText.body),
                              ),
                            for (final s in results)
                              ListTile(
                                leading: ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  child: SizedBox(
                                    width: 46,
                                    height: 46,
                                    child: ServiceImage(
                                        path: s.image, cacheWidth: 150),
                                  ),
                                ),
                                title: Text(s.title, style: AppText.bodyStrong),
                                subtitle:
                                    Text(s.price, style: AppText.caption),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.primaryStrong),
                                onTap: () {
                                  _clearSearch();
                                  _openService(s);
                                },
                              ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),

            // HISTORIAL
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Align(
                alignment: Alignment.centerLeft,
                child: HistoryChip(
                  onPressed: () =>
                      AppRoutes.push(context, const HistorialScreen()),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // SALUDO
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: FadeSlideIn(
                child: HeroPanel(
                  seed: 7,
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hola, $_nombre',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              AppText.subtitle.copyWith(color: AppColors.ice)),
                      const SizedBox(height: 6),
                      Text('¿Qué deseas\nlimpiar?',
                          style: AppText.display
                              .copyWith(color: Colors.white, fontSize: 28)),
                      const SizedBox(height: 16),
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          onTap: openServices,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 11, 12, 11),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Solicitar una limpieza',
                                    style: AppText.label
                                        .copyWith(color: AppColors.ink)),
                                const SizedBox(width: 6),
                                const Icon(Icons.arrow_forward_rounded,
                                    size: 18, color: AppColors.primaryStrong),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),

            // PAQUETES
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Text('Paquetes más populares', style: AppText.heading),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 236,
              child: PageView.builder(
                controller: _packages,
                padEnds: false,
                itemCount: popular.length,
                itemBuilder: (context, i) => AnimatedBuilder(
                  animation: _packages,
                  builder: (context, child) {
                    // Las tarjetas laterales se reducen un poco: da profundidad.
                    var scale = 1.0;
                    if (_packages.hasClients &&
                        _packages.position.haveDimensions &&
                        _packages.page != null) {
                      scale = (1 - (_packages.page! - i).abs() * 0.08)
                          .clamp(0.9, 1.0)
                          .toDouble();
                    }
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: i == 0 ? pad : 6, right: 6, bottom: 12, top: 4),
                    child: PackageCard(
                      service: popular[i],
                      onTap: () => _openService(popular[i]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: AppColors.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: AppText.bodyStrong,
              decoration: InputDecoration(
                hintText: 'Buscar',
                hintStyle: AppText.body,
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 8)
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.inkMuted),
                  ),
          ),
        ],
      ),
    );
  }
}
