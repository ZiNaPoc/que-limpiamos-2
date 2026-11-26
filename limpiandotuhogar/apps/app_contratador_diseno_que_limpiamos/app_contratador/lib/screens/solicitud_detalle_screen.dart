import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ciclo_api.dart';
import '../services/historial_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';

/// Detalle de UNA solicitud del cliente (docs/backend/25 v2). Se actualiza cada 15 s mientras
/// está abierta. Las acciones las decide el servidor (`acciones`):
///  - tras un rechazo: enviar a la bolsa o invitar a otro colaborador;
///  - cancelar (sin cargo: pendiente, o confirmada con 24 h o más);
///  - confirmar que se realizó, viendo las fotos del colaborador.
/// Sin chat en las solicitudes reales.
class SolicitudDetalleScreen extends StatefulWidget {
  const SolicitudDetalleScreen({super.key, required this.solicitudId});

  final int solicitudId;

  static const Duration actualizarCada = Duration(seconds: 15);

  @override
  State<SolicitudDetalleScreen> createState() => _SolicitudDetalleScreenState();
}

class _SolicitudDetalleScreenState extends State<SolicitudDetalleScreen> {
  DetalleSolicitud? _d;
  String? _error;
  bool _trabajando = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(SolicitudDetalleScreen.actualizarCada, (_) => _cargar(silencioso: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    try {
      final d = await CicloApi.detalle(widget.solicitudId);
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && !silencioso) setState(() => _error = mensajeDelCiclo(e));
    }
  }

