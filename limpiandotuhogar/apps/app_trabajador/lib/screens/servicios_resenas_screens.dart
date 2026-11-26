import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../services/haptics.dart';
import '../services/historial_api.dart';
import '../services/resenas_reportes_api.dart';
import '../services/validaciones_contenido.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/screen_header.dart';

// ════════════════════════════════════════════════════════════════════
// Reseñas y reportes del TRABAJADOR (Fase 3b) con datos REALES del backend:
//   GET  /api/trabajador/solicitudes                 mis servicios (asignados e invitaciones)
//   POST /api/trabajador/solicitudes/:id/resena      calificar al cliente
//   POST /api/trabajador/solicitudes/:id/reportes    reportar (multipart)
//   GET  /api/trabajador/solicitudes/:id/reputacion-cliente
//   GET  /api/trabajador/resenas · /resenas/recibidas · /reportes[/:id]
// El backend es la autoridad: la app solo refleja lo que permite.
// ════════════════════════════════════════════════════════════════════

Widget _pantalla(BuildContext context, String titulo, Widget cuerpo) {
  final pad = AppSpacing.screen(context);
  return Scaffold(
    body: SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(title: titulo, onBack: () => Navigator.of(context).maybePop()),
            const SizedBox(height: 10),
            Expanded(child: cuerpo),
          ],
        ),
      ),
    ),
  );
}

/// Carga con estados de carga, error recuperable y vacío.
class _Cargador<T> extends StatefulWidget {
  const _Cargador({super.key, required this.cargar, required this.vacio, required this.construir});

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
      return Align(
        alignment: Alignment.topCenter,
        child: NoticeBox.error(message: _error!, action: AppLinkButton(label: 'Reintentar', onPressed: _recargar)),
      );
    }
    final datos = _datos;
    if (datos == null) return const Center(child: CircularProgressIndicator());
    if (datos.isEmpty) return widget.vacio;
    return RefreshIndicator(onRefresh: _recargar, child: widget.construir(datos, _recargar));
  }
}

// ── MIS SERVICIOS ─────────────────────────────────────────────────────
class MisServiciosScreen extends StatefulWidget {
  const MisServiciosScreen({super.key});

  @override
  State<MisServiciosScreen> createState() => _MisServiciosScreenState();
}

class _MisServiciosScreenState extends State<MisServiciosScreen> {
  Key _clave = UniqueKey();

  void _recargar() => setState(() => _clave = UniqueKey());

  Future<void> _calificar(SolicitudTrabajador s) async {
    final ok = await AppRoutes.push<bool>(context, CalificarClienteScreen(solicitudId: s.id, clienteNombre: s.clienteNombre));
    if (ok == true && mounted) {
      showToast(context, 'Gracias. Tu calificación quedó guardada.', icon: Icons.cleaning_services_rounded);
      _recargar();
    }
  }

  Future<void> _reportar(SolicitudTrabajador s) async {
    final ok = await AppRoutes.push<bool>(context, ReportarClienteScreen(solicitudId: s.id, servicio: s.servicio));
    if (ok == true && mounted) {
      showToast(context, 'Reporte enviado. La administración le dará seguimiento.', icon: Icons.flag_outlined);
      _recargar();
    }
  }

  Future<void> _reputacion(SolicitudTrabajador s) async {
    await showAppSheet<void>(context, title: 'Reputación de ${s.clienteNombre}', builder: (_) => _ReputacionCliente(solicitudId: s.id));
  }

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Mis servicios',
      _Cargador<SolicitudTrabajador>(
        key: _clave,
        cargar: HistorialApi.misSolicitudes,
        vacio: const EmptyState(icon: Icons.work_outline_rounded, title: 'Aún no tienes servicios registrados', message: 'Aquí aparecerán los servicios que te asignen y las invitaciones vigentes.'),
        construir: (lista, _) => ListView.separated(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
          itemCount: lista.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _TarjetaServicio(
            solicitud: lista[i],
            onCalificar: () => _calificar(lista[i]),
            onReportar: () => _reportar(lista[i]),
            onReputacion: () => _reputacion(lista[i]),
          ),
        ),
      ),
    );
  }
}

class _TarjetaServicio extends StatelessWidget {
  const _TarjetaServicio({required this.solicitud, required this.onCalificar, required this.onReportar, required this.onReputacion});

  final SolicitudTrabajador solicitud;
  final VoidCallback onCalificar;
  final VoidCallback onReportar;
  final VoidCallback onReputacion;

