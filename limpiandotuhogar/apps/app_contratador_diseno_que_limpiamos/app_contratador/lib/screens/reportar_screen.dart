import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
import '../widgets/flow_widgets.dart';
import '../widgets/wave_background.dart';

/// Foto elegida para el reporte, con su tipo REAL detectado por sus bytes.
class _Foto {
  _Foto(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

/// Reporta al trabajador de UN servicio (POST /api/cliente/solicitudes/:id/reportes, multipart).
/// Tipo, descripción y fotos son opcionales. Máx. 5 fotos, 8 MB c/u y 16 MB en total (JPEG, PNG o WebP).
/// Solo tú y la administración verán el reporte. Devuelve `true` si se envió.
class ReportarScreen extends StatefulWidget {
  const ReportarScreen({super.key, required this.solicitudId, required this.servicio});

  final int solicitudId;
  final String servicio;

  @override
  State<ReportarScreen> createState() => _ReportarScreenState();
}

class _ReportarScreenState extends State<ReportarScreen> {
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

  int get _totalBytes => _fotos.fold(0, (s, f) => s + f.bytes.length);

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
      final error = ext == null
          ? 'Solo se admiten fotografías JPEG, PNG o WebP.'
          : validarFotos([..._fotos.map((f) => f.bytes), bytes]);
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
    if (_enviando) return; // evita envíos repetidos
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
    final pad = AppSpacing.screen(context);
    return Scaffold(
      body: WaveBackground(
        headerHeight: 200,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, MediaQuery.paddingOf(context).bottom + 28),
          children: [
            StepHeader(title: 'Reportar un problema', subtitle: widget.servicio),
            const SizedBox(height: 14),
            const NoticeBox(message: 'Solo tú y la administración verán este reporte. La otra persona no podrá consultarlo ni saber quién lo hizo.'),
            const SizedBox(height: 18),
            Text('¿Qué pasó?', style: AppText.heading),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in kTiposDeReporte.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _tipo == e.key,
                    onSelected: _enviando ? null : (_) => setState(() => _tipo = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Descripción (opcional)', style: AppText.heading),
            const SizedBox(height: 10),
            AppTextField(
              controller: _descripcion,
              hint: 'Cuéntanos qué ocurrió',
              maxLines: 5,
              editable: !_enviando,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text('Fotografías (opcional)', style: AppText.heading)),
                Text('${_fotos.length}/$kMaxFotos · ${megas(_totalBytes)} de 16 MB', style: AppText.caption),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _fotos.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Image.memory(_fotos[i].bytes, width: 92, height: 92, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 92, height: 92, color: AppColors.frost, child: const Icon(Icons.broken_image_outlined))),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Material(
                          color: AppColors.fade(Colors.black, 0.55),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _enviando ? null : () => setState(() => _fotos.removeAt(i)),
                            child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 16, color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_fotos.length < kMaxFotos)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: _enviando || _eligiendo ? null : _agregarFoto,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.primary, width: 1.2),
                      ),
                      child: _eligiendo
                          ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                          : const Icon(Icons.add_a_photo_outlined, color: AppColors.primaryStrong),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('JPEG, PNG o WebP · máx. 8 MB por foto y 16 MB en total.', style: AppText.caption),
            if (_error != null) ...[
              const SizedBox(height: 14),
              NoticeBox.error(message: _error!),
            ],
            if (_enviando) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              Text(_fotos.isEmpty ? 'Enviando reporte…' : 'Enviando reporte con ${_fotos.length} foto${_fotos.length == 1 ? '' : 's'}…', style: AppText.caption),
            ],
            const SizedBox(height: 20),
            AppButton(
              label: 'Enviar reporte',
              icon: Icons.flag_outlined,
              loading: _enviando,
              onPressed: _enviando ? null : _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
