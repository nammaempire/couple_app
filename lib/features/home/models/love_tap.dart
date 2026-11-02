import 'package:flutter/painting.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';

/// The kinds of one-tap love message a partner can send.
enum LoveTap {
  thinking(
    'thinking',
    '💭',
    'Thinking of you',
    'is thinking of you',
    AvatarExpression.blush,
    ['💭', '💭', '✨', '💫', '🤔'],
    Color(0x389678FF),
  ),
  love('love', '❤️', 'Love you', 'sent you love', AvatarExpression.love, [
    '❤️',
    '💖',
    '💕',
    '💗',
    '💘',
    '💞',
  ], Color(0x38FF2D55)),
  missYou('miss', '🥺', 'Miss you', 'misses you', AvatarExpression.sad, [
    '🥺',
    '💌',
    '💭',
    '🌙',
    '💧',
    '🥹',
  ], Color(0x335A8CFF)),
  hug('hug', '🤗', 'Hug', 'sent you a hug', AvatarExpression.happy, [
    '🤗',
    '🫂',
    '💞',
    '🧸',
    '💛',
  ], Color(0x38FFAA3C)),
  kiss('kiss', '😘', 'Kiss', 'sent you a kiss', AvatarExpression.kiss, [
    '😘',
    '💋',
    '😚',
    '💋',
    '💗',
  ], Color(0x38FF3C8C));

  const LoveTap(
    this.id,
    this.emoji,
    this.label,
    this.receivedText,
    this.expression,
    this.particles,
    this.tint,
  );

  final String id;
  final String emoji;
  final String label;

  /// Completes "[partner name] …" on the receiving phone.
  final String receivedText;

  /// The face an avatar pulls for this tap (on the buttons, in the burst
  /// and on the Home header).
  final AvatarExpression expression;

  /// The small emojis that fill the screen in the burst.
  final List<String> particles;

  /// The glow behind the burst.
  final Color tint;

  /// Older nudges have no kind and were all "thinking of you".
  static LoveTap fromId(String? id) {
    for (final tap in LoveTap.values) {
      if (tap.id == id) return tap;
    }
    return LoveTap.thinking;
  }
}