  @override
  Widget build(BuildContext context) {
    final s = solicitud;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.servicio, style: AppText.bodyStrong)),
              Pill(label: s.asignado ? etiquetaDeEstado(s.estado) : 'Invitación', dense: true),
            ],
          ),
          const SizedBox(height: 4),
          Text('${s.clienteNombre} · ${fechaCorta(s.fechaProgramada)}', style: AppText.caption),
          if (s.miResena != null) ...[
            const SizedBox(height: 6),
            Row(children: [const Text('Tu calificación: ', style: AppText.caption), BroomRating(value: s.miResena!.puntuacion, size: 16)]),
          ] else if (s.puedeCalificar && s.calificarHasta != null) ...[
            const SizedBox(height: 6),
            Text('Puedes calificar hasta el ${fechaCorta(s.calificarHasta!)}', style: AppText.caption.copyWith(color: AppColors.successFg)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (s.puedeVerReputacionCliente) OutlinedButton.icon(onPressed: onReputacion, icon: const Icon(Icons.star_outline_rounded, size: 18), label: const Text('Reputación del cliente')),
              if (s.puedeCalificar) FilledButton.icon(onPressed: onCalificar, icon: const Icon(Icons.cleaning_services_rounded, size: 18), label: const Text('Calificar')),
              if (s.puedeReportar) OutlinedButton.icon(onPressed: onReportar, icon: const Icon(Icons.flag_outlined, size: 18), label: const Text('Reportar')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Reputación del cliente: el backend la entrega solo si el trabajador está invitado o asignado (V5).
class _ReputacionCliente extends StatelessWidget {
  const _ReputacionCliente({required this.solicitudId});

  final int solicitudId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Reputacion>(
      future: ResenasApi.reputacionDelCliente(solicitudId),
      builder: (context, snap) {
        if (snap.hasError) return NoticeBox.warning(message: mensajeDeError(snap.error!));
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        final r = snap.data!;
        if (r.promedio == null) return const Text('Este cliente todavía no tiene calificaciones.', style: AppText.body);
        return Row(
          children: [
            BroomRating(value: r.promedio!.round(), size: 24),
            const SizedBox(width: 10),
            Text('${r.promedio!.toStringAsFixed(1)} de 5 · ${r.cantidad} reseña${r.cantidad == 1 ? '' : 's'}', style: AppText.bodyStrong),
          ],
        );
      },
    );
  }
}

// ── CALIFICAR AL CLIENTE ──────────────────────────────────────────────
class CalificarClienteScreen extends StatefulWidget {
  const CalificarClienteScreen({super.key, required this.solicitudId, required this.clienteNombre});

  final int solicitudId;
  final String clienteNombre;

  @override
  State<CalificarClienteScreen> createState() => _CalificarClienteScreenState();
}

class _CalificarClienteScreenState extends State<CalificarClienteScreen> {
  static const _etiquetas = ['Mala', 'Regular', 'Buena', 'Muy buena', 'Excelente'];
  static const _definitivos = {'RESENA_DUPLICADA', 'PLAZO_VENCIDO', 'SERVICIO_NO_FINALIZADO', 'NO_ES_PARTE'};

  int _estrellas = 0;
  final _comentario = TextEditingController();
  bool _enviando = false;
  bool _bloqueado = false;
  String? _error;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando || _bloqueado) return; // evita envíos repetidos
    final invalido = validarResena(puntuacion: _estrellas, comentario: _comentario.text);
    if (invalido != null) {
      setState(() => _error = invalido);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ResenasApi.calificarCliente(widget.solicitudId, puntuacion: _estrellas, comentario: _comentario.text);
      if (!mounted) return;
      Haptics.success(context);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = mensajeDeError(e);
        _bloqueado = e is ApiException && _definitivos.contains(e.codigo);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Calificar al cliente',
      ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
        children: [
          Text(widget.clienteNombre, style: AppText.title),
          const SizedBox(height: 16),
          Center(
            child: BroomRating(value: _estrellas, size: 36, onChanged: _enviando || _bloqueado ? null : (v) => setState(() => _estrellas = v)),
          ),
          const SizedBox(height: 6),
          Text(_estrellas == 0 ? 'Toca las escobas para calificar' : _etiquetas[_estrellas - 1], textAlign: TextAlign.center, style: AppText.label),
          const SizedBox(height: 18),
          AppTextField(
            controller: _comentario,
            hint: 'Comentario (opcional)',
            maxLines: 5,
            maxLength: kMaxComentario,
            editable: !_enviando && !_bloqueado,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 6),
          const Text('Se publica de inmediato y no podrás editarla. El cliente verá la calificación y el comentario, pero no quién la escribió.', style: AppText.caption),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _bloqueado ? NoticeBox.warning(message: _error!) : NoticeBox.error(message: _error!),
          ],
          const SizedBox(height: 18),
          AppButton(label: 'Enviar calificación', icon: Icons.send_rounded, loading: _enviando, onPressed: _enviando || _bloqueado ? null : _enviar),
        ],
      ),
    );
  }
}

