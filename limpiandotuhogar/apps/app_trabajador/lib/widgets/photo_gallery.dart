import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_modals.dart';
import 'buttons.dart';

/// Imagen desde assets o desde un archivo local (fotos elegidas por el usuario).
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.path,
    this.isAsset = true,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String path;
  final bool isAsset;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    Widget error(BuildContext c, Object e, StackTrace? s) => Container(
          color: AppColors.ice,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined,
              color: AppColors.inkMuted, size: 32),
        );
    return isAsset || path.startsWith('assets/')
        ? Image.asset(path,
            fit: fit, cacheWidth: cacheWidth, errorBuilder: error)
        : Image.file(File(path),
            fit: fit, cacheWidth: cacheWidth, errorBuilder: error);
  }
}

/// Nombre legible de la foto a partir del archivo (cocina.jpg → Cocina).
String photoCaption(String path) {
  final name = path.split('/').last.split('.').first;
  const map = {
    'cocina': 'Cocina',
    'bano': 'Baño',
    'sala': 'Sala',
    'recamara': 'Recámara',
    'oficina': 'Oficina',
    'departamento': 'Vista general',
  };
  return map[name] ?? 'Foto';
}

/// Galería a pantalla completa con zoom, deslizamiento e indicadores.
Future<void> showPhotoGallery(BuildContext context, List<String> photos,
    {int initial = 0}) {
  return showAppDialog<void>(
    context,
    builder: (ctx) => _Gallery(photos: photos, initial: initial),
  );
}

class _Gallery extends StatefulWidget {
  const _Gallery({required this.photos, required this.initial});

  final List<String> photos;
  final int initial;

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  late final PageController _controller =
      PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppDurations.fast,
                  child: Text(
                    '${photoCaption(widget.photos[_index])} · ${_index + 1} de ${widget.photos.length}',
                    key: ValueKey(_index),
                    style: AppText.heading,
                  ),
                ),
              ),
              CircleIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Cerrar',
                background: AppColors.ice,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 3,
                  child: AppImage(path: widget.photos[i]),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.photos.length, (i) {
              final active = i == _index;
              return GestureDetector(
                onTap: () => _controller.animateToPage(i,
                    duration: AppDurations.medium, curve: Curves.easeOutCubic),
                child: AnimatedContainer(
                  duration: AppDurations.medium,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 26 : 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primaryStrong : AppColors.fog,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('Pellizca para acercar',
              style: AppText.caption, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}

/// Fila horizontal de miniaturas que abre la galería.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.photos, this.height = 92});

  final List<String> photos;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (context, i) => const SizedBox(width: 10),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => showPhotoGallery(context, photos, initial: i),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: height * 1.3,
                  height: height,
                  child: AppImage(path: photos[i], cacheWidth: 360),
                ),
              ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.fade(AppColors.ink, 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(photoCaption(photos[i]),
                      style: AppText.caption
                          .copyWith(color: Colors.white, fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
