import 'package:flutter/material.dart';

import '../services/haptics.dart';
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

class CalificarScreen extends StatefulWidget {
  const CalificarScreen({super.key, this.nombre = 'Colaborador'});

  final String nombre;

  @override
  State<CalificarScreen> createState() => _CalificarScreenState();
}

class _CalificarScreenState extends State<CalificarScreen> {
  static const _etiquetas = [
    'Mala',
    'Regular',
    'Buena',
    'Muy buena',
    'Excelente',
  ];

  int _rating = 0;
  final TextEditingController _comentario = TextEditingController();

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  String get _iniciales {
    final partes = widget.nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty);
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  void _enviar() {
    if (_rating == 0) {
      showToast(context, 'Elige de 1 a 5 escobas', error: true);
      return;
    }
    // Simulado: no se guarda nada, solo regresa a Avisos
    FocusScope.of(context).unfocus();
    Haptics.success(context);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.screen(context) + 6;

    return Scaffold(
      extendBody: true,
      body: WaveBackground(
        headerHeight: 230,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, MediaQuery.paddingOf(context).top + 8,
              pad, AppBottomNav.reservedHeight(context)),
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
            Text(widget.nombre,
                textAlign: TextAlign.center, style: AppText.display),
            const SizedBox(height: 24),
            Text('Califica tu servicio', style: AppText.heading),
            const SizedBox(height: 12),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: BroomRating(
                  value: _rating,
                  size: 34,
                  onChanged: (v) => setState(() => _rating = v),
                ),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: AppDurations.fast,
              child: Text(
                _rating == 0
                    ? 'Toca las escobas para calificar'
                    : _etiquetas[_rating - 1],
                key: ValueKey(_rating),
                textAlign: TextAlign.center,
                style: AppText.label.copyWith(
                    color: _rating == 0
                        ? AppColors.inkMuted
                        : AppColors.successFg),
              ),
            ),
            const SizedBox(height: 22),
            Text('Cuéntanos cómo te fue', style: AppText.heading),
            const SizedBox(height: 10),
            AppTextField(
              controller: _comentario,
              hint: 'Escribe un comentario (opcional)',
              maxLines: 7,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Enviar calificación',
                icon: Icons.send_rounded,
                expand: false,
                onPressed: _enviar,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
    );
  }
}
