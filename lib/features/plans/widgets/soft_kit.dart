import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

/// Small building blocks shared by the Plans, Memories and Calendar screens,
/// in the style of the Love notes / Home redesign: soft gradient-tinted
/// rows, gradient-ruled section headers, illustrated empty states and a
/// light gradient strip on top of editors.

/// Text-safe accent for [preset]: the light accent darkened a little so
/// small text on pastel gradients stays above 4.5:1; the dark accent is a
/// light glow that already reads well on deep gradients.
Color presetAccentText(GradientPreset preset, Brightness b) =>
    preset.isDarkIn(b)
    ? preset.accentDark
    : Color.lerp(preset.accentLight, Colors.black, .28)!;

/// [preset]'s colours softened toward the page [surface] by [strength]
/// (1 = the full pastel).
List<Color> tintedColors(
  GradientPreset preset,
  Brightness b,
  Color surface, {
  double strength = .75,
}) => [for (final c in preset.colors(b)) Color.lerp(surface, c, strength)!];

/// A static, softly tinted gradient card for list rows. Optionally ringed by
/// a thin gradient [edge] in the preset's accent tones.
class TintedCard extends StatelessWidget {
  const TintedCard({
    super.key,
    required this.child,
    this.preset = GradientPreset.blush,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    this.radius = 20,
    this.strength = .75,
    this.edge = false,
    this.glow,
    this.muted = false,
  });

  final Widget child;
  final GradientPreset preset;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  /// How much of the preset shows through (0 = plain surface).
  final double strength;

  /// A thin gradient outline.
  final bool edge;

  /// A soft coloured halo, e.g. for something that needs attention.
  final Color? glow;

  /// Quiet look for finished / received items.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = theme.brightness;
    final dark = b == Brightness.dark;
    final r = BorderRadius.circular(radius);
    final colors = muted
        ? [
            scheme.surfaceContainerHighest.withValues(alpha: .55),
            scheme.surfaceContainerHigh.withValues(alpha: .55),
          ]
        : tintedColors(
            preset,
            b,
            theme.scaffoldBackgroundColor,
            strength: strength,
          );
    final accent = preset.accent(b);

    final shadows = [
      if (!muted && !dark)
        BoxShadow(
          color: preset.light[1].withValues(alpha: .35),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      if (glow != null)
        BoxShadow(
          color: glow!.withValues(alpha: .35),
          blurRadius: 20,
          spreadRadius: 1,
        ),
    ];

    // Shadows sit outside the Material: ink decorations are clipped to it.
    final card = DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: shadows),
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: edge && !muted
                ? Border.all(
                    color: accent.withValues(alpha: dark ? .45 : .28),
                    width: 1.2,
                  )
                : null,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: r,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
    return Padding(padding: margin, child: card);
  }
}

/// A square badge holding an emoji, frosted when it sits on a gradient and
/// tinted with [preset] when it sits on the page.
class EmojiBadge extends StatelessWidget {
  const EmojiBadge({
    super.key,
    required this.emoji,
    this.preset = GradientPreset.blush,
    this.size = 46,
    this.onGradient = true,
  });

  final String emoji;
  final GradientPreset preset;
  final double size;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final dark = preset.isDarkIn(b);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .32),
        color: onGradient
            ? Colors.white.withValues(alpha: dark ? .14 : .7)
            : null,
        gradient: onGradient
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: preset.colors(b),
              ),
        border: Border.all(
          color: Colors.white.withValues(alpha: dark ? .16 : .8),
        ),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * .48, height: 1.1)),
    );
  }
}

/// A small coloured heading between list sections, with an optional count
/// pill and a soft gradient rule trailing off after it.
class SoftSectionHeader extends StatelessWidget {
  const SoftSectionHeader({
    super.key,
    required this.label,
    this.count,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 10),
    this.color,
    this.trailing,
  });

  final String label;
  final int? count;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: c,
              ),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: c.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: c,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1.2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.withValues(alpha: .35), c.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// A friendly empty state: an emoji on a soft gradient blob, an optional
/// [title], the [text] and an optional [action].
class GradientEmptyState extends StatelessWidget {
  const GradientEmptyState({
    super.key,
    required this.emoji,
    required this.text,
    this.title,
    this.preset = GradientPreset.blush,
    this.action,
    this.padding = const EdgeInsets.all(32),
    this.scrollable = false,
  });

  /// Scrolls when it doesn't fit (large text, small phones). Leave off when
  /// the parent already scrolls or measures intrinsic height.
  final bool scrollable;

  final String emoji;
  final String? title;
  final String text;
  final GradientPreset preset;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final colors = preset.colors(b);

