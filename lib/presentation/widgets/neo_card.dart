import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Card estruturado com Material Design 3, fundo claro contrastante, contorno escuro bem definido
/// (#1E293B), cantos arredondados e faixa superior opcional de destaque.
class NeoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color? topAccentColor;
  final double borderRadius;
  final bool showHardShadow;
  final VoidCallback? onTap;

  const NeoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor = AppColors.cardSurface,
    this.topAccentColor,
    this.borderRadius = 16,
    this.showHardShadow = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.darkOutline, width: 1.8),
        boxShadow: showHardShadow
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x1F1E293B),
                  offset: Offset(0, 3),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 1.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (topAccentColor != null)
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: topAccentColor,
                  border: const Border(
                    bottom: BorderSide(color: AppColors.darkOutline, width: 1.4),
                  ),
                ),
              ),
            Padding(
              padding: padding,
              child: child,
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      ),
    );
  }
}
