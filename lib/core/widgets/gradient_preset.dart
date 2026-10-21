import 'package:flutter/material.dart';

/// A small palette of soft gradients, each tuned for light and dark themes.
///
/// Light variants are pastel, so the theme's regular text colours stay
/// readable on them; dark variants are deep, so light text does. [night] is
/// dark in both themes and always wants light text ([foreground]).
enum GradientPreset {
  blush(
    light: [Color(0xFFFFE4EC), Color(0xFFFFC7D6), Color(0xFFFBD5EA)],
    dark: [Color(0xFF5A2236), Color(0xFF431A30), Color(0xFF5C2A47)],
    accentLight: Color(0xFFC2185B),
    accentDark: Color(0xFFFF9EBB),
  ),
  sunset(
    light: [Color(0xFFFFE3CF), Color(0xFFFFC9BE), Color(0xFFFFBCD2)],
    dark: [Color(0xFF5C2C22), Color(0xFF572239), Color(0xFF3F1C35)],
    accentLight: Color(0xFFD84315),
    accentDark: Color(0xFFFFB59A),
  ),
  lavender(
    light: [Color(0xFFEEE6FF), Color(0xFFDCD0FF), Color(0xFFF4DCF8)],
    dark: [Color(0xFF362B5E), Color(0xFF2A2350), Color(0xFF472B58)],
    accentLight: Color(0xFF6A3FC4),
    accentDark: Color(0xFFCDB8FF),
  ),
  ocean(
    light: [Color(0xFFDDF0FF), Color(0xFFCBE3FB), Color(0xFFE4E1FF)],
    dark: [Color(0xFF173A56), Color(0xFF1D2E53), Color(0xFF2B2B5C)],
    accentLight: Color(0xFF1565C0),
    accentDark: Color(0xFFA6CCFF),
  ),
  mint(
    light: [Color(0xFFDDF7EC), Color(0xFFCAEEE2), Color(0xFFE9F7D9)],
    dark: [Color(0xFF17443A), Color(0xFF1C3A42), Color(0xFF27443A)],
    accentLight: Color(0xFF00796B),
    accentDark: Color(0xFF9EE6CF),
  ),
  peach(
    light: [Color(0xFFFFEBD9), Color(0xFFFFD6C6), Color(0xFFFFE1E4)],
    dark: [Color(0xFF5A3527), Color(0xFF543026), Color(0xFF4F2636)],
    accentLight: Color(0xFFD9480F),
    accentDark: Color(0xFFFFC2A3),
  ),
  sunny(
    light: [Color(0xFFFFF3C4), Color(0xFFFFE0C4), Color(0xFFD9F4E4)],
    dark: [Color(0xFF574818), Color(0xFF573822), Color(0xFF1F4A3C)],
    accentLight: Color(0xFFB26A00),
    accentDark: Color(0xFFFFD98A),
  ),
  festive(
    light: [Color(0xFFFFE0F0), Color(0xFFE6DAFF), Color(0xFFFFEFC7)],
    dark: [Color(0xFF5A1F4A), Color(0xFF34265E), Color(0xFF574318)],
    accentLight: Color(0xFFAD1457),
    accentDark: Color(0xFFFFB0DA),
  ),
  gold(
    light: [Color(0xFFFFF2CC), Color(0xFFFFDDB8), Color(0xFFFFCCD6)],
    dark: [Color(0xFF594519), Color(0xFF5A3223), Color(0xFF4F2336)],
    accentLight: Color(0xFFA65E00),
    accentDark: Color(0xFFFFD27A),
  ),
  night(
    light: [Color(0xFF2E3178), Color(0xFF3C2F7E), Color(0xFF1F2257)],
    dark: [Color(0xFF15173A), Color(0xFF231A4B), Color(0xFF0E1030)],
    accentLight: Color(0xFFFFE08A),
    accentDark: Color(0xFFFFE08A),
    alwaysDark: true,
  );

  const GradientPreset({
    required this.light,
    required this.dark,
    required this.accentLight,
    required this.accentDark,
    this.alwaysDark = false,
  });

  final List<Color> light;
  final List<Color> dark;
  final Color accentLight;
  final Color accentDark;

  /// Dark in both themes (wants light text).
  final bool alwaysDark;

  List<Color> colors(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// A strong tone of the preset for icons, dots and highlights.
  Color accent(Brightness brightness) =>
      brightness == Brightness.dark ? accentDark : accentLight;

  /// A strong tone for text on white or cream paper (the accent, except
  /// for presets whose accent is a light glow).
  Color get ink => alwaysDark ? const Color(0xFF3D3A8C) : accentLight;

  /// Whether text on this preset should be light.
  bool isDarkIn(Brightness brightness) =>
      alwaysDark || brightness == Brightness.dark;

  /// Readable text colour on this preset.
  Color foreground(Brightness brightness) =>
      isDarkIn(brightness) ? const Color(0xFFFFF4F6) : const Color(0xFF3B1424);

  /// Secondary text colour on this preset.
  Color foregroundMuted(Brightness brightness) =>
      foreground(brightness).withValues(alpha: isDarkIn(brightness) ? .8 : .72);

  /// A soft coloured shadow under cards of this preset.
  Color shadow(Brightness brightness) => brightness == Brightness.dark
      ? Colors.black.withValues(alpha: .35)
      : light[1].withValues(alpha: .55);
}
