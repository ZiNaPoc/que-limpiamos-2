import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/service_request.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_modals.dart';
import 'buttons.dart';
import 'common.dart';

/// Modal con el perfil del cliente. Los datos de contacto completos se
/// muestran solo cuando el trabajador ya aceptó la oportunidad.
Future<void> showClientProfile(BuildContext context, ServiceRequest r) {
  return showAppDialog<void>(
    context,
    builder: (ctx) => _ClientProfileCard(request: r),
  );
}

String _mask(String value, {int visible = 2}) {
  if (value.length <= visible) return value;
  return '${'•' * (value.length - visible)}${value.substring(value.length - visible)}';
}

String _maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 1) return email;
  return '${email[0]}${'•' * (at - 1)}${email.substring(at)}';
}

class _ClientProfileCard extends StatelessWidget {
  const _ClientProfileCard({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final c = request.client;
    final reveal = request.status != RequestStatus.disponible &&
        !request.takenByOther;

    Widget field(String label, String value, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.label),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(value,
                          style: AppText.bodyStrong
                              .copyWith(color: AppColors.primaryStrong)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.aqua, AppColors.seafoam],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(c.initials,
                    style: AppText.display.copyWith(fontSize: 32)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.firstName.toUpperCase(),
                        style: AppText.heading.copyWith(fontSize: 18)),
                    Text(c.lastName.toUpperCase(),
                        style: AppText.heading.copyWith(fontSize: 18)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.cleaning_services_rounded,
                            size: 16, color: AppColors.successFg),
                        const SizedBox(width: 4),
                        Text(c.rating.toStringAsFixed(1),
                            style: AppText.label),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text('${c.servicesRequested} servicios',
                              style: AppText.caption),
                        ),
                      ],
                    ),
                    Text('Cliente desde ${c.memberSince}',
                        style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          field('Número telefónico', reveal ? c.phone : _mask(c.phone),
              Icons.phone_outlined),
          field('Correo electrónico', reveal ? c.email : _maskEmail(c.email),
              Icons.mail_outline_rounded),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              children: [
                const Icon(Icons.badge_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('INE',
                      style: AppText.label.copyWith(color: Colors.white)),
                ),
                Pill(
                  label: c.ineVerified ? 'Verificada' : 'En revisión',
                  background: c.ineVerified ? AppColors.mint : AppColors.warningBg,
                  foreground:
                      c.ineVerified ? AppColors.successFg : AppColors.warningFg,
                  dense: true,
                ),
              ],
            ),
          ),
          if (!reveal) ...[
            const SizedBox(height: 12),
            const NoticeBox(
              icon: Icons.lock_outline_rounded,
              message:
                  'Los datos de contacto completos se muestran cuando aceptas la oportunidad.',
            ),
          ],
          const SizedBox(height: 18),
          if (reveal)
            AppButton(
              label: 'Copiar teléfono',
              icon: Icons.copy_rounded,
              variant: AppButtonVariant.outline,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: c.phone));
                if (context.mounted) {
                  showToast(context, 'Teléfono copiado al portapapeles.');
                  Navigator.of(context).pop();
                }
              },
            ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cerrar',
                style: AppText.label.copyWith(color: AppColors.inkSoft)),
          ),
        ],
      ),
    );
  }
}
