import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/historial_api.dart';
import '../services/validaciones_contenido.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'mis_resenas_reportes_screen.dart';
import 'rate_screen.dart';
import 'reportar_screen.dart';
import 'solicitud_detalle_screen.dart';

/// Historial de limpiezas del cliente (GET /api/cliente/solicitudes). Desde cada servicio se
/// califica al trabajador (si el servidor lo permite) o se reporta un problema.
class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  List<SolicitudCliente>? _solicitudes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final lista = await HistorialApi.misSolicitudes();
      if (mounted) setState(() => _solicitudes = lista);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  void _pronto() => showToast(context, 'Esta opción estará disponible pronto.', icon: Icons.info_outline_rounded);

  Future<void> _verDetalle(SolicitudCliente s) async {
    await AppRoutes.push(context, SolicitudDetalleScreen(solicitudId: s.id));
    if (mounted) await _cargar();
  }

  Future<void> _calificar(SolicitudCliente s) async {
    final ok = await AppRoutes.push<bool>(context, CalificarScreen(solicitudId: s.id, nombre: s.trabajadorNombre ?? 'Colaborador'));
    if (ok == true && mounted) {
      showToast(context, '¡Gracias por tu calificación!', icon: Icons.cleaning_services_rounded);
      await _cargar();
    }
  }

  Future<void> _reportar(SolicitudCliente s) async {
    final ok = await AppRoutes.push<bool>(context, ReportarScreen(solicitudId: s.id, servicio: s.servicio));
    if (ok == true && mounted) {
      showToast(context, 'Reporte enviado. La administración le dará seguimiento.', icon: Icons.flag_outlined);
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);
    final lista = _solicitudes;
    final actuales = lista?.where((s) => s.activa).toList() ?? [];
    actuales.sort((a, b) => a.fechaProgramada.compareTo(b.fechaProgramada));
    final pasadas = lista?.where((s) => !s.activa).toList() ?? [];

    return Scaffold(
      body: WaveBackground(
        headerHeight: 200,
        child: RefreshIndicator(
          onRefresh: _cargar,
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, MediaQuery.paddingOf(context).bottom + 28),
            children: [
              const StepHeader(title: 'Historial'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(avatar: const Icon(Icons.star_outline_rounded, size: 18), label: const Text('Mis reseñas'), onPressed: () => AppRoutes.push(context, const MisResenasScreen())),
                  ActionChip(avatar: const Icon(Icons.flag_outlined, size: 18), label: const Text('Mis reportes'), onPressed: () => AppRoutes.push(context, const MisReportesScreen())),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null) NoticeBox.error(message: _error!, action: AppLinkButton(label: 'Reintentar', onPressed: _cargar)),
              if (lista == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              if (lista != null && lista.isEmpty)
                const EmptyState(icon: Icons.cleaning_services_outlined, title: 'Aún no tienes servicios', message: 'Cuando solicites una limpieza, aparecerá aquí.'),
              if (actuales.isNotEmpty) ...[
                FadeSlideIn(child: _TarjetaActual(solicitud: actuales.first, onReportar: () => _reportar(actuales.first), onPronto: () => _verDetalle(actuales.first))),
                const SizedBox(height: 26),
              ],
              if (pasadas.isNotEmpty) ...[
                Text('Pasadas', style: AppText.title),
                const SizedBox(height: 12),
                for (var i = 0; i < pasadas.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FadeSlideIn(
                      delay: FadeSlideIn.stagger(i + 1),
                      child: _TarjetaPasada(
                        solicitud: pasadas[i],
                        onCalificar: () => _calificar(pasadas[i]),
                        onReportar: () => _reportar(pasadas[i]),
                        onPronto: _pronto,
                        onDetalle: () => _verDetalle(pasadas[i]),
                      ),
                    ),
                  ),
              ],
              if (actuales.length > 1) ...[
                Text('Próximas', style: AppText.title),
                const SizedBox(height: 12),
                for (final s in actuales.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TarjetaPasada(solicitud: s, onCalificar: () => _calificar(s), onReportar: () => _reportar(s), onPronto: _pronto, onDetalle: () => _verDetalle(s)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// TARJETA SERVICIO ACTUAL
class _TarjetaActual extends StatelessWidget {
  const _TarjetaActual({required this.solicitud, required this.onReportar, required this.onPronto});

  final SolicitudCliente solicitud;
  final VoidCallback onReportar;
  final VoidCallback onPronto;

  @override
  Widget build(BuildContext context) {
    final s = solicitud;
    final nombre = s.trabajadorNombre ?? 'Colaborador por asignar';
    final iniciales = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    return HeroPanel(
      seed: 4,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BlobAvatar(seed: nombre.codeUnits.fold<int>(0, (a, b) => a + b), initials: iniciales, size: 76),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre, style: AppText.heading.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(etiquetaDeEstado(s.estado), style: AppText.caption.copyWith(color: AppColors.ice)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(color: AppColors.fade(Colors.white, 0.94), borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Linea('Servicio', s.servicio),
                _Linea('Fecha', fechaCorta(s.fechaProgramada)),
                _Linea('Dirección', s.direccion),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (s.puedeReportar) ...[
                _BotonPildora(label: 'Reportar', onTap: onReportar),
                const SizedBox(width: 8),
              ],
              _BotonPildora(label: 'Ver detalle', filled: true, onTap: onPronto),
            ],
          ),
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: AppText.body.copyWith(color: AppColors.inkSoft, fontSize: 13),
          children: [TextSpan(text: value, style: AppText.bodyStrong.copyWith(fontSize: 13))],
        ),
      ),
    );
  }
}

class _BotonPildora extends StatelessWidget {
  const _BotonPildora({required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Material(
        color: filled ? AppColors.ice : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            alignment: Alignment.center,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(fontSize: 12, color: filled ? AppColors.primaryStrong : AppColors.ink)),
          ),
        ),
      ),
    );
  }
}

// TARJETAS DE SERVICIOS
class _TarjetaPasada extends StatelessWidget {
  const _TarjetaPasada({required this.solicitud, required this.onCalificar, required this.onReportar, required this.onPronto, required this.onDetalle});

  final SolicitudCliente solicitud;
  final VoidCallback onCalificar;
  final VoidCallback onReportar;
  final VoidCallback onPronto;
  final VoidCallback onDetalle;

  @override
  Widget build(BuildContext context) {
    final s = solicitud;
    final resena = s.miResena;
    return AppCard(
      onTap: onDetalle,
      radius: AppRadius.xl,
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: s.finalizada ? AppColors.mint : AppColors.frost, shape: BoxShape.circle),
            child: Icon(s.finalizada ? Icons.check_rounded : Icons.schedule_rounded, color: s.finalizada ? AppColors.successFg : AppColors.inkSoft, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.servicio, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(fechaCorta(s.fechaProgramada), style: AppText.caption),
                if (s.trabajadorNombre != null) Text(s.trabajadorNombre!, style: AppText.caption),
                const SizedBox(height: 4),
                Pill(label: etiquetaDeEstado(s.estado), icon: Icons.task_alt_rounded, background: AppColors.frost, foreground: AppColors.inkSoft, dense: true),
                if (resena != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [Text('Tu calificación: ', style: AppText.caption), BroomRating(value: resena.puntuacion, size: 16)]),
                ] else if (s.puedeCalificar && s.calificarHasta != null) ...[
                  const SizedBox(height: 4),
                  Text('Puedes calificar hasta el ${fechaCorta(s.calificarHasta!)}', style: AppText.caption.copyWith(color: AppColors.successFg)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.puedeCalificar) ...[
                  _BotonContorno(label: 'Calificar', onTap: onCalificar),
                  const SizedBox(height: 6),
                ] else if (s.finalizada) ...[
                  _BotonContorno(label: 'Reagendar', onTap: onPronto),
                  const SizedBox(height: 6),
                ],
                if (s.puedeReportar) _BotonContorno(label: 'Reportar', onTap: onReportar),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// BOTONES CON CONTORNO
class _BotonContorno extends StatelessWidget {
  const _BotonContorno({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: AppColors.primary, width: 1.2)),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(label, textAlign: TextAlign.center, style: AppText.label.copyWith(fontSize: 12, color: AppColors.primaryStrong)),
        ),
      ),
    );
  }
}
