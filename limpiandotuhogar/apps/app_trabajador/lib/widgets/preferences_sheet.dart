import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_modals.dart';
import 'common.dart';

/// Preferencias del trabajador. Los cambios se guardan al momento.
Future<void> showPreferencesSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    title: 'Preferencias',
    builder: (ctx) => const _PreferencesBody(),
  );
}

class _PreferencesBody extends StatelessWidget {
  const _PreferencesBody();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final p = state.profile.preferences;

    Widget switchTile(String title, String subtitle, bool value,
            ValueChanged<bool> onChanged) =>
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: SwitchListTile(
            value: value,
            onChanged: onChanged,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
            title: Text(title, style: AppText.subtitle),
            subtitle: Text(subtitle, style: AppText.caption),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Se guardan automáticamente en este dispositivo.',
            style: AppText.caption),
        const SizedBox(height: 12),
        switchTile(
          'Alertas de notificaciones',
          'Muestra el contador de avisos nuevos.',
          p.notificationsEnabled,
          (v) => state.updatePreferences(p.copyWith(notificationsEnabled: v)),
        ),
        switchTile(
          'Vibración al tocar',
          'Respuesta táctil en botones y acciones.',
          p.soundsEnabled,
          (v) => state.updatePreferences(p.copyWith(soundsEnabled: v)),
        ),
        switchTile(
          'Solo dentro de mi horario',
          'Oculta solicitudes fuera de tu horario de disponibilidad.',
          p.onlyWithinSchedule,
          (v) => state.updatePreferences(p.copyWith(onlyWithinSchedule: v)),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Distancia máxima', style: AppText.subtitle)),
                  Pill(label: '${p.maxDistanceKm.round()} km'),
                ],
              ),
              Text('Solo verás solicitudes dentro de esta distancia.',
                  style: AppText.caption),
              Slider(
                value: p.maxDistanceKm.clamp(2, 20).toDouble(),
                min: 2,
                max: 20,
                divisions: 18,
                activeColor: AppColors.primaryStrong,
                inactiveColor: AppColors.frost,
                label: '${p.maxDistanceKm.round()} km',
                onChanged: (v) =>
                    state.updatePreferences(p.copyWith(maxDistanceKm: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: AppDurations.medium,
          child: state.hiddenByPreferences > 0
              ? NoticeBox(
                  key: ValueKey(state.hiddenByPreferences),
                  icon: Icons.filter_alt_outlined,
                  message:
                      '${state.hiddenByPreferences} solicitud(es) disponible(s) quedan ocultas con estas preferencias.',
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
