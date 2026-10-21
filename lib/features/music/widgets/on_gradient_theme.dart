import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';

/// Retunes the theme for content laid straight onto a [GradientPreset]
/// background: text, icons, sliders and buttons take the preset's readable
/// foreground and accent, so a light-theme screen on the always-dark night
/// preset still reads (and the other way round).
class OnGradientTheme extends StatelessWidget {
  const OnGradientTheme({super.key, required this.preset, required this.child});

  final GradientPreset preset;
  final Widget child;

  /// The preset's accent, deepened in light themes so text in it stays
  /// AA-readable on the pastel gradient (the raw light accents are tuned
  /// for icons and dots).
  static Color ink(GradientPreset preset, Brightness b) => preset.isDarkIn(b)
      ? preset.accent(b)
      : Color.lerp(preset.accentLight, const Color(0xFF3B1424), .4)!;

  /// Text and icon colour on the accent (filled buttons).
  static Color onAccent(GradientPreset preset, Brightness b) =>
      preset.isDarkIn(b) ? const Color(0xFF2A0F1C) : Colors.white;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final darkBg = preset.isDarkIn(b);
    final fg = preset.foreground(b);
    final muted = preset.foregroundMuted(b);
    final accent = ink(preset, b);
    final onAccent = OnGradientTheme.onAccent(preset, b);
    final scheme = theme.colorScheme.copyWith(
      brightness: darkBg ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      secondaryContainer: Colors.white.withValues(alpha: darkBg ? .16 : .6),
      onSecondaryContainer: fg,
      onSurface: fg,
      onSurfaceVariant: muted,
      outline: fg.withValues(alpha: .45),
      outlineVariant: fg.withValues(alpha: .2),
      error: darkBg ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: scheme,
        textTheme: theme.textTheme.apply(bodyColor: fg, displayColor: fg),
        iconTheme: theme.iconTheme.copyWith(color: fg),
        listTileTheme: theme.listTileTheme.copyWith(
          textColor: fg,
          iconColor: fg,
        ),
        sliderTheme: theme.sliderTheme.copyWith(
          activeTrackColor: accent,
          thumbColor: accent,
          inactiveTrackColor: fg.withValues(alpha: .2),
          overlayColor: accent.withValues(alpha: .12),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: onAccent,
          ).merge(theme.filledButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            side: BorderSide(color: fg.withValues(alpha: .45)),
          ).merge(theme.outlinedButtonTheme.style),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: fg,
          ).merge(theme.textButtonTheme.style),
        ),
        progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
          color: accent,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: IconTheme.merge(
          data: IconThemeData(color: fg),
          child: child,
        ),
      ),
    );
  }
}
