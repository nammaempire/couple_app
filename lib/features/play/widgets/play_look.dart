import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/widgets/play_start_card.dart';

/// How a game screen looks: each game keeps its start card's gradient
/// while you play, and a finished game turns gold (you won) or festive.
abstract final class PlayLook {
  /// The game's own gradient (the same as its start card).
  static GradientPreset of(GameType type) => PlayStartCard.presetFor(type);

  /// Whether [game] ended with me on top.
  static bool iWon(Game game, String myUid) =>
      game.isFinished && !game.isDraw && game.winner == myUid;

  /// The page gradient for [game] as [myUid] sees it.
  static GradientPreset page(Game game, String myUid) {
    if (!game.isFinished) return of(game.type);
    return iWon(game, myUid) ? GradientPreset.gold : GradientPreset.festive;
  }

  /// Particles behind a finished game: confetti for a win or a draw,
  /// soft hearts otherwise. Null while playing.
  static ParticleStyle? particles(Game game, String myUid) {
    if (!game.isFinished) return null;
    final lost = !game.isDraw && game.winner != null && game.winner != myUid;
    return lost ? ParticleStyle.hearts : ParticleStyle.confetti;
  }

  /// A soft white or smoky fill for chips and panels on a game gradient.
  static Color panel(BuildContext context, {double light = .55}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Colors.white.withValues(alpha: dark ? .1 : light);
  }
}
