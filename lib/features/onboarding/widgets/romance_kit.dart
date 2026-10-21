import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';

/// Shared look for the onboarding, account and lock screens: serif display
/// titles, pill buttons, a softly drifting page backdrop and frosted panels,
/// matching the Love notes and Home redesign.

/// A serif display style for emotional moments (titles, the couple's name).
TextStyle romanceSerif(TextStyle? base) => (base ?? const TextStyle()).copyWith(
  fontFamily: 'serif',
  fontFamilyFallback: [
    'Georgia',
    'Noto Serif',
    'Times New Roman',
    ...?base?.fontFamilyFallback,
  ],
);

/// A rounded pill [FilledButton] style in [preset]'s strong tone.
///
/// Only presets whose ink passes AA with white text are meant here (blush,
/// lavender, ocean, mint, festive, night). Pass [minimumSize] in Rows and
/// dialogs, where the theme's full-width default doesn't fit.
ButtonStyle pillButtonStyle(
  BuildContext context, {
  GradientPreset preset = GradientPreset.blush,
  Size minimumSize = const Size.fromHeight(54),
}) {
  final b = Theme.of(context).brightness;
  final dark = b == Brightness.dark;
  return FilledButton.styleFrom(
    minimumSize: minimumSize,
    backgroundColor: dark ? preset.accent(b) : preset.ink,
    foregroundColor: dark ? const Color(0xFF3B1424) : Colors.white,
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 24),
    textStyle: Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
    elevation: 0,
  );
}

/// A quiet pill [OutlinedButton] style for secondary actions on gradients.
ButtonStyle pillOutlineStyle(
  BuildContext context, {
  GradientPreset preset = GradientPreset.blush,
  Size minimumSize = const Size.fromHeight(54),
}) {
  final theme = Theme.of(context);
  final b = theme.brightness;
  final dark = b == Brightness.dark;
  return OutlinedButton.styleFrom(
    minimumSize: minimumSize,
    backgroundColor: Colors.white.withValues(alpha: dark ? .08 : .7),
    foregroundColor: dark ? theme.colorScheme.onSurface : preset.ink,
    side: BorderSide(
      color: dark
          ? Colors.white.withValues(alpha: .28)
          : preset.ink.withValues(alpha: .35),
    ),
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    textStyle: theme.textTheme.labelLarge?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// The preset's colours, softened towards the page so content cards still
/// stand out on top of it.
List<Color> softenedColors(
  BuildContext context,
  GradientPreset preset, {
  double strength = .6,
}) {
  final theme = Theme.of(context);
  return [
    for (final c in preset.colors(theme.brightness))
      Color.lerp(theme.scaffoldBackgroundColor, c, strength)!,
  ];
}

/// A full-page, slowly drifting gradient behind [child], with optional
/// floating hearts. [child] is usually a transparent [Scaffold].
class RomanceBackdrop extends StatelessWidget {
  const RomanceBackdrop({
    super.key,
    required this.child,
    this.preset = GradientPreset.blush,
    this.hearts = false,
    this.heartCount = 12,
    this.strength = .6,
  });

  final Widget child;
  final GradientPreset preset;
  final bool hearts;
  final int heartCount;

  /// How much of the preset shows through the page colour (0–1).
  final double strength;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedGradientBackground(
            preset: preset,
            colors: softenedColors(context, preset, strength: strength),
            duration: const Duration(seconds: 14),
          ),
        ),
        if (hearts)
          Positioned.fill(
            child: FloatingHearts(
              count: heartCount,
              color: dark ? preset.accent(Brightness.dark) : Colors.white,
              opacity: dark ? .22 : .8,
              duration: const Duration(seconds: 18),
            ),
          ),
        child,
      ],
    );
  }
}

/// An [AppBar] that lets a [RomanceBackdrop] show through.
AppBar romanceAppBar({
  Widget? title,
  Widget? leading,
  bool automaticallyImplyLeading = false,
  List<Widget>? actions,
}) => AppBar(
  automaticallyImplyLeading: automaticallyImplyLeading,
  leading: leading,
  title: title,
  actions: actions,
  backgroundColor: Colors.transparent,
  surfaceTintColor: Colors.transparent,
  scrolledUnderElevation: 0,
);

