import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/haptics.dart';
import '../services/resenas_reportes_api.dart';
import '../services/validaciones_contenido.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_modals.dart';
import '../widgets/app_text_field.dart';
import '../widgets/buttons.dart';
import '../widgets/common.dart';
import '../widgets/organic.dart';
import '../widgets/wave_background.dart';
import 'app_bottom_nav.dart';

/// Califica al trabajador de UN servicio finalizado (POST /api/cliente/solicitudes/:id/resena).
/// El servidor decide si se puede (finalizado, 168 h, una sola vez): la app solo muestra su respuesta.
/// Devuelve `true` al cerrar si la reseña se guardó.
class CalificarScreen extends StatefulWidget {
  const CalificarScreen({super.key, required this.solicitudId, this.nombre = 'Colaborador'});

  final int solicitudId;
  final String nombre;

  @override
  State<CalificarScreen> createState() => _CalificarScreenState();
}

class _CalificarScreenState extends State<CalificarScreen> {
  static const _etiquetas = ['Mala', 'Regular', 'Buena', 'Muy buena', 'Excelente'];
  // Errores del servidor que significan que este servicio ya no se puede calificar.
  static const _definitivos = {'RESENA_DUPLICADA', 'PLAZO_VENCIDO', 'SERVICIO_NO_FINALIZADO', 'NO_ES_PARTE'};

  int _rating = 0;
  final TextEditingController _comentario = TextEditingController();
  bool _enviando = false;
  String? _error;
  bool _bloqueado = false;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  String get _iniciales {
    final partes = widget.nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Future<void> _enviar() async {
    if (_enviando || _bloqueado) return; // evita envíos repetidos
    final invalido = validarResena(puntuacion: _rating, comentario: _comentario.text);
    if (invalido != null) {
      setState(() => _error = invalido);
      showToast(context, invalido, error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ResenasApi.calificarTrabajador(widget.solicitudId, puntuacion: _rating, comentario: _comentario.text);
      if (!mounted) return;
      Haptics.success(context);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final mensaje = mensajeDeError(e);
      setState(() {
        _enviando = false;
        _error = mensaje;
        _bloqueado = e is ApiException && _definitivos.contains(e.codigo);
      });
      showToast(context, mensaje, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context) + 6;

    return Scaffold(
      extendBody: true,
      body: WaveBackground(
        headerHeight: 230,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, MediaQuery.paddingOf(context).top + 8, pad, AppBottomNav.reservedHeight(context)),
          children: [
            Row(
              children: [
                CircleIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Regresar',
                  background: AppColors.fade(Colors.white, 0.8),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                const AppLogo(size: 44),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: FadeSlideIn(
                child: BlobAvatar(
                  seed: widget.nombre.codeUnits.fold<int>(0, (a, b) => a + b),
                  initials: _iniciales,
                  icon: _iniciales.isEmpty ? Icons.person_rounded : null,
                  size: 140,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(widget.nombre, textAlign: TextAlign.center, style: AppText.display),
            const SizedBox(height: 24),
            Text('Califica tu servicio', style: AppText.heading),
            const SizedBox(height: 12),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: BroomRating(
                  value: _rating,
                  size: 34,
                  onChanged: _enviando || _bloqueado ? null : (v) => setState(() => _rating = v),
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: AppDurations.fast,
              child: Text(
                _rating == 0 ? 'Toca las escobas para calificar' : _etiquetas[_rating - 1],
                key: ValueKey(_rating),
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(color: _rating == 0 ? AppColors.inkMuted : AppColors.successFg),
              ),
            ),
            const SizedBox(height: 22),
            Text('Cuéntanos cómo te fue', style: AppText.heading),
            const SizedBox(height: 10),
            AppTextField(
              controller: _comentario,
              hint: 'Escribe un comentario (opcional)',
              maxLines: 7,
              maxLength: kMaxComentario,
              editable: !_enviando && !_bloqueado,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            Text(
              'Tu calificación se publica de inmediato y no podrás editarla. '
              'El trabajador verá la calificación y el comentario, pero no quién la escribió.',
              style: AppText.caption,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _bloqueado ? NoticeBox.warning(message: _error!) : NoticeBox.error(message: _error!),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Enviar calificación',
                icon: Icons.send_rounded,
                expand: false,
                loading: _enviando,
                onPressed: _enviando || _bloqueado ? null : _enviar,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}