// ── REPORTAR ─────────────────────────────────────────────────────────
class _Foto {
  _Foto(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

class ReportarClienteScreen extends StatefulWidget {
  const ReportarClienteScreen({super.key, required this.solicitudId, required this.servicio});

  final int solicitudId;
  final String servicio;

  @override
  State<ReportarClienteScreen> createState() => _ReportarClienteScreenState();
}

class _ReportarClienteScreenState extends State<ReportarClienteScreen> {
  final _descripcion = TextEditingController();
  final _picker = ImagePicker();
  final List<_Foto> _fotos = [];
  String _tipo = 'OTRO';
  bool _enviando = false;
  bool _eligiendo = false;
  String? _error;

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  int get _total => _fotos.fold(0, (s, f) => s + f.bytes.length);

  Future<void> _agregarFoto() async {
    if (_enviando || _eligiendo) return;
    if (_fotos.length >= kMaxFotos) {
      showToast(context, 'Puedes adjuntar como máximo $kMaxFotos fotografías.', error: true);
      return;
    }
    final origen = await showAppSheet<ImageSource>(
      context,
      title: 'Agregar fotografía',
      builder: (ctx) => Column(
        children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.of(ctx).pop(ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de la galería'), onTap: () => Navigator.of(ctx).pop(ImageSource.gallery)),
        ],
      ),
    );
    if (origen == null || !mounted) return;
    setState(() => _eligiendo = true);
    try {
      final archivo = await _picker.pickImage(source: origen, maxWidth: 2000, imageQuality: 85);
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      final ext = extensionReal(bytes);
      final error = ext == null ? 'Solo se admiten fotografías JPEG, PNG o WebP.' : validarFotos([..._fotos.map((f) => f.bytes), bytes]);
      if (!mounted) return;
      if (error != null) {
        showToast(context, error, error: true);
        return;
      }
      setState(() => _fotos.add(_Foto(bytes, ext!)));
    } catch (_) {
      if (mounted) showToast(context, 'No se pudo cargar la fotografía. Intenta con otra.', error: true);
    } finally {
      if (mounted) setState(() => _eligiendo = false);
    }
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final invalido = validarFotos(_fotos.map((f) => f.bytes).toList());
    if (invalido != null) {
      setState(() => _error = invalido);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ReportesApi.reportar(
        widget.solicitudId,
        tipo: _tipo,
        descripcion: _descripcion.text,
        fotos: [for (var i = 0; i < _fotos.length; i++) (nombre: 'evidencia-${i + 1}.${_fotos[i].extension}', bytes: _fotos[i].bytes)],
      );
      if (!mounted) return;
      Haptics.success(context);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = mensajeDeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Reportar un problema',
      ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
        children: [
          Text(widget.servicio, style: AppText.caption),
          const SizedBox(height: 10),
          const NoticeBox(message: 'Solo tú y la administración verán este reporte. El cliente no podrá consultarlo ni saber quién lo hizo.'),
          const SizedBox(height: 16),
          const Text('¿Qué pasó?', style: AppText.heading),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kTiposDeReporte.entries)
                ChoiceChip(label: Text(e.value), selected: _tipo == e.key, onSelected: _enviando ? null : (_) => setState(() => _tipo = e.key)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Descripción (opcional)', style: AppText.heading),
          const SizedBox(height: 8),
          AppTextField(controller: _descripcion, hint: 'Cuéntanos qué ocurrió', maxLines: 5, editable: !_enviando, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Fotografías (opcional)', style: AppText.heading)),
              Text('${_fotos.length}/$kMaxFotos · ${megas(_total)} de 16 MB', style: AppText.caption),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _fotos.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.memory(_fotos[i].bytes, width: 88, height: 88, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 88, height: 88, color: AppColors.frost, child: const Icon(Icons.broken_image_outlined))),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: _enviando ? null : () => setState(() => _fotos.removeAt(i)),
                        child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close_rounded, size: 14, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              if (_fotos.length < kMaxFotos)
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: _enviando || _eligiendo ? null : _agregarFoto,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.primary, width: 1.2)),
                    child: _eligiendo
                        ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                        : const Icon(Icons.add_a_photo_outlined, color: AppColors.primaryStrong),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('JPEG, PNG o WebP · máx. 8 MB por foto y 16 MB en total.', style: AppText.caption),
          if (_error != null) ...[const SizedBox(height: 12), NoticeBox.error(message: _error!)],
          if (_enviando) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_fotos.isEmpty ? 'Enviando reporte…' : 'Enviando reporte con ${_fotos.length} foto${_fotos.length == 1 ? '' : 's'}…', style: AppText.caption),
          ],
          const SizedBox(height: 18),
          AppButton(label: 'Enviar reporte', icon: Icons.flag_outlined, loading: _enviando, onPressed: _enviando ? null : _enviar),
        ],
      ),
    );
  }
}

