import 'package:flutter/material.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/chat/widgets/chat_patterns.dart';

/// Chat-only colours that follow the couple's [ChatLook].
///
/// [applyTo] builds the theme the chat (and its preview) is drawn with;
/// widgets read the colours back with [ChatPalette.of].
@immutable
class ChatPalette extends ThemeExtension<ChatPalette> {
  const ChatPalette({
    required this.theirsBubble,
    required this.onTheirsBubble,
    required this.systemChip,
    required this.hasBackground,
    this.mineGradient = const [Color(0xFFB3264F), Color(0xFF9C3D7A)],
    this.onMine = Colors.white,
    this.theirsGradient = const [Color(0xFFFFFBFC), Color(0xFFF7E3E8)],
    this.theirsBorder = const Color(0xB3FFFFFF),
    this.accentGradient = const [Color(0xFFB3264F), Color(0xFF9C3D7A)],
    this.onAccent = Colors.white,
    this.headerGradient = const [Color(0xFFFFE4EC), Color(0xFFF4DCF8)],
    this.glass = const Color(0xC7FFFFFF),
    this.glassBorder = const Color(0xB3FFFFFF),
    this.glow = const Color(0x40B3264F),
  });

  /// Partner's bubbles: solid, so they read over photos and patterns.
  final Color theirsBubble;
  final Color onTheirsBubble;

  /// Behind date dividers, call records and other centred labels.
  final Color systemChip;

  /// A pattern or photo is drawn behind the messages, so loose labels need
  /// a [systemChip] pill to stay readable.
  final bool hasBackground;

  /// My bubbles: a soft two-stop gradient derived from the chat colour.
  final List<Color> mineGradient;
  final Color onMine;

  /// The partner's bubbles: a tinted, glassy surface ([onTheirsBubble]
  /// text), edged with [theirsBorder].
  final List<Color> theirsGradient;
  final Color theirsBorder;

  /// Strong gradient for the send button, badges and sheet handles.
  final List<Color> accentGradient;
  final Color onAccent;

  /// Behind the app bar (text stays [ColorScheme.onSurface]).
  final List<Color> headerGradient;

  /// Frosted fill and edge for floating pills (composer, pinned bar).
  final Color glass;
  final Color glassBorder;

  /// Soft coloured shadow under my bubbles and accent buttons.
  final Color glow;

