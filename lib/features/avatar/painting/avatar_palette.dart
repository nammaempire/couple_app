import 'dart:ui';

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/painting/avatar_brush.dart';

/// Every colour an avatar is painted with, derived once from its config.
class AvatarPalette {
  AvatarPalette._({
    required this.skin,
    required this.skinShade,
    required this.skinDeep,
    required this.ink,
    required this.lip,
    required this.hair,
    required this.hairShade,
    required this.hairLight,
    required this.brow,
    required this.iris,
    required this.pupil,
    required this.outfit,
    required this.outfitShade,
    required this.outfitDeep,
    required this.outfitLight,
    required this.trim,
    required this.scarf,
    required this.background,
    required this.darkSkin,
  });

  factory AvatarPalette.of(AvatarConfig config) {
    final skin = config.skinColor;
    final hair = config.hairTint;
    final outfit = config.outfitTint;
    final eye = config.eyeTint;
    final darkSkin = skin.computeLuminance() < .12;
    final ink = AvatarBrush.shade(skin, darkSkin ? .9 : .84);
    final lightHair = hair.computeLuminance() > .3;
    final lightOutfit = outfit.computeLuminance() > .6;

    return AvatarPalette._(
      skin: skin,
      skinShade: AvatarBrush.shade(skin, darkSkin ? .2 : .13),
      skinDeep: AvatarBrush.shade(skin, darkSkin ? .42 : .3),
      ink: ink,
      lip: Color.lerp(
        AvatarBrush.shade(skin, .12),
        const Color(0xFFC94F69),
        darkSkin ? .4 : .6,
      )!,
      hair: hair,
      hairShade: AvatarBrush.shade(hair, .3),
      hairLight: AvatarBrush.tint(hair, lightHair ? .32 : .16),
      brow: Color.lerp(hair, ink, lightHair ? .45 : .2)!,
      iris: AvatarBrush.shade(eye, .12),
      pupil: AvatarBrush.shade(eye, .78),
      outfit: outfit,
      outfitShade: AvatarBrush.shade(outfit, lightOutfit ? .1 : .16),
      outfitDeep: AvatarBrush.shade(outfit, lightOutfit ? .2 : .32),
      outfitLight: AvatarBrush.tint(outfit, .28),
      trim: config.outfitColor == 'mustard'
          ? const Color(0xFFB8402F)
          : const Color(0xFFEDBE4E),
      scarf: lightOutfit
          ? AvatarBrush.shade(outfit, .16)
          : AvatarBrush.tint(outfit, .3),
      background: config.backgroundColor,
      darkSkin: darkSkin,
    );
  }

  final Color skin;
  final Color skinShade;
  final Color skinDeep;

  /// Eyes, brows' fallback and mouth lines: a very dark tone of the skin.
  final Color ink;
  final Color lip;
  final Color hair;
  final Color hairShade;
  final Color hairLight;
  final Color brow;
  final Color iris;
  final Color pupil;
  final Color outfit;
  final Color outfitShade;
  final Color outfitDeep;
  final Color outfitLight;

  /// Gold (or contrast) trim for kurta and saree borders.
  final Color trim;

  /// A headscarf: the outfit colour, lifted (or deepened for very light
  /// outfits) so the drape stands out from the clothes under it.
  final Color scarf;
  final Color background;

  /// Deep skin tones get stronger blush and lighter feature accents.
  final bool darkSkin;

  static const blush = Color(0xFFFF5F86);
  static const mouth = Color(0xFF6B2230);
  static const tongue = Color(0xFFF2788F);
  static const teeth = Color(0xFFFFFFFF);
  static const heart = Color(0xFFEB3B61);
  static const tear = Color(0xFF8FD3FF);
  static const metal = Color(0xFF2E2B33);
  static const gold = Color(0xFFEDBE4E);
}
