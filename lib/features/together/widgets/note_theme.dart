import 'package:flutter/material.dart';

import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/together/models/love_note.dart';

/// The look of a love note: its gradient world and what floats in it.
class NoteTheme {
  const NoteTheme(this.preset, this.particles);

  final GradientPreset preset;
  final ParticleStyle particles;

  /// A letter is blush; each "Open when…" envelope has its own mood.
  static NoteTheme of(LoveNote note) =>
      note.kind == NoteKind.openWhen ? forOpenWhen(note.openWhen) : letter;

  static const letter = NoteTheme(GradientPreset.blush, ParticleStyle.hearts);

  static NoteTheme forOpenWhen(OpenWhen? o) => switch (o) {
    OpenWhen.badDay => const NoteTheme(
      GradientPreset.lavender,
      ParticleStyle.hearts,
    ),
    OpenWhen.cantSleep => const NoteTheme(
      GradientPreset.night,
      ParticleStyle.stars,
    ),
    OpenWhen.missMe => const NoteTheme(
      GradientPreset.peach,
      ParticleStyle.hearts,
    ),
    OpenWhen.needSmile => const NoteTheme(
      GradientPreset.sunny,
      ParticleStyle.hearts,
    ),
    OpenWhen.birthday => const NoteTheme(
      GradientPreset.festive,
      ParticleStyle.confetti,
    ),
    OpenWhen.anniversary => const NoteTheme(
      GradientPreset.gold,
      ParticleStyle.hearts,
    ),
    null => letter,
  };

  /// The colour of floating hearts or stars on this note's background.
  Color particleColor(Brightness b) =>
      preset.isDarkIn(b) ? const Color(0xFFFFE6EE) : Colors.white;
}

/// The serif family used for letters (as for sticker quotes).
TextStyle noteSerif(TextStyle? base) => (base ?? const TextStyle()).copyWith(
  fontFamily: 'serif',
  fontFamilyFallback: [
    'Georgia',
    'Noto Serif',
    'Times New Roman',
    ...?base?.fontFamilyFallback,
  ],
);
