import 'dart:async';

import 'package:flutter/material.dart';

import '../navigation/app_routes.dart';
import '../services/api_client.dart';
import '../services/session.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';
import '../widgets/common.dart';
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';
import 'app_bottom_nav.dart';
import 'chat_screen.dart';
import 'rate_screen.dart';

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
  });

  final int id;
  final String colaborador;
  final String detalle;
}

class AvisosScreen extends StatefulWidget {
  const AvisosScreen({super.key});

  @override
  State<AvisosScreen> createState() => _AvisosScreenState();
}

class _AvisosScreenState extends State<AvisosScreen> {
  static const Duration _pollEvery = Duration(seconds: 4);

  List<_Aviso> _avisos = const [];
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
      final data = await ApiClient.get('/hoyo-negro?cliente_id=$clienteId');
      final avisos = _parse(data);
      if (!mounted) return;
      setState(() {
        _avisos = avisos;
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

  /// Se queda solo con las solicitudes que ya aceptó un colaborador.
  List<_Aviso> _parse(dynamic data) {
    if (data is! List) return const [];
    final out = <_Aviso>[];
    for (final e in data) {
      if (e is! Map) continue;
      if (e['estado'] != 'ACEPTADA') continue;
      final id = e['id'];
      if (id is! int) continue;

      final t = e['trabajador'];
      final nombre = t is Map ? (t['name'] as String?)?.trim() : null;

      final sel = e['seleccion'];
      final tipo = sel is Map ? sel['tipoLimpieza']?.toString() : null;
      DateTime? fecha;
      final rawFecha = e['fecha'];
      if (rawFecha is String) fecha = DateTime.tryParse(rawFecha)?.toLocal();

      final partes = <String>[
        if (tipo != null && tipo.isNotEmpty) tipo,
        if (fecha != null) _fmt(fecha),
      ];

      out.add(_Aviso(
        id: id,
        colaborador:
            (nombre == null || nombre.isEmpty) ? 'Tu colaborador' : nombre,
        detalle: partes.join(' · '),
      ));
    }
    return out;
  }

  String _fmt(DateTime d) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }

  void _abrirChat(_Aviso a) {
    setState(() => _leidos.add(a.id));
    AppRoutes.push(context, ChatScreen(nombre: a.colaborador));
  }

  Future<void> _abrirCalificar(_Aviso a) async {
    final enviado = await AppRoutes.push<bool>(
      context,
      CalificarScreen(nombre: a.colaborador),
    );
    if (enviado == true && mounted) {
      setState(() => _calificados.add(a.id));
      showToast(context, '¡Gracias por tu calificación!',
          icon: Icons.cleaning_services_rounded);
    }
  }

  int get _sinLeer => _avisos.where((a) => !_leidos.contains(a.id)).length;

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
    if (_avisos.isNotEmpty) widgets.add(const SectionTitle('Hoy'));
    var i = 0;
    for (final a in _avisos) {
      widgets.add(FadeSlideIn(
        key: ValueKey('conf-${a.id}'),
        delay: FadeSlideIn.stagger(i++),
        child: _tarjetaConfirmado(a),
      ));
      widgets.add(const SizedBox(height: 12));
      widgets.add(FadeSlideIn(
        key: ValueKey('rate-${a.id}'),
        delay: FadeSlideIn.stagger(i++),
        child: _tarjetaCalificar(a),
      ));
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
                    onPressed: () => _abrirChat(a),
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 16),
                    label: const Text('Mensaje'),
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
    final calificado = _calificados.contains(a.id);
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
