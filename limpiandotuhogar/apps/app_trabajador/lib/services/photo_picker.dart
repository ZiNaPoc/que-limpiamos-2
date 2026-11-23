import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_modals.dart';

/// Selección de fotos desde la cámara o la galería del dispositivo.
/// Las imágenes se usan solo localmente (no se suben a ningún servidor).
class PhotoPicker {
  PhotoPicker._();

  static final ImagePicker _picker = ImagePicker();

  static Future<String?> pick(BuildContext context, {required String title}) async {
    final source = await showAppSheet<ImageSource>(
      context,
      title: title,
      builder: (ctx) => Column(
        children: [
          _SourceTile(
            icon: Icons.photo_camera_outlined,
            label: 'Tomar foto',
            onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
          ),
          const SizedBox(height: 10),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            label: 'Elegir de la galería',
            onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
          ),
        ],
      ),
    );
    if (source == null) return null;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      return file?.path;
    } catch (_) {
      if (context.mounted) {
        showToast(context,
            'No se pudo abrir la ${source == ImageSource.camera ? 'cámara' : 'galería'}. Revisa los permisos del dispositivo.',
            error: true);
      }
      return null;
    }
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                    color: AppColors.ice, shape: BoxShape.circle),
                child: Icon(icon, color: AppColors.primaryStrong),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: AppText.subtitle)),
              const Icon(Icons.chevron_right_rounded, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