  /// [colors] as a diagonal gradient.
  static LinearGradient diagonal(List<Color> colors) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
  );

  /// The palette in [context]'s theme, or the standard one outside a chat.
  static ChatPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ChatPalette>() ?? _derive(theme, ChatLook.standard);
  }

  /// [base] recoloured for [look]: a scheme seeded from the chosen colour
  /// (the app's own when none was chosen) plus a matching [ChatPalette].
  static ThemeData applyTo(ThemeData base, ChatLook look) {
    var theme = base;
    final seed = look.colorValue;
    if (seed != null) {
      final scheme = ColorScheme.fromSeed(
        seedColor: Color(seed),
        brightness: base.brightness,
      );
      theme = base.copyWith(
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
        ),
      );
    }
    return theme.copyWith(
      extensions: [
        ...theme.extensions.values.where((e) => e is! ChatPalette),
        _derive(theme, look),
      ],
    );
  }

  static ChatPalette _derive(ThemeData theme, ChatLook look) {
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final hasBackground = ChatPatterns.shows(look.background);
    Color blend(Color over, double alpha, Color under) =>
        Color.alphaBlend(over.withValues(alpha: alpha), under);
    // Light: tone-40 primary under white text. Dark: the deep container
    // under its light "on" colour, like the presets. The second stop leans
    // the hue towards violet, then is darkened (or lightened) as needed to
    // keep the text at AA.
    final onMine = dark ? scheme.onPrimaryContainer : scheme.onPrimary;
    final mineFrom = dark ? scheme.primaryContainer : scheme.primary;
    final mineTo = _readable(_shift(mineFrom), onMine);
    final accentTo = _readable(_shift(scheme.primary), scheme.onPrimary);
    final lowest = dark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLowest;
    return ChatPalette(
      mineGradient: [mineFrom, mineTo],
      onMine: onMine,
      theirsGradient: dark
          ? [lowest, blend(scheme.primaryContainer, .32, lowest)]
          : [
              blend(scheme.primaryContainer, .10, lowest),
              blend(scheme.primaryContainer, .42, lowest),
            ],
      theirsBorder: Colors.white.withValues(alpha: dark ? .07 : .75),
      accentGradient: [scheme.primary, accentTo],
      onAccent: scheme.onPrimary,
      headerGradient: [
        blend(scheme.primaryContainer, dark ? .42 : .55, scheme.surface),
        dark
            ? blend(_shift(scheme.primaryContainer), .45, scheme.surface)
            : blend(scheme.tertiaryContainer, .5, scheme.surface),
      ],
      glass: (dark ? scheme.surfaceContainerHigh : scheme.surface).withValues(
        alpha: dark ? .8 : .78,
      ),
      glassBorder: Colors.white.withValues(alpha: dark ? .1 : .7),
      glow: (dark ? Colors.black : scheme.primary).withValues(
        alpha: dark ? .3 : .22,
      ),
      // The default look keeps the app's original rose-grey bubble.
      theirsBubble: look.colorValue == null
          ? (dark ? AppTheme.bubbleTheirsDark : AppTheme.bubbleTheirsLight)
          : scheme.surfaceContainerHigh,
      onTheirsBubble: scheme.onSurface,
      systemChip: hasBackground
          ? scheme.surface.withValues(alpha: .88)
          : scheme.surfaceContainerHighest.withValues(alpha: .6),
      hasBackground: hasBackground,
    );
  }

  /// [c] with its hue turned towards violet.
  static Color _shift(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withHue((hsl.hue - 28) % 360)
        .withSaturation((hsl.saturation * 1.08).clamp(0.0, 1.0))
        .toColor();
  }

  /// [bg] nudged away from [fg] until text in [fg] reads at 4.5:1.
  static Color _readable(Color bg, Color fg) {
    final towards = fg.computeLuminance() > .5 ? Colors.black : Colors.white;
    var c = bg;
    for (var i = 0; i < 12 && _contrast(c, fg) < 4.5; i++) {
      c = Color.lerp(c, towards, .08)!;
    }
    return c;
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + .05) / (lo + .05);
  }

  @override
  ChatPalette copyWith({
    Color? theirsBubble,
    Color? onTheirsBubble,
    Color? systemChip,
    bool? hasBackground,
  }) => ChatPalette(
    theirsBubble: theirsBubble ?? this.theirsBubble,
    onTheirsBubble: onTheirsBubble ?? this.onTheirsBubble,
    systemChip: systemChip ?? this.systemChip,
    hasBackground: hasBackground ?? this.hasBackground,
    mineGradient: mineGradient,
    onMine: onMine,
    theirsGradient: theirsGradient,
    theirsBorder: theirsBorder,
    accentGradient: accentGradient,
    onAccent: onAccent,
    headerGradient: headerGradient,
    glass: glass,
    glassBorder: glassBorder,
    glow: glow,
  );

  static List<Color> _lerpList(List<Color> a, List<Color> b, double t) => [
    for (var i = 0; i < a.length && i < b.length; i++)
      Color.lerp(a[i], b[i], t)!,
  ];

  @override
  ChatPalette lerp(ChatPalette? other, double t) {
    if (other == null) return this;
    return ChatPalette(
      theirsBubble: Color.lerp(theirsBubble, other.theirsBubble, t)!,
      onTheirsBubble: Color.lerp(onTheirsBubble, other.onTheirsBubble, t)!,
      systemChip: Color.lerp(systemChip, other.systemChip, t)!,
      hasBackground: t < .5 ? hasBackground : other.hasBackground,
      mineGradient: _lerpList(mineGradient, other.mineGradient, t),
      onMine: Color.lerp(onMine, other.onMine, t)!,
      theirsGradient: _lerpList(theirsGradient, other.theirsGradient, t),
      theirsBorder: Color.lerp(theirsBorder, other.theirsBorder, t)!,
      accentGradient: _lerpList(accentGradient, other.accentGradient, t),
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      headerGradient: _lerpList(headerGradient, other.headerGradient, t),
      glass: Color.lerp(glass, other.glass, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
    );
  }
}
