import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A frosted, semi-transparent panel for content over gradients.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
    this.dark = false,
    this.blur = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Use a smoky tint (for dark backgrounds) instead of a milky one.
  final bool dark;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            color: dark
                ? Colors.white.withValues(alpha: .12)
                : Colors.white.withValues(alpha: .5),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .22 : .7),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A tappable glass pill with an emoji or icon and a label.
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    required this.onTap,
    this.leading,
    this.dark = false,
    this.foreground,
  });

  final String label;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool dark;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? (dark ? Colors.white : const Color(0xFF3B1424));
    return GlassPanel(
      dark: dark,
      radius: 30,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
