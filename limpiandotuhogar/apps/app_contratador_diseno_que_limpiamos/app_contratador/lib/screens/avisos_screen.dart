import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/ciclo_api.dart';
import '../services/historial_api.dart';
import '../services/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';
import 'app_bottom_nav.dart';
import 'rate_screen.dart';
import 'solicitud_detalle_screen.dart';

/// Nombre de respaldo si el backend no manda el nombre del colaborador.
/// Esta pantalla ya usa el nombre real; se deja la constante por si otro
/// archivo todavía la importa.
const String kColaborador = 'Nicte';

/// Una solicitud aceptada por un colaborador.
class _Aviso {
  const _Aviso({
    required this.id,
    required this.colaborador,
    required this.detalle,
    required this.puedeCalificar,
    required this.yaCalificado,
  });

  final int id;
  final String colaborador;
  final String detalle;

  /// Lo indica el servidor (finalizado, dentro de 168 h, sin reseña previa).
  final bool puedeCalificar;
  final bool yaCalificado;
}

class AvisosScreen extends StatefulWidget {
  const AvisosScreen({super.key});

  @override
  State<AvisosScreen> createState() => _AvisosScreenState();
}

class _AvisosScreenState extends State<AvisosScreen> {
  static const Duration _pollEvery = Duration(seconds: 4);

  List<_Aviso> _avisos = const [];
  // Avisos REALES del servidor (D60): confirmaciones, rechazos, vencimientos, D54, reportes…
  List<Notificacion> _notificaciones = const [];
  int _noLeidas = 0;
  bool _cargando = true;
  bool _cargandoAhora = false;
  String? _error;
  Timer? _timer;

  // Por solicitud (antes era uno solo para toda la pantalla).
  final Set<int> _leidos = {};
  final Set<int> _calificados = {};

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(_pollEvery, (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    final clienteId = Session.instance.user?.id;
    if (clienteId == null || _cargandoAhora) {
      if (mounted && _cargando) setState(() => _cargando = false);
      return;
    }
    _cargandoAhora = true;
    try {
      final avisos = _parse(await HistorialApi.misSolicitudes());
      final (noLeidas, notificaciones) = await NotificacionesApi.listar();
      if (!mounted) return;
      setState(() {
        _avisos = avisos;
        _notificaciones = notificaciones;
        _noLeidas = noLeidas;
        _error = null;
        _cargando = false;
      });
    } catch (e, st) {
      debugPrint('[avisos] ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus avisos.';
        _cargando = false;
      });
    } finally {
      _cargandoAhora = false;
    }
  }

  /// Se queda con las solicitudes que ya tienen colaborador (confirmadas, en proceso o finalizadas).
  List<_Aviso> _parse(List<SolicitudCliente> solicitudes) {
    const estados = {'CONFIRMADO', 'EN_PROCESO', 'REALIZADO'};
    return [
      for (final s in solicitudes)
        if (s.trabajadorId != null && estados.contains(s.estado))
          _Aviso(
            id: s.id,
            colaborador: (s.trabajadorNombre ?? '').isEmpty ? 'Tu colaborador' : s.trabajadorNombre!,
            detalle: [s.servicio, _fmt(s.fechaProgramada.toLocal())].join(' · '),
            puedeCalificar: s.puedeCalificar,
            yaCalificado: s.miResena != null,
          ),
    ];
  }