    final content = Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EntranceAnimation(
            child: SizedBox(
              width: 132,
              height: 116,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Two overlapping soft blobs.
                  Positioned(
                    left: 6,
                    top: 4,
                    child: _Blob(
                      size: 96,
                      colors: [colors[0], colors[1]],
                      radius: const BorderRadius.only(
                        topLeft: Radius.circular(56),
                        topRight: Radius.circular(40),
                        bottomLeft: Radius.circular(36),
                        bottomRight: Radius.circular(58),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 2,
                    child: _Blob(
                      size: 70,
                      colors: [colors[2], colors[1]],
                      radius: BorderRadius.circular(35),
                      opacity: .8,
                    ),
                  ),
                  Text(emoji, style: const TextStyle(fontSize: 46)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (title != null) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    );
    if (!scrollable) return Center(child: content);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.size,
    required this.colors,
    required this.radius,
    this.opacity = 1,
  });

  final double size;
  final List<Color> colors;
  final BorderRadius radius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      ),
    );
  }
}

/// A compact gradient strip at the top of an editor form: an emoji badge
/// and a short line of encouragement. Decorative only.
class EditorHeaderStrip extends StatelessWidget {
  const EditorHeaderStrip({
    super.key,
    required this.emoji,
    required this.text,
    this.preset = GradientPreset.blush,
  });

  final String emoji;
  final String text;
  final GradientPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return ExcludeSemantics(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: preset.colors(b),
          ),
        ),
        child: Row(
          children: [
            EmojiBadge(emoji: emoji, preset: preset, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: preset.foreground(b),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section label inside an editor form, with a small accent dot.
class SoftFieldLabel extends StatelessWidget {
  const SoftFieldLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme.primary;
    return Padding(
      padding: padding ?? const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [c, c.withValues(alpha: .45)]),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded progress bar filled with [preset]'s accent gradient, easing to
/// [fraction] when it changes.
class GradientProgressBar extends StatelessWidget {
  const GradientProgressBar({
    super.key,
    required this.fraction,
    this.preset = GradientPreset.blush,
    this.height = 10,
    this.track,
  });

  final double fraction;
  final GradientPreset preset;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final accent = preset.accent(b);
    final fill = [
      Color.lerp(accent, Colors.white, b == Brightness.dark ? .0 : .25)!,
      accent,
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        height: height,
        decoration: BoxDecoration(
          color:
              track ??
              Colors.white.withValues(alpha: preset.isDarkIn(b) ? .14 : .6),
          borderRadius: BorderRadius.circular(height),
        ),
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: fraction.clamp(0, 1)),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Container(
            width: v == 0 ? 0 : (constraints.maxWidth * v).clamp(height, 1e9),
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: LinearGradient(colors: fill),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small rounded label filled with [preset]'s accent gradient.
class GradientPill extends StatelessWidget {
  const GradientPill({
    super.key,
    required this.text,
    this.preset = GradientPreset.blush,
    this.icon,
  });

  final String text;
  final GradientPreset preset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final dark = b == Brightness.dark;
    // Deep accent tones in light mode carry white text; in dark mode the
    // accent is a light glow, so the text goes deep.
    final base = dark ? preset.accentDark : preset.accentLight;
    final fg = dark ? const Color(0xFF2A1020) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            Color.lerp(base, Colors.black, dark ? 0 : .12)!,
            Color.lerp(base, dark ? Colors.white : Colors.black, .12)!,
          ],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A one-time staggered entrance for the first few rows of a list. Rows
/// further down (usually built as they scroll in) appear without one, so
/// scrolling never replays a cascade.
Widget stagger(int index, Widget child, {Key? key}) => index < 8
    ? EntranceAnimation(key: key, index: index, child: child)
    : KeyedSubtree(key: key, child: child);

/// [stagger] over a list of rows, keeping each row's key.
List<Widget> staggered(Iterable<Widget> children, {int start = 0}) {
  var i = start;
  return [
    for (final c in children)
      stagger(i++, c, key: c.key == null ? null : ValueKey(c.key)),
  ];
}

/// A soft gradient panel at the top of a details sheet, around its title.
class SheetGradientHeader extends StatelessWidget {
  const SheetGradientHeader({
    super.key,
    required this.child,
    this.preset = GradientPreset.blush,
  });

  final Widget child;
  final GradientPreset preset;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.colors(b),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: preset.foreground(b)),
        child: IconTheme.merge(
          data: IconThemeData(color: preset.accent(b)),
          child: child,
        ),
      ),
    );
  }
}