/// A frosted panel for forms over a [RomanceBackdrop]. Text fields inside get
/// a brighter fill so they read clearly on the glass.
class FrostedForm extends StatelessWidget {
  const FrostedForm({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 20, 18, 20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return GlassPanel(
      dark: dark,
      radius: 28,
      padding: padding,
      child: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            fillColor: dark
                ? Colors.black.withValues(alpha: .28)
                : Colors.white.withValues(alpha: .85),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A round badge on [preset]'s gradient with a softly pulsing glow, for the
/// top of a screen (a heart, a lock).
class GlowBadge extends StatelessWidget {
  const GlowBadge({
    super.key,
    this.icon = Icons.favorite_rounded,
    this.preset = GradientPreset.blush,
    this.size = 76,
    this.child,
  });

  final IconData icon;
  final GradientPreset preset;
  final double size;

  /// Shown instead of [icon] when given.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final accent = preset.accent(b);
    final inner = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.colors(b),
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: b == Brightness.dark ? .2 : .9),
          width: 2,
        ),
      ),
      child:
          child ??
          Icon(
            icon,
            size: size * .46,
            color: b == Brightness.dark ? accent : preset.ink,
          ),
    );
    return RepaintBoundary(
      child: Pulse(
        duration: const Duration(milliseconds: 2200),
        child: inner,
        builder: (context, v, child) => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .22 + .18 * v),
                blurRadius: 18 + 12 * v,
                spreadRadius: 1 + 4 * v,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A rounded square with an icon on a translucent white tile, for rows on
/// gradient cards.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.preset,
    this.size = 44,
  });

  final IconData icon;
  final GradientPreset preset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final dark = preset.isDarkIn(b);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: dark ? .13 : .7),
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(
        icon,
        size: size * .5,
        color: dark ? preset.accent(b) : preset.ink,
      ),
    );
  }
}

/// Staggers a list's children in with [EntranceAnimation].
List<Widget> staggered(List<Widget> children, {int start = 0}) => [
  for (var i = 0; i < children.length; i++)
    EntranceAnimation(index: start + i, child: children[i]),
];

/// A soft gradient halo ring around [child] (an avatar or photo picker).
class GlowRing extends StatelessWidget {
  const GlowRing({
    super.key,
    required this.child,
    this.preset = GradientPreset.blush,
    this.width = 4,
  });

  final Widget child;
  final GradientPreset preset;
  final double width;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final dark = b == Brightness.dark;
    final a = dark ? preset.accent(b) : preset.ink;
    final c = dark
        ? GradientPreset.lavender.accent(b)
        : GradientPreset.lavender.ink;
    return Container(
      padding: EdgeInsets.all(width),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [a, c, a.withValues(alpha: .5), a]),
        boxShadow: [
          BoxShadow(
            color: a.withValues(alpha: .28),
            blurRadius: 22,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: child,
      ),
    );
  }
}

/// The top of a bottom sheet: a glowing badge, a serif title and an
/// optional line under it.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.preset = GradientPreset.blush,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final GradientPreset preset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Row(
        children: [
          GlowBadge(icon: icon, preset: preset, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: romanceSerif(theme.textTheme.headlineSmall).copyWith(
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft gradient section card holding list rows ([ListTile],
/// [SwitchListTile]…), which take the preset's readable colours.
class GradientGroup extends StatelessWidget {
  const GradientGroup({
    super.key,
    required this.children,
    this.preset = GradientPreset.blush,
    this.animate = true,
  });

  final List<Widget> children;
  final GradientPreset preset;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final darkCard = preset.isDarkIn(b);
    final accent = darkCard ? preset.accent(b) : preset.ink;
    final fg = preset.foreground(b);
    final muted = preset.foregroundMuted(b);
    return AnimatedGradientCard(
      preset: preset,
      animate: animate,
      sheen: false,
      radius: 24,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Theme(
        data: theme.copyWith(
          dividerColor: Colors.transparent,
          listTileTheme: theme.listTileTheme.copyWith(
            iconColor: accent,
            textColor: fg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
              color: muted,
            ),
          ),
          expansionTileTheme: theme.expansionTileTheme.copyWith(
            iconColor: accent,
            collapsedIconColor: muted,
            textColor: fg,
            collapsedTextColor: fg,
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? (darkCard ? const Color(0xFF2A1220) : Colors.white)
                  : null,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? accent : null,
            ),
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? accent : null,
            ),
          ),
          radioTheme: RadioThemeData(
            fillColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.disabled)
                  ? muted.withValues(alpha: .45)
                  : s.contains(WidgetState.selected)
                  ? accent
                  : muted,
            ),
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
