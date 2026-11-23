import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Interruptor de disponibilidad con etiqueta («Activa» / «Inactiva»).
class AvailabilityToggle extends StatelessWidget {
  const AvailabilityToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.large = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final width = large ? 148.0 : 112.0;
    final height = large ? 50.0 : 34.0;
    final knob = height - 8;
    return Semantics(
      toggled: value,
      label: 'Disponibilidad',
      child: GestureDetector(
        onTap: () {
          Haptics.tap(context);
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: Curves.easeOutCubic,
          width: width,
          height: height,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: value ? AppColors.mint : AppColors.cloud,
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
                color: value ? AppColors.seafoam : AppColors.fog, width: 1.2),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: AppDurations.medium,
                curve: Curves.easeOutBack,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: knob,
                  height: knob,
                  decoration: BoxDecoration(
                    color: value ? AppColors.successFg : AppColors.inkMuted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    value ? Icons.check_rounded : Icons.pause_rounded,
                    color: Colors.white,
                    size: knob * 0.6,
                  ),
                ),
              ),
              AnimatedAlign(
                duration: AppDurations.medium,
                alignment: value ? const Alignment(-0.55, 0) : const Alignment(0.6, 0),
                child: Text(
                  value ? 'Activa' : 'Inactiva',
                  style: AppText.label.copyWith(
                    fontSize: large ? 15 : 12,
                    fontWeight: FontWeight.w700,
                    color: value ? AppColors.successFg : AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
