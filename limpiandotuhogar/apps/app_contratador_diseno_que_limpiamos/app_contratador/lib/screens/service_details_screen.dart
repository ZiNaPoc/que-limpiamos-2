import 'package:flutter/material.dart';

import '../data/service_catalog.dart';
import '../navigation/app_routes.dart';
import '../services/ciclo_api.dart';
import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';
import 'service_request_data.dart';
import 'service_request_screen.dart';

/// Paso 1: datos del inmueble y dirección del servicio. Se puede elegir uno de «Mis inmuebles»
/// o capturar uno nuevo (y guardarlo con un nombre). La solicitud guarda su propia copia.
class ServiceDetailsScreen extends StatefulWidget {
  const ServiceDetailsScreen({
    super.key,
    required this.serviceTitle,
    required this.price,
    required this.image,
    required this.basePrice,
  });

  /// Abre el flujo a partir de un servicio del catálogo.
  factory ServiceDetailsScreen.fromService(CleaningService s, {Key? key}) =>
      ServiceDetailsScreen(
        key: key,
        serviceTitle: s.title,
        price: s.price,
        image: s.image,
        basePrice: s.basePrice,
      );

  final String serviceTitle;
  final String price; // ej. "Desde $400"
  final String image;
  final int basePrice; // ej. 400

  @override
  State<ServiceDetailsScreen> createState() => _ServiceDetailsScreenState();
}

class _ServiceDetailsScreenState extends State<ServiceDetailsScreen> {
  static const List<String> tiposCasa = ['Casa', 'Oficina', 'Departamento'];

  static const Map<String, IconData> _iconosTipo = {
    'Casa': Icons.house_outlined,
    'Oficina': Icons.business_outlined,
    'Departamento': Icons.apartment_outlined,
  };

  static const List<String> secciones = [
    'Número de habitaciones',
    'Número de baños completos',
    'Número de medios baños',
    'Número de pisos o niveles',
  ];

  // Mínimo de cada sección (los pisos empiezan en 1)
  static const List<int> minimos = [0, 0, 0, 1];
  static const int maximo = 20;

  String tipoCasa = 'Casa';
  final List<int> cantidades = [0, 0, 0, 1];
  final List<bool> abiertas = [true, false, false, false];
  final List<bool> confirmadas = [false, false, false, false];
  final TextEditingController direccionController = TextEditingController();

  // «Mis inmuebles»: el elegido se usa tal cual; si se cambia algún dato, pasa a ser uno nuevo.
  List<Inmueble> _guardados = const [];
  Inmueble? _elegido;

