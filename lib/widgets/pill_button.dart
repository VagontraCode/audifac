import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/theme/app_colors.dart';

/// Rounded "Play" / "Shuffle" style action button.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = true,
    this.color,
    this.onColor,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  /// Overrides the fill (filled) or text color (outlined).
  final Color? color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fill = color ?? palette.ink;
    final foreground = filled ? (onColor ?? palette.onInk) : fill;
    return Material(
      color: filled ? fill : Colors.transparent,
      shape: StadiumBorder(
        side: filled ? BorderSide.none : BorderSide(color: palette.line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(icon: icon, color: foreground, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
