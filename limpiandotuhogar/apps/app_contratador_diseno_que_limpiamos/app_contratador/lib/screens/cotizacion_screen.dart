import 'package:flutter/material.dart';

import '../data/service_catalog.dart';
import '../navigation/app_routes.dart';
import '../services/ciclo_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'pago_screen.dart';
import 'service_request_data.dart';

/// Paso 4: cotización.
///
/// Se llega aquí de dos formas:
///  * Después de elegir un colaborador en su perfil (`request.collaborator`
///    trae su nombre).
///  * Después de elegir «Asignación automática» (`request.collaborator` es
///    `null`).
///
/// «Continuar al pago» lleva a [PagoScreen].
///
/// El precio y la duración los calcula el SERVIDOR (POST /api/cliente/cotizaciones, D4): la
/// cotización no crea nada. Mientras no llegue, no se puede continuar.
class CotizacionScreen extends StatefulWidget {
  const CotizacionScreen({super.key, required this.request});

  final ServiceRequestData request;

  @override
  State<CotizacionScreen> createState() => _CotizacionScreenState();
}

class _CotizacionScreenState extends State<CotizacionScreen> {
  late ServiceRequestData request = widget.request;
  Cotizacion? _cotizacion;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cotizar();
  }

  Future<void> _cotizar() async {
    setState(() => _error = null);
    try {
      final c = await CicloApi.cotizar(widget.request);
      if (!mounted) return;
      setState(() {
        _cotizacion = c;
        request = widget.request.copyWith(precioServidor: c.total.round());
      });
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDelCiclo(e));
    }
  }

  void _continuarAlPago(BuildContext context) {
    AppRoutes.push(context, PagoScreen(request: request));
  }

  void _editar(BuildContext context) {
    // Regresa a la pantalla de áreas/extras con todo lo que ya había elegido.
    Navigator.popUntil(
      context,
      (route) => route.settings.name == 'solicitud' || route.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) {
    final extras =
        request.extras.isEmpty ? 'Ninguno' : request.extras.join(', ');
    final notas = request.notes.isEmpty ? 'Sin notas' : request.notes;
    final p = request.property;
    final inmueble = [
      p.type,
      '${p.rooms} hab.',
      '${p.fullBaths} baño${p.fullBaths == 1 ? '' : 's'}',
      if (p.halfBaths > 0) '${p.halfBaths} medio${p.halfBaths == 1 ? '' : 's'}',
      '${p.floors} nivel${p.floors == 1 ? '' : 'es'}',
    ].join(' · ');
    final pad = AppSpacing.screen(context);

    return Scaffold(
      body: WaveBackground(
        headerHeight: 190,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              pad, 0, pad, MediaQuery.paddingOf(context).bottom + 24),
          children: [
            const StepHeader(
              title: 'Tu cotización',
              step: 4,
              subtitle: 'Revisa tu solicitud antes de pagar.',
            ),
            const SizedBox(height: 20),

            // COLABORADOR (elegido o automático)
            FadeSlideIn(child: _ColaboradorCard(request: request)),
            const SizedBox(height: 12),

            // RESUMEN
            FadeSlideIn(
              delay: FadeSlideIn.stagger(1),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resumen', style: AppText.heading),
                    const SizedBox(height: 6),
                    SummaryRow('Tipo', request.serviceTitle),
                    SummaryRow('Inmueble', inmueble),
                    if (p.address.isNotEmpty)
                      SummaryRow('Dirección', p.address),
                    SummaryRow('Áreas', request.areas.join(', ')),
                    SummaryRow('Servicios extras', extras),
                    SummaryRow('Notas', notas),
                    SummaryRow('Fecha', request.dateText),
                    SummaryRow('Hora', request.timeText),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // PRECIO ESTIMADO + DESGLOSE
            if (_error != null)
              NoticeBox.error(message: _error!, action: AppLinkButton(label: 'Reintentar', onPressed: _cotizar))
            else if (_cotizacion == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else
              FadeSlideIn(
                delay: FadeSlideIn.stagger(2),
                child: _PrecioPanel(request: request, cotizacion: _cotizacion!),
              ),
            const SizedBox(height: 12),

            // AVISO
            const NoticeBox.success(
              message:
                  'El precio lo calcula QueLimpiamos (servicio + extras). Pagas en efectivo al terminar.',
            ),
            const SizedBox(height: 22),

            // BOTONES
            AppButton(
              label: 'Continuar al pago',
              icon: Icons.payments_outlined,
              onPressed: _cotizacion == null ? null : () => _continuarAlPago(context),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Editar solicitud',
              icon: Icons.edit_outlined,
              variant: AppButtonVariant.outline,
              onPressed: () => _editar(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta con el colaborador elegido o con la asignación automática.
class _ColaboradorCard extends StatelessWidget {
  const _ColaboradorCard({required this.request});

  final ServiceRequestData request;

  static String _iniciales(String nombre) {
    final partes =
        nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final nombre = request.collaborator ?? '';
    final manual = request.collaborator != null;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: [
          BlobAvatar(
            seed: manual ? nombre.codeUnits.fold<int>(0, (a, b) => a + b) : 3,
            initials: manual ? _iniciales(nombre) : '',
            icon: manual ? null : Icons.auto_awesome,
            size: 58,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(manual ? 'Tu colaborador' : 'Colaborador',
                    style: AppText.caption),
                Text(
                  manual ? nombre : 'Bolsa abierta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heading,
                ),
                const SizedBox(height: 2),
                Text(
                  manual
                      ? 'Le enviaremos tu solicitud para que la confirme.'
                      : 'La verán los colaboradores disponibles; el primero que acepte la atiende.',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Pill(
            label: manual ? 'Elegido por ti' : 'Más rápido',
            icon: manual ? Icons.check_rounded : Icons.bolt_rounded,
            background: manual ? AppColors.ice : AppColors.mint,
            foreground: manual ? AppColors.primaryStrong : AppColors.successFg,
            dense: true,
          ),
        ],
      ),
    );
  }
}

/// Precio del SERVIDOR con su desglose (servicio + extras, D4).
class _PrecioPanel extends StatelessWidget {
  const _PrecioPanel({required this.request, required this.cotizacion});

  final ServiceRequestData request;
  final Cotizacion cotizacion;

  @override
  Widget build(BuildContext context) {
    final total = cotizacion.total.round();
    final extras = cotizacion.extras.round();
    final base = cotizacion.base.round();
    final horas = (cotizacion.duracionMin / 60).toStringAsFixed(cotizacion.duracionMin % 60 == 0 ? 0 : 1);

    return HeroPanel(
      seed: 11,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Precio',
              style: AppText.bodyStrong.copyWith(color: AppColors.ice)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                text: money(total),
                style: AppText.display
                    .copyWith(color: Colors.white, fontSize: 34),
                children: [
                  TextSpan(
                    text: ' MXN',
                    style: AppText.label.copyWith(color: AppColors.ice),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Calculado por QueLimpiamos. Duración estimada: $horas h.',
            style: AppText.caption.copyWith(color: AppColors.frost),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: BoxDecoration(
              color: AppColors.fade(Colors.white, 0.94),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              children: [
                _LineaPrecio(
                  request.serviceTitle,
                  money(base),
                ),
                _LineaPrecio(
                  'Servicios extra',
                  extras > 0 ? money(extras) : r'$0',
                ),
                const Divider(height: 14, color: AppColors.divider),
                _LineaPrecio(
                  'Total (efectivo)',
                  money(total),
                  fuerte: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineaPrecio extends StatelessWidget {
  const _LineaPrecio(this.label, this.value, {this.fuerte = false});

  final String label;
  final String value;
  final bool fuerte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: fuerte
                  ? AppText.bodyStrong.copyWith(fontWeight: FontWeight.w700)
                  : AppText.body.copyWith(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: fuerte
                ? AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryStrong)
                : AppText.bodyStrong.copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }
}