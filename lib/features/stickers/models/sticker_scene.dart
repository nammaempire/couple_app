import 'dart:ui';

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/stickers/models/sticker_category.dart';

/// How the two avatars are arranged in a sticker. The sender is always on
/// the left, their partner on the right, mirrored to face them.
enum StickerLayout {
  /// Side by side, heads leaning in.
  together,

  /// Heads touching, with a stronger tilt.
  heads,

  /// Close overlap, cheek to cheek.
  hug,

  /// Far apart with something between them.
  apart,

  /// The sender alone, big.
  solo,
}

/// Decorations drawn in code around the avatars.
enum StickerProp {
  floatingHearts,
  bigHeart,
  brokenHeart,
  rainCloud,
  sun,
  moonStars,
  sparkles,
  flowers,
  coffee,
  zzz,
  musicNotes,
  confetti,

  /// A heart with crossed plasters, for sorry.
  plasterHeart,

  /// A dotted arc with a heart, joining two avatars that are [StickerLayout.apart].
  heartTrail,
}

/// One sticker design: who pulls which face, how they stand, what floats
/// around them and the card colours. [id] is stored on messages as
/// `sticker.id`, so ids must never change.
class StickerScene {
  const StickerScene({
    required this.id,
    required this.category,
    required this.label,
    required this.layout,
    required this.senderExpression,
    this.partnerExpression = AvatarExpression.happy,
    this.props = const [],
    required this.gradient,
    required this.accent,
    required this.defaultQuoteId,
  });

  final String id;
  final StickerCategory category;

  /// Short description for accessibility, e.g. "Big heart".
  final String label;

  final StickerLayout layout;
  final AvatarExpression senderExpression;

  /// Unused for [StickerLayout.solo].
  final AvatarExpression partnerExpression;

  final List<StickerProp> props;

  /// Top and bottom colours of the card in light mode. Dark mode deepens
  /// them.
  final List<Color> gradient;

  /// Colour of hearts and other accents.
  final Color accent;

  /// The quote shown with this scene until the sender picks another.
  final String defaultQuoteId;

  bool get isSolo => layout == StickerLayout.solo;
}
