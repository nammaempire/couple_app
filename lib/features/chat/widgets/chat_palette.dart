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
  });

  /// Partner's bubbles: solid, so they read over photos and patterns.
  final Color theirsBubble;
  final Color onTheirsBubble;

  /// Behind date dividers, call records and other centred labels.
  final Color systemChip;

  /// A pattern or photo is drawn behind the messages, so loose labels need
  /// a [systemChip] pill to stay readable.
  final bool hasBackground;

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
    return ChatPalette(
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
  );

  @override
  ChatPalette lerp(ChatPalette? other, double t) {
    if (other == null) return this;
    return ChatPalette(
      theirsBubble: Color.lerp(theirsBubble, other.theirsBubble, t)!,
      onTheirsBubble: Color.lerp(onTheirsBubble, other.onTheirsBubble, t)!,
      systemChip: Color.lerp(systemChip, other.systemChip, t)!,
      hasBackground: t < .5 ? hasBackground : other.hasBackground,
    );
  }
}