  @override
  void initState() {
    super.initState();
    direccionController.addListener(() {
      if (_elegido != null && direccionController.text != _elegido!.direccion) setState(() => _elegido = null);
    });
    InmueblesApi.listar().then((l) {
      if (mounted) setState(() => _guardados = l);
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    direccionController.dispose();
    super.dispose();
  }

  void _usarGuardado(Inmueble i) {
    setState(() {
      tipoCasa = i.tipoApp;
      cantidades.setAll(0, [i.habitaciones, i.banos, i.mediosBanos, i.pisos]);
      for (var k = 0; k < confirmadas.length; k++) {
        confirmadas[k] = true;
        abiertas[k] = false;
      }
      direccionController.text = i.direccion;
      _elegido = i;
    });
  }

  /// Pide el nombre con el que se guardará el inmueble (p. ej. «Casa Playa»).
  Future<String?> _pedirNombre() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar inmueble'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Airbnb Centro, Casa Playa'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    ctrl.dispose();
    return (nombre == null || nombre.isEmpty) ? null : nombre;
  }

  void _confirmar(int i) {
    setState(() {
      confirmadas[i] = true;
      abiertas[i] = false; // se oculta con animación
    });
  }

  Future<void> _continuar({required bool guardar}) async {
    final direccion = direccionController.text.trim();
    if (direccion.length < 5) {
      showToast(context, 'Escribe la dirección del servicio', error: true);
      return;
    }
    FocusScope.of(context).unfocus();

    // Guardar: se pide el nombre; el servidor lo guarda al crear la solicitud.
    String? guardarComo;
    if (guardar && _elegido == null) {
      guardarComo = await _pedirNombre();
      if (guardarComo == null || !mounted) return;
    } else if (guardar && _elegido != null) {
      showToast(context, 'Este inmueble ya está en «Mis inmuebles».', icon: Icons.info_outline_rounded);
    }
    if (!mounted) return;
    AppRoutes.push(
      context,
      ServiceRequestScreen(
        serviceTitle: widget.serviceTitle,
        price: widget.price,
        image: widget.image,
        basePrice: widget.basePrice,
        property: PropertyData(
          type: tipoCasa,
          rooms: cantidades[0],
          fullBaths: cantidades[1],
          halfBaths: cantidades[2],
          floors: cantidades[3],
          address: direccion,
          inmuebleId: _elegido?.id,
          alias: _elegido?.nombre ?? guardarComo,
          guardarComo: guardarComo,
        ),
      ),
      name: 'solicitud',
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);

    return Scaffold(
      body: WaveBackground(
        headerHeight: 200,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                children: [
                  StepHeader(
                    title: widget.serviceTitle,
                    step: 1,
                    subtitle: 'Datos del inmueble',
                  ),
                  const SizedBox(height: 20),
                  if (_guardados.isNotEmpty) ...[
                    Text('Mis inmuebles', style: AppText.heading),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final i in _guardados)
                          SelectChip(
                            label: i.nombre,
                            selected: _elegido?.id == i.id,
                            icon: Icons.bookmark_outline_rounded,
                            onTap: () => _usarGuardado(i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_elegido == null ? 'O captura uno nuevo abajo.' : 'Usarás «${_elegido!.nombre}». Si cambias un dato, se tomará como un inmueble nuevo.', style: AppText.caption),
                    const SizedBox(height: 20),
                  ],
                  Text('Tipo de casa', style: AppText.heading),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tipo in tiposCasa)
                        SelectChip(
                          label: tipo,
                          selected: tipoCasa == tipo,
                          icon: _iconosTipo[tipo],
                          onTap: () => setState(() {
                            if (tipoCasa != tipo) _elegido = null;
                            tipoCasa = tipo;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  for (int i = 0; i < secciones.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FadeSlideIn(
                        delay: FadeSlideIn.stagger(i),
                        child: _CounterTile(
                          label: secciones[i],
                          value: cantidades[i],
                          min: minimos[i],
                          max: maximo,
                          expanded: abiertas[i],
                          summary: confirmadas[i] ? '${cantidades[i]}' : null,
                          onToggle: () =>
                              setState(() => abiertas[i] = !abiertas[i]),
                          onChanged: (v) => setState(() {
                            cantidades[i] = v;
                            _elegido = null;
                          }),
                          onDone: () => _confirmar(i),
                        ),
                      ),
                    ),

                  // DIRECCIÓN
                  const SizedBox(height: 10),
                  Text('Dirección del servicio', style: AppText.heading),
                  const SizedBox(height: 10),
                  FlowTextArea(
                    controller: direccionController,
                    hint: 'Calle, número, colonia o SM...',
                    minLines: 2,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: 'Continuar',
                        variant: AppButtonVariant.outline,
                        height: 48,
                        onPressed: () => _continuar(guardar: false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: AppButton(
                        label: 'Continuar y guardar',
                        height: 48,
                        onPressed: () => _continuar(guardar: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila desplegable con selector numérico.
class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
    required this.onDone,
    this.summary,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<int> onChanged;
  final VoidCallback onDone;

  /// Valor elegido; se ve cuando la tarjeta está cerrada.
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return AnimatedContainer(
      duration: AppDurations.medium,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: expanded ? AppColors.primary : AppColors.divider, width: 1.2),
        boxShadow: expanded ? AppShadows.lifted : AppShadows.soft,
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: AppText.subtitle)),
                  AnimatedSwitcher(
                    duration: AppDurations.fast,
                    transitionBuilder: (c, a) =>
                        ScaleTransition(scale: a, child: c),
                    child: expanded || s == null
                        ? const SizedBox.shrink()
                        : Container(
                            key: ValueKey(s),
                            constraints: const BoxConstraints(minWidth: 32),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.ice,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(s, style: AppText.label),
                          ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: AppDurations.medium,
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppDurations.medium,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Row(
                      children: [
                        _StepButton(
                          icon: Icons.remove_rounded,
                          onTap: value > min ? () => onChanged(value - 1) : null,
                        ),
                        SizedBox(
                          width: 56,
                          child: AnimatedSwitcher(
                            duration: AppDurations.fast,
                            transitionBuilder: (c, a) => FadeTransition(
                              opacity: a,
                              child: ScaleTransition(scale: a, child: c),
                            ),
                            child: Text('$value',
                                key: ValueKey(value),
                                textAlign: TextAlign.center,
                                style: AppText.title),
                          ),
                        ),
                        _StepButton(
                          icon: Icons.add_rounded,
                          onTap: value < max ? () => onChanged(value + 1) : null,
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: onDone,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryStrong,
                            shape: const StadiumBorder(),
                            minimumSize: const Size(64, 40),
                          ),
                          child: Text('Ok',
                              style:
                                  AppText.label.copyWith(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.ice : AppColors.cloud,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled
            ? () {
                Haptics.tap(context);
                onTap!();
              }
            : null,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon,
              color: enabled ? AppColors.primaryStrong : AppColors.inkMuted),
        ),
      ),
    );
  }
}
