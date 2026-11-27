import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/historial_api.dart';
import '../services/resenas_reportes_api.dart';
import '../services/validaciones_contenido.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';

/// Carga genérica con estados de carga, error recuperable y vacío.
class _Cargador<T> extends StatefulWidget {
  const _Cargador({required this.cargar, required this.vacio, required this.construir});

  final Future<List<T>> Function() cargar;
  final Widget vacio;
  final Widget Function(List<T> datos, Future<void> Function() recargar) construir;

  @override
  State<_Cargador<T>> createState() => _CargadorState<T>();
}

class _CargadorState<T> extends State<_Cargador<T>> {
  List<T>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recargar();
  }

  Future<void> _recargar() async {
    setState(() => _error = null);
    try {
      final datos = await widget.cargar();
      if (mounted) setState(() => _datos = datos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: NoticeBox.error(
          message: _error!,
          action: AppLinkButton(label: 'Reintentar', onPressed: _recargar),
        ),
      );
    }
    final datos = _datos;
    if (datos == null) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    if (datos.isEmpty) return widget.vacio;
    return RefreshIndicator(onRefresh: _recargar, child: widget.construir(datos, _recargar));
  }
}

Widget _pantalla(BuildContext context, String titulo, Widget cuerpo) {
  final pad = AppSpacing.screen(context);
  return Scaffold(
    body: WaveBackground(
      headerHeight: 200,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [StepHeader(title: titulo), const SizedBox(height: 12), Expanded(child: cuerpo)],
        ),
      ),
    ),
  );
}

/// Reseñas que el cliente ESCRIBIÓ (GET /api/cliente/resenas). Solo lectura: no se editan ni se borran.
class MisResenasScreen extends StatelessWidget {
  const MisResenasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Mis reseñas',
      _Cargador<ResenaPropia>(
        cargar: ResenasApi.misResenas,
        vacio: const EmptyState(icon: Icons.star_outline_rounded, title: 'Aún no calificas servicios', message: 'Cuando un servicio termine, podrás calificarlo desde tu historial durante 7 días.'),
        construir: (lista, _) => ListView.separated(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
          itemCount: lista.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final r = lista[i];
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [BroomRating(value: r.puntuacion, size: 22), const Spacer(), Text(fechaCorta(r.fecha), style: AppText.caption)]),
                  const SizedBox(height: 6),
                  Text(r.comentario ?? 'Sin comentario', style: AppText.body),
                  const SizedBox(height: 6),
                  Text('Servicio #${r.solicitudId}', style: AppText.caption),
                  if (r.editadaPorModeracion) const Padding(padding: EdgeInsets.only(top: 6), child: Pill(label: 'Corregida por moderación', dense: true)),
                  if (r.eliminadaPorModeracion)
                    const Padding(padding: EdgeInsets.only(top: 6), child: Pill(label: 'Retirada por moderación', dense: true, background: AppColors.warningBg, foreground: AppColors.warningFg)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Reportes que el cliente CREÓ (GET /api/cliente/reportes). Nadie más que él y la administración los ve.
class MisReportesScreen extends StatelessWidget {
  const MisReportesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Mis reportes',
      _Cargador<ReportePropio>(
        cargar: ReportesApi.misReportes,
        vacio: const EmptyState(icon: Icons.flag_outlined, title: 'No has hecho reportes', message: 'Si algo sale mal en un servicio, puedes reportarlo desde tu historial.'),
        construir: (lista, _) => ListView.separated(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
          itemCount: lista.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final r = lista[i];
            return AppCard(
              onTap: () => AppRoutes.push(context, DetalleReporteScreen(reporteId: r.id)),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined, color: AppColors.primaryStrong),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kTiposDeReporte[r.tipo] ?? r.tipo, style: AppText.bodyStrong),
                        Text('Servicio #${r.solicitudId} · ${fechaCorta(r.fecha)}', style: AppText.caption),
                      ],
                    ),
                  ),
                  Pill(label: r.eliminadoPorModeracion ? 'Retirado' : (kEstadosDeReporte[r.estado] ?? r.estado), dense: true),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Detalle de un reporte PROPIO con sus fotos (URL temporal de 5 minutos).
class DetalleReporteScreen extends StatelessWidget {
  const DetalleReporteScreen({super.key, required this.reporteId});

  final int reporteId;

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Reporte',
      _Cargador<ReportePropio>(
        cargar: () async => [await ReportesApi.miReporte(reporteId)],
        vacio: const SizedBox.shrink(),
        construir: (datos, _) {
          final r = datos.first;
          return ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kTiposDeReporte[r.tipo] ?? r.tipo, style: AppText.heading),
                    const SizedBox(height: 4),
                    Text('Servicio #${r.solicitudId} · ${fechaCorta(r.fecha)}', style: AppText.caption),
                    const SizedBox(height: 8),
                    Pill(label: r.eliminadoPorModeracion ? 'Retirado por moderación' : 'Estado: ${kEstadosDeReporte[r.estado] ?? r.estado}', dense: true),
                    const SizedBox(height: 12),
                    Text(r.descripcion ?? 'Sin descripción', style: AppText.body),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Fotografías', style: AppText.title),
              const SizedBox(height: 10),
              if (r.evidenciaIds.isEmpty) Text('Sin fotografías.', style: AppText.caption),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [for (final id in r.evidenciaIds) _FotoRemota(reporteId: r.id, evidenciaId: id)],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FotoRemota extends StatelessWidget {
  const _FotoRemota({required this.reporteId, required this.evidenciaId});

  final int reporteId;
  final int evidenciaId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: ReportesApi.urlDeFoto(reporteId, evidenciaId),
      builder: (context, snap) {
        Widget hijo;
        if (snap.hasError) {
          hijo = const Icon(Icons.broken_image_outlined, color: AppColors.inkMuted);
        } else if (!snap.hasData) {
          hijo = const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2));
        } else {
          hijo = Image.network(snap.data!, width: 110, height: 110, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.inkMuted));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(width: 110, height: 110, color: AppColors.frost, alignment: Alignment.center, child: hijo),
        );
      },
    );
  }
}
