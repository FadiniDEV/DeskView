import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum VibrantButtonVariant {
  vibrantGreen,
  secondaryWhite,
  accentBlue,
  dangerRed,
}

/// Botão destacado com contorno escuro bem definido, cantos arredondados e feedback visual.
class VibrantButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final VibrantButtonVariant variant;
  final bool compact;

  const VibrantButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = VibrantButtonVariant.vibrantGreen,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (variant) {
      VibrantButtonVariant.vibrantGreen => (AppColors.vibrantGreen, AppColors.onVibrantGreen),
      VibrantButtonVariant.secondaryWhite => (AppColors.cardSurface, AppColors.textPrimary),
      VibrantButtonVariant.accentBlue => (AppColors.accentBlue, Colors.white),
      VibrantButtonVariant.dangerRed => (AppColors.dangerRed, Colors.white),
    };

    final ButtonStyle style = ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 18,
        vertical: compact ? 10 : 14,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.darkOutline, width: 1.8),
      ),
      textStyle: TextStyle(
        fontSize: compact ? 12.5 : 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon, size: compact ? 16 : 18, color: fg),
        label: Text(label),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}
