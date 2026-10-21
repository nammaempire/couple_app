import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/music/models/song.dart';

/// The colours and particles a song's moment brings to the library and the
/// player: romantic songs glow blush with hearts, sad ones go ocean blue,
/// road trips sunset, chill nights starry.
extension SongMomentLook on SongMoment {
  GradientPreset get preset => switch (this) {
    SongMoment.ourSong => GradientPreset.festive,
    SongMoment.romantic => GradientPreset.blush,
    SongMoment.missYou => GradientPreset.lavender,
    SongMoment.happy => GradientPreset.sunny,
    SongMoment.sad => GradientPreset.ocean,
    SongMoment.roadTrip => GradientPreset.sunset,
    SongMoment.dance => GradientPreset.peach,
    SongMoment.chill => GradientPreset.night,
    SongMoment.movieNight => GradientPreset.night,
    SongMoment.funny => GradientPreset.sunny,
    SongMoment.food => GradientPreset.peach,
    SongMoment.travel => GradientPreset.mint,
    SongMoment.music => GradientPreset.lavender,
    SongMoment.learn => GradientPreset.mint,
    SongMoment.other => GradientPreset.blush,
  };

  /// Particles drifting behind the player, or null for none.
  ParticleStyle? get particles => switch (this) {
    SongMoment.ourSong ||
    SongMoment.romantic ||
    SongMoment.missYou => ParticleStyle.hearts,
    SongMoment.chill || SongMoment.movieNight => ParticleStyle.stars,
    SongMoment.dance || SongMoment.happy => ParticleStyle.confetti,
    _ => null,
  };

  /// Particle colour on [preset] in [brightness].
  Color particleColor(Brightness brightness) {
    final p = preset;
    if (particles == ParticleStyle.stars) return const Color(0xFFFFF1C2);
    return p.isDarkIn(brightness) ? p.accent(brightness) : Colors.white;
  }
}