  Future<void> _accion(Future<void> Function() f, String exito) async {
    if (_trabajando) return;
    setState(() => _trabajando = true);
    try {
      await f();
      if (!mounted) return;
      showToast(context, exito);
      await _cargar();
    } catch (e) {
      if (mounted) showToast(context, mensajeDelCiclo(e), error: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _cancelar() async {
    final ok = await confirmAction(context, title: 'Cancelar solicitud', message: 'Se cancelará sin ningún cargo. ¿Continuar?', confirmLabel: 'Cancelar solicitud', destructive: true);
    if (ok) await _accion(() => CicloApi.cancelar(widget.solicitudId), 'Solicitud cancelada.');
  }

  Future<void> _invitarOtro() async {
    final d = _d!;
    List<TrabajadorSeleccionable> lista;
    try {
      final cat = await Catalogo.obtener();
      lista = await HistorialApi.trabajadores(servicioId: cat.servicios[d.servicio], fecha: d.fechaProgramada);
    } catch (e) {
      if (mounted) showToast(context, mensajeDelCiclo(e), error: true);
      return;
    }
    if (!mounted) return;
    final elegido = await showModalBottomSheet<TrabajadorSeleccionable>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Invitar a otro colaborador')),
            if (lista.isEmpty) const ListTile(title: Text('No hay colaboradores disponibles para ese horario.')),
            for (final t in lista)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(t.nombre),
                subtitle: Text(t.reputacion.cantidad == 0 ? 'Sin calificaciones' : '${t.reputacion.promedio?.toStringAsFixed(1)} · ${t.reputacion.cantidad} reseña(s)'),
                onTap: () => Navigator.of(ctx).pop(t),
              ),
          ],
        ),
      ),
    );
    if (elegido != null) await _accion(() => CicloApi.invitar(widget.solicitudId, elegido.id), 'Invitación enviada a ${elegido.nombre}.');
  }

  Future<void> _verFoto(FotoTerminado f) async {
    try {
      final url = await CicloApi.urlFoto(widget.solicitudId, f.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Padding(padding: EdgeInsets.all(24), child: Text('No se pudo cargar la foto.'))))),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) showToast(context, mensajeDelCiclo(e), error: true);
    }
  }

  String _estadoLegible(DetalleSolicitud d) {
    if (d.estado == 'PENDIENTE') {
      if (d.rechazadaPor != null) return 'Invitación rechazada';
      if (d.modo == 'BOLSA') return 'En la bolsa: esperando a un colaborador';
      return 'Esperando a que ${d.invitadoNombre ?? 'el colaborador'} acepte';
    }
    if (d.estado == 'EN_PROCESO' && d.trabajadorTerminoEn != null) return 'Terminado por el colaborador: confirma';
    return etiquetaDeEstado(d.estado);
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);
    final d = _d;
    return Scaffold(
      body: WaveBackground(
        headerHeight: 190,
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, MediaQuery.paddingOf(context).bottom + 28),
            children: [
              StepHeader(title: d?.servicio ?? 'Solicitud', subtitle: d == null ? null : _estadoLegible(d)),
              const SizedBox(height: 16),
              if (_error != null) NoticeBox.error(message: _error!, action: AppLinkButton(label: 'Reintentar', onPressed: _cargar)),
              if (d == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              if (d != null) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SummaryRow('Estado', etiquetaDeEstado(d.estado)),
                      SummaryRow('Fecha', fechaCorta(d.fechaProgramada)),
                      if (d.finEstimado != null) SummaryRow('Termina aprox.', fechaCorta(d.finEstimado!)),
                      if (d.inmuebleNombre != null) SummaryRow('Inmueble', d.inmuebleNombre!),
                      SummaryRow('Dirección', d.direccion),
                      SummaryRow('Precio', '\$${d.precio.toStringAsFixed(0)} MXN en efectivo'),
                      SummaryRow('Asignación', d.modo == 'BOLSA' ? 'Bolsa abierta' : 'Invitación'),
                      SummaryRow('Colaborador', d.trabajadorNombre ?? d.invitadoNombre ?? 'Por asignar'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (d.rechazadaPor != null && d.estado == 'PENDIENTE')
                  NoticeBox.warning(message: '${d.rechazadaPor} no puede atender tu solicitud. Puedes enviarla a la bolsa, invitar a otro colaborador o cancelarla.'),
                if (d.reporteEnRevision) const NoticeBox(message: 'Hay un reporte en revisión: la administración resolverá el servicio.'),
                if (d.fotos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Fotos del trabajo terminado', style: AppText.heading),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < d.fotos.length; i++) ActionChip(avatar: const Icon(Icons.photo_outlined, size: 18), label: Text('Foto ${i + 1}'), onPressed: () => _verFoto(d.fotos[i])),
                  ]),
                ],
                const SizedBox(height: 18),
                if (d.puedeConfirmar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppButton(label: 'Confirmar que se realizó', icon: Icons.task_alt_rounded, loading: _trabajando, onPressed: () => _accion(() => CicloApi.confirmar(widget.solicitudId), '¡Gracias! Servicio confirmado.')),
                  ),
                if (d.puedeEnviarABolsa)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppButton(label: 'Enviar a la bolsa', icon: Icons.groups_outlined, variant: AppButtonVariant.outline, onPressed: _trabajando ? null : () => _accion(() => CicloApi.enviarABolsa(widget.solicitudId), 'Tu solicitud está en la bolsa.')),
                  ),
                if (d.puedeInvitarOtro)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppButton(label: 'Invitar a otro colaborador', icon: Icons.person_add_alt_outlined, variant: AppButtonVariant.outline, onPressed: _trabajando ? null : _invitarOtro),
                  ),
                if (d.activa && d.estado != 'EN_PROCESO')
                  d.puedeCancelar
                      ? AppButton(label: 'Cancelar solicitud', icon: Icons.close_rounded, variant: AppButtonVariant.outline, onPressed: _trabajando ? null : _cancelar)
                      : NoticeBox(message: d.motivoNoCancelar ?? 'Esta solicitud ya no se puede cancelar.'),
                const SizedBox(height: 8),
                Text('Se actualiza sola cada 15 s.', textAlign: TextAlign.center, style: AppText.caption.copyWith(color: AppColors.inkSoft)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