// ── MIS RESEÑAS / RECIBIDAS / REPORTES ────────────────────────────────
class MisResenasScreen extends StatelessWidget {
  const MisResenasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Reseñas que escribí',
      _Cargador<ResenaPropia>(
        cargar: ResenasApi.misResenas,
        vacio: const EmptyState(icon: Icons.star_outline_rounded, title: 'Aún no calificas clientes', message: 'Al terminar un servicio podrás calificar al cliente durante 7 días.'),
        construir: (lista, _) => ListView.separated(
          itemCount: lista.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final r = lista[i];
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [BroomRating(value: r.puntuacion, size: 20), const Spacer(), Text(fechaCorta(r.fecha), style: AppText.caption)]),
                  const SizedBox(height: 6),
                  Text(r.comentario ?? 'Sin comentario', style: AppText.body),
                  Text('Servicio #${r.solicitudId}', style: AppText.caption),
                  if (r.editadaPorModeracion) const Padding(padding: EdgeInsets.only(top: 6), child: Pill(label: 'Corregida por moderación', dense: true)),
                  if (r.eliminadaPorModeracion) const Padding(padding: EdgeInsets.only(top: 6), child: Pill(label: 'Retirada por moderación', dense: true)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Reseñas que RECIBIÓ el trabajador: anónimas (calificación, comentario y mes/año) y su promedio.
class ResenasRecibidasScreen extends StatelessWidget {
  const ResenasRecibidasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Mi reputación',
      _Cargador<({Reputacion reputacion, List<ResenaPublica> resenas})>(
        cargar: () async => [await ResenasApi.resenasRecibidas()],
        vacio: const SizedBox.shrink(),
        construir: (datos, _) {
          final d = datos.first;
          final p = d.reputacion.promedio;
          return ListView(
            children: [
              AppCard(
                color: AppColors.ice,
                shadow: false,
                child: p == null
                    ? const Text('Todavía no tienes calificaciones.', style: AppText.bodyStrong)
                    : Row(children: [
                        BroomRating(value: p.round(), size: 26),
                        const SizedBox(width: 10),
                        Text('${p.toStringAsFixed(1)} de 5 · ${d.reputacion.cantidad} reseña${d.reputacion.cantidad == 1 ? '' : 's'}', style: AppText.bodyStrong),
                      ]),
              ),
              const SizedBox(height: 12),
              for (final r in d.resenas) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [BroomRating(value: r.puntuacion, size: 18), const Spacer(), Text('${kMeses[r.mes - 1]} ${r.anio}', style: AppText.caption)]),
                      if (r.comentario != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.comentario!, style: AppText.body)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class MisReportesScreen extends StatelessWidget {
  const MisReportesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _pantalla(
      context,
      'Mis reportes',
      _Cargador<ReportePropio>(
        cargar: ReportesApi.misReportes,
        vacio: const EmptyState(icon: Icons.flag_outlined, title: 'No has hecho reportes', message: 'Si algo sale mal en un servicio, puedes reportarlo desde "Mis servicios".'),
        construir: (lista, _) => ListView.separated(
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
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kTiposDeReporte[r.tipo] ?? r.tipo, style: AppText.heading),
                    Text('Servicio #${r.solicitudId} · ${fechaCorta(r.fecha)}', style: AppText.caption),
                    const SizedBox(height: 8),
                    Pill(label: r.eliminadoPorModeracion ? 'Retirado por moderación' : 'Estado: ${kEstadosDeReporte[r.estado] ?? r.estado}', dense: true),
                    const SizedBox(height: 10),
                    Text(r.descripcion ?? 'Sin descripción', style: AppText.body),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('Fotografías', style: AppText.heading),
              const SizedBox(height: 8),
              if (r.evidenciaIds.isEmpty) const Text('Sin fotografías.', style: AppText.caption),
              Wrap(spacing: 10, runSpacing: 10, children: [for (final id in r.evidenciaIds) _FotoRemota(reporteId: r.id, evidenciaId: id)]),
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
          hijo = Image.network(snap.data!, width: 104, height: 104, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: AppColors.inkMuted));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(width: 104, height: 104, color: AppColors.frost, alignment: Alignment.center, child: hijo),
        );
      },
    );
  }
}
