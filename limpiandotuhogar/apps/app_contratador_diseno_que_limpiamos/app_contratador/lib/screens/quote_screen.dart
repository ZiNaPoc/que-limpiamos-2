import 'package:flutter/material.dart';

import '../data/service_catalog.dart';
import '../services/api_client.dart'; // ApiException
import '../services/haptics.dart';
import '../services/session.dart'; // Session
import '../services/solicitud_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'service_request_data.dart';

/// Paso 4: resumen y precio estimado antes de confirmar.
class QuoteScreen extends StatefulWidget {
  const QuoteScreen({super.key, required this.request});

  final ServiceRequestData request;

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  bool _enviando = false;

  ServiceRequestData get request => widget.request;

  void _mostrar(String mensaje, {bool error = false}) {
    showToast(context, mensaje, error: error);
  }

  Future<void> _confirmar() async {
    if (_enviando) return; // evita dobles toques

    final user = Session.instance.user;
    if (user == null) {
      _mostrar('Inicia sesión con tu cuenta para enviar la solicitud.',
          error: true);
      return;
    }

    setState(() => _enviando = true);
    try {
      // Guarda el inmueble y la solicitud en la base de datos.
      await SolicitudApi.crear(request, clienteId: user.id);
      if (!mounted) return;
      Haptics.success(context);
      _mostrar('¡Solicitud confirmada!');
      // Por ahora se regresa al inicio para no enviar la misma solicitud dos veces.
      Navigator.popUntil(context, (route) => route.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      _mostrar(e.message, error: true);
    } catch (e, st) {
      debugPrint('[quote] ERROR inesperado: $e\n$st');
      if (!mounted) return;
      _mostrar('No se pudo enviar la solicitud. Intenta de nuevo.',
          error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _editar() {
    if (_enviando) return;
    // Regresa a la pantalla de áreas/extras con todo lo que ya había elegido
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
            const StepHeader(title: 'Tu cotización', step: 4),
            const SizedBox(height: 20),

            // RESUMEN
            FadeSlideIn(
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resumen', style: AppText.heading),
                    const SizedBox(height: 6),
                    SummaryRow('Tipo', request.serviceTitle),
                    SummaryRow('Inmueble', inmueble),
                    if (p.address.isNotEmpty) SummaryRow('Dirección', p.address),
                    SummaryRow('Áreas', request.areas.join(', ')),
                    SummaryRow('Servicios extras', extras),
                    SummaryRow('Notas', notas),
                    SummaryRow('Fecha', request.dateText),
                    SummaryRow('Hora', request.timeText),
                    SummaryRow('Colaborador',
                        request.collaborator ?? 'Asignación automática'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // PRECIO ESTIMADO
            FadeSlideIn(
              delay: FadeSlideIn.stagger(1),
              child: HeroPanel(
                seed: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Precio estimado',
                        style:
                            AppText.bodyStrong.copyWith(color: AppColors.ice)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          text:
                              '${money(request.priceMin)}-${money(request.priceMax).substring(1)}',
                          style: AppText.display
                              .copyWith(color: Colors.white, fontSize: 34),
                          children: [
                            TextSpan(
                              text: ' MXN',
                              style:
                                  AppText.label.copyWith(color: AppColors.ice),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Calculado según el tipo de limpieza y las áreas elegidas.',
                      style: AppText.caption.copyWith(color: AppColors.frost),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // AVISO
            const NoticeBox.success(
              message:
                  'El precio final lo confirma tu colaborador al revisar el servicio.',
            ),
            const SizedBox(height: 22),

            // BOTONES
            AppButton(
              label: 'Confirmar solicitud',
              icon: Icons.check_rounded,
              loading: _enviando,
              onPressed: _confirmar,
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Editar solicitud',
              icon: Icons.edit_outlined,
              variant: AppButtonVariant.outline,
              onPressed: _enviando ? null : _editar,
            ),
          ],
        ),
      ),
    );
  }
}
