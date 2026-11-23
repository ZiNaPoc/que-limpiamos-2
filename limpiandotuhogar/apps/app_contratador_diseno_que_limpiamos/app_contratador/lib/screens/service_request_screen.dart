import 'package:flutter/material.dart';

import '../data/service_catalog.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';
import 'schedule_dialog.dart';
import 'service_request_data.dart';

/// Paso 2: áreas, servicios extra y notas, con el precio estimado.
class ServiceRequestScreen extends StatefulWidget {
  const ServiceRequestScreen({
    super.key,
    required this.serviceTitle,
    required this.price,
    required this.image,
    required this.basePrice,
    this.property = const PropertyData(),
  });

  final String serviceTitle;
  final String price; // ej. "Desde $400"
  final String image;
  final int basePrice; // ej. 400

  /// Datos del inmueble y dirección capturados en «Datos del inmueble».
  final PropertyData property;

  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  static const List<String> areas = [
    'Cocina',
    'Sala',
    'Recámaras',
    'Baños',
    'Patio',
    'Áreas comunes',
  ];

  static const Map<String, int> extras = {
    'Limpieza de ventanas': 300,
    'Limpieza de estufa': 300,
    'Limpieza de refrigerador': 200,
    'Limpieza de alacena': 180,
    'Limpieza de cajonera': 150,
  };

  final Set<String> areasSel = {};
  final Set<String> extrasSel = {};
  final TextEditingController notasController = TextEditingController();

  @override
  void dispose() {
    notasController.dispose();
    super.dispose();
  }

  bool get _todaLaCasa => areasSel.length == areas.length;

  void _toggleArea(String area) {
    setState(() {
      if (areasSel.contains(area)) {
        areasSel.remove(area);
      } else {
        areasSel.add(area);
      }
    });
  }

  void _toggleTodaLaCasa() {
    setState(() {
      if (_todaLaCasa) {
        areasSel.clear();
      } else {
        areasSel.addAll(areas);
      }
    });
  }

  void _toggleExtra(String extra) {
    setState(() {
      if (extrasSel.contains(extra)) {
        extrasSel.remove(extra);
      } else {
        extrasSel.add(extra);
      }
    });
  }

  // Fórmula de ejemplo: base + $25 por área + extras (rango de +$100).
  // Ajústala cuando haya base de datos.
  int get _extrasTotal =>
      extrasSel.fold<int>(0, (suma, e) => suma + (extras[e] ?? 0));
  int get _precioMin => widget.basePrice + areasSel.length * 25 + _extrasTotal;
  int get _precioMax => _precioMin + 100;

  void _enviar() {
    if (areasSel.isEmpty) {
      showToast(context, 'Elige al menos un área para limpiar', error: true);
      return;
    }

    FocusScope.of(context).unfocus();

    final request = ServiceRequestData(
      serviceTitle: widget.serviceTitle,
      areas: areas.where(areasSel.contains).toList(),
      extras: extras.keys.where(extrasSel.contains).toList(),
      notes: notasController.text.trim(),
      priceMin: _precioMin,
      priceMax: _precioMax,
      extrasTotal: _extrasTotal,
      property: widget.property,
    );

    showAppDialog<void>(
      context,
      builder: (_) => ScheduleDialog(
        serviceTitle: widget.serviceTitle,
        price: widget.price,
        image: widget.image,
        request: request,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);

    return Scaffold(
      body: WaveBackground(
        headerHeight: 190,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                children: [
                  StepHeader(
                    title: widget.serviceTitle,
                    step: 2,
                    subtitle: 'Áreas y servicios extra',
                  ),
                  const SizedBox(height: 22),

                  // ÁREAS
                  Text('¿Qué áreas deseas limpiar?', style: AppText.heading),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final area in areas)
                        SelectChip(
                          label: area,
                          selected: areasSel.contains(area),
                          onTap: () => _toggleArea(area),
                        ),
                      SelectChip(
                        label: 'Toda la casa',
                        selected: _todaLaCasa,
                        icon: Icons.home_rounded,
                        onTap: _toggleTodaLaCasa,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // EXTRAS
                  Text('¿Desea un servicio extra?', style: AppText.heading),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final extra in extras.keys)
                        SelectChip(
                          label: '$extra ${money(extras[extra]!)}',
                          selected: extrasSel.contains(extra),
                          accent: true,
                          onTap: () => _toggleExtra(extra),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // NOTAS
                  Text('¿Hay algo que debemos saber?', style: AppText.heading),
                  const SizedBox(height: 10),
                  FlowTextArea(
                    controller: notasController,
                    hint:
                        'Mascotas, acceso al domicilio, productos de limpieza que prefieres...',
                    minLines: 4,
                    maxLines: 6,
                  ),
                ],
              ),
            ),

            // BARRA DE PRECIO
            PriceBar(
              min: _precioMin,
              max: _precioMax,
              actionLabel: 'Enviar solicitud',
              onAction: _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
