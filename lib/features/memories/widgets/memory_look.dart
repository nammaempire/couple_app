import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/memories/models/memory.dart';

/// The gradient each album wears when a memory has no photo, and behind
/// its detail page.
abstract final class MemoryLook {
  static GradientPreset presetFor(String album) => switch (album) {
    MemoryAlbums.firstDate => GradientPreset.blush,
    MemoryAlbums.trips => GradientPreset.ocean,
    MemoryAlbums.birthdays => GradientPreset.festive,
    MemoryAlbums.anniversaries => GradientPreset.gold,
    MemoryAlbums.randomMoments => GradientPreset.lavender,
    _ => const [
      GradientPreset.mint,
      GradientPreset.peach,
      GradientPreset.sunny,
      GradientPreset.sunset,
    ][album.codeUnits.fold<int>(0, (a, c) => a + c) % 4],
  };
}