  String _fmt(DateTime d) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }

  // Sin chat en las solicitudes reales (docs/backend/25 v2): se abre el detalle de la solicitud.
  void _abrirDetalle(_Aviso a) {
    setState(() => _leidos.add(a.id));
    AppRoutes.push(context, SolicitudDetalleScreen(solicitudId: a.id));
  }

  Future<void> _abrirNotificacion(Notificacion n) async {
    if (!n.leida) {
      try {
        await NotificacionesApi.marcarLeida(n.id);
      } catch (_) {}
    }
    if (!mounted) return;
    if (n.solicitudId != null) await AppRoutes.push(context, SolicitudDetalleScreen(solicitudId: n.solicitudId!));
    await _cargar();
  }

  Future<void> _marcarTodas() async {
    try {
      await NotificacionesApi.marcarTodas();
    } catch (_) {}
    await _cargar();
  }

  Future<void> _abrirCalificar(_Aviso a) async {
    final enviado = await AppRoutes.push<bool>(
      context,
      CalificarScreen(solicitudId: a.id, nombre: a.colaborador),
    );
    if (enviado == true && mounted) {
      setState(() => _calificados.add(a.id));
      showToast(context, '¡Gracias por tu calificación!',
          icon: Icons.cleaning_services_rounded);
    }
  }

  int get _sinLeer => _noLeidas;

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context);
    final logueado = Session.instance.user != null;
    final sinLeer = _sinLeer;

    return Scaffold(
      extendBody: true,
      body: WaveBackground(
        headerHeight: 190,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, MediaQuery.paddingOf(context).top + 16,
              pad, AppBottomNav.reservedHeight(context)),
          children: [
            TabHeader(
              title: 'Avisos',
              subtitle: !logueado || _cargando
                  ? 'Hoy'
                  : sinLeer == 0
                      ? 'Estás al día.'
                      : '$sinLeer aviso${sinLeer == 1 ? '' : 's'} sin leer',
            ),
            const SizedBox(height: 18),
            ..._contenido(),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }

  List<Widget> _contenido() {
    if (Session.instance.user == null) {
      return const [
        EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Sin sesión',
          message: 'Inicia sesión para ver tus avisos.',
        ),
      ];
    }
    if (_cargando) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final widgets = <Widget>[];
    if (_error != null) {
      widgets.add(NoticeBox.error(message: _error!));
      widgets.add(const SizedBox(height: 14));
    }
    if (_avisos.isEmpty && _error == null) {
      widgets.add(const EmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'Sin avisos por ahora',
        message:
            'Cuando un colaborador acepte tu solicitud, te avisaremos aquí.',
      ));
    }
    if (_notificaciones.isNotEmpty) {
      widgets.add(const SectionTitle('Avisos'));
      for (final n in _notificaciones.take(30)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            onTap: () => _abrirNotificacion(n),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Icon(n.leida ? Icons.notifications_none_rounded : Icons.notifications_active_rounded, color: n.leida ? AppColors.inkSoft : AppColors.primaryStrong),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.titulo, style: AppText.bodyStrong.copyWith(fontWeight: n.leida ? FontWeight.w500 : FontWeight.w700)),
                  Text(n.mensaje, style: AppText.caption),
                  Text(_fmt(n.fecha.toLocal()), style: AppText.caption.copyWith(color: AppColors.inkSoft)),
                ]),
              ),
            ]),
          ),
        ));
      }
      if (_noLeidas > 0) {
        widgets.add(Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _marcarTodas, child: const Text('Marcar todos como leídos'))));
      }
      widgets.add(const SizedBox(height: 14));
    }
    if (_avisos.isNotEmpty) widgets.add(const SectionTitle('Tus servicios'));
    var i = 0;
    for (final a in _avisos) {
      widgets.add(FadeSlideIn(
        key: ValueKey('conf-${a.id}'),
        delay: FadeSlideIn.stagger(i++),
        child: _tarjetaConfirmado(a),
      ));
      // La tarjeta de calificar solo aparece cuando el servidor lo permite (o si ya calificaste).
      if (a.puedeCalificar || a.yaCalificado || _calificados.contains(a.id)) {
        widgets.add(const SizedBox(height: 12));
        widgets.add(FadeSlideIn(
          key: ValueKey('rate-${a.id}'),
          delay: FadeSlideIn.stagger(i++),
          child: _tarjetaCalificar(a),
        ));
      }
      widgets.add(const SizedBox(height: 22));
    }
    return widgets;
  }

  Widget _icono(IconData icon, Color bg, Color fg) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: fg, size: 24),
    );
  }

  // ─────────────────── TARJETA: SERVICIO CONFIRMADO ───────────────────
  Widget _tarjetaConfirmado(_Aviso a) {
    final leido = _leidos.contains(a.id);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      border: leido ? AppColors.divider : AppColors.aqua,
      shadow: !leido,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _icono(Icons.check_rounded, AppColors.mint, AppColors.successFg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${a.colaborador} ha confirmado tu servicio',
                        style: AppText.bodyStrong.copyWith(
                            fontWeight:
                                leido ? FontWeight.w500 : FontWeight.w700),
                      ),
                    ),
                    AnimatedContainer(
                      duration: AppDurations.medium,
                      margin: const EdgeInsets.only(top: 5, left: 6),
                      width: leido ? 0 : 9,
                      height: 9,
                      decoration: const BoxDecoration(
                          color: AppColors.successFg, shape: BoxShape.circle),
                    ),
                  ],
                ),
                if (a.detalle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    a.detalle,
                    style: AppText.caption.copyWith(color: AppColors.inkSoft),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _abrirDetalle(a),
                    icon: const Icon(Icons.receipt_long_outlined,
                        size: 16),
                    label: const Text('Ver detalle'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryStrong,
                      shape: const StadiumBorder(),
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      textStyle: AppText.label,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────── TARJETA: CALIFICA TU SERVICIO ───────────────────
  Widget _tarjetaCalificar(_Aviso a) {
    final calificado = a.yaCalificado || _calificados.contains(a.id);
    return AppCard(
      onTap: calificado ? null : () => _abrirCalificar(a),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      border: calificado ? AppColors.divider : null,
      shadow: !calificado,
      child: Row(
        children: [
          calificado
              ? _icono(Icons.check_rounded, AppColors.mint, AppColors.successFg)
              : _icono(Icons.star_outline_rounded, AppColors.ice,
                  AppColors.primaryStrong),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  calificado ? 'Servicio calificado' : 'Califica tu servicio',
                  style: AppText.bodyStrong
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  calificado
                      ? 'Gracias por tus comentarios'
                      : 'Cuéntanos cómo te fue con ${a.colaborador}',
                  style: AppText.caption.copyWith(color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          if (!calificado)
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.primaryStrong),
        ],
      ),
    );
  }
}
