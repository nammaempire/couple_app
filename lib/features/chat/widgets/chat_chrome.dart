import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:couple_app/features/chat/widgets/chat_palette.dart';

/// A frosted pill or card that floats over the chat background, tinted by
/// the chat's [ChatPalette]. Used for the composer and the pinned bar.
class ChatGlass extends StatelessWidget {
  const ChatGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final palette = ChatPalette.of(context);
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: palette.glow.withValues(alpha: .16),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: palette.glass,
              borderRadius: r,
              border: Border.all(color: palette.glassBorder),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A round badge filled with the chat's accent gradient, for icons in
/// sheets, the send button and the pinned bar.
class GradientBadge extends StatelessWidget {
  const GradientBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize,
    this.colors,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final double? iconSize;

  /// Overrides the accent gradient (e.g. for destructive actions).
  final List<Color>? colors;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final palette = ChatPalette.of(context);
    final colors = this.colors ?? palette.accentGradient;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ChatPalette.diagonal(colors),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: .28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        icon,
        size: iconSize ?? size * .5,
        color: foreground ?? palette.onAccent,
      ),
    );
  }
}

/// The top of every chat sheet: a gradient grab handle and, optionally, a
/// title with a gradient icon badge. Sheets using it are opened with
/// `showDragHandle: false`.
class ChatSheetHeader extends StatelessWidget {
  const ChatSheetHeader({super.key, this.title, this.icon, this.subtitle});

  final String? title;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ChatPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12, bottom: 14),
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(colors: palette.accentGradient),
            ),
          ),
        ),
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                if (icon != null) ...[
                  GradientBadge(icon: icon!, size: 38),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title!,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A soft wash of the chat colour at the top of a sheet, fading into the
/// sheet's surface. Open the sheet with `clipBehavior: Clip.antiAlias`.
class ChatSheetBackground extends StatelessWidget {
  const ChatSheetBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ChatPalette.of(context);
    final surface = Theme.of(context).colorScheme.surfaceContainerLow;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          stops: const [0, .3, .65],
          colors: [
            palette.headerGradient.first,
            palette.headerGradient.last,
            surface,
          ],
        ),
      ),
      child: child,
    );
  }
}

/// A rounded, tinted option row for chat sheets, with a gradient icon
/// badge. [destructive] switches to the error colours.
class ChatSheetOption extends StatelessWidget {
  const ChatSheetOption({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
    this.trailing,
    this.titleMaxLines,
  });

  final IconData icon;
  final String title;

  /// Clamps a long title (e.g. a pinned message) with an ellipsis.
  final int? titleMaxLines;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final titleColor = destructive ? scheme.error : scheme.onSurface;
    final r = BorderRadius.circular(20);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: dark
            ? Colors.white.withValues(alpha: .06)
            : Colors.white.withValues(alpha: .72),
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(
            color: destructive
                ? scheme.error.withValues(alpha: .25)
                : Colors.white.withValues(alpha: dark ? .08 : .9),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                GradientBadge(
                  icon: icon,
                  size: 38,
                  iconSize: 20,
                  colors: destructive
                      ? [
                          scheme.error,
                          Color.lerp(scheme.error, scheme.tertiary, .35)!,
                        ]
                      : null,
                  foreground: destructive ? scheme.onError : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: titleMaxLines,
                        overflow: titleMaxLines == null
                            ? null
                            : TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: titleColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
