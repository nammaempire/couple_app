import 'dart:ui';

import 'package:couple_app/features/avatar/data/selfie_avatar.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A 400×600 "selfie": background, hair above (and beside the jaw when
/// [longHair]), a skin-coloured face, a chin and a shirt below.
img.Image selfie({
  required img.Color skin,
  img.Color? hair,
  bool longHair = false,
  img.Color? chin,
  required img.Color shirt,
}) {
  final im = img.Image(width: 400, height: 600);
  img.fill(im, color: img.ColorRgb8(200, 220, 235)); // wall
  img.fillRect(im, x1: 0, y1: 430, x2: 399, y2: 599, color: shirt);
  if (hair != null) {
    img.fillRect(im, x1: 110, y1: 80, x2: 290, y2: 150, color: hair);
    if (longHair) {
      img.fillRect(im, x1: 90, y1: 150, x2: 310, y2: 420, color: hair);
    }
  }
  img.fillRect(im, x1: 120, y1: 150, x2: 280, y2: 350, color: skin);
  if (chin != null) {
    img.fillRect(im, x1: 150, y1: 300, x2: 250, y2: 350, color: chin);
  }
  return im;
}

const face = Rect.fromLTRB(120, 150, 280, 350);

void main() {
  test('reads skin tone, hair colour, long hair and outfit colour', () {
    final scan = SelfieAvatarScanner.fromImage(
      selfie(
        skin: img.ColorRgb8(200, 150, 110),
        hair: img.ColorRgb8(30, 22, 20),
        longHair: true,
        shirt: img.ColorRgb8(45, 72, 120),
      ),
      face: face,
      base: const AvatarConfig(hair: 'bun', glasses: 'round'),
    );
    final a = scan.avatar;
    expect(a.hairColor, 'black');
    expect(a.hair, 'bun', reason: 'a long style is kept');
    expect(a.outfitColor, 'navy');
    expect(a.facialHair, 'none');
    expect(a.glasses, 'round', reason: 'parts a photo cannot tell are kept');
    expect(['skin3', 'skin4'], contains(a.skin));
    expect(scan.matched, containsAll(['skin tone', 'hair colour']));
  });

  test('short hair turns a long style short; a dark chin is a beard', () {
    final a = SelfieAvatarScanner.fromImage(
      selfie(
        skin: img.ColorRgb8(150, 100, 70),
        hair: img.ColorRgb8(70, 45, 32),
        chin: img.ColorRgb8(60, 42, 32),
        shirt: img.ColorRgb8(225, 90, 120),
      ),
      face: face,
      base: const AvatarConfig(hair: 'ponytail'),
    ).avatar;
    expect(a.hair, 'short');
    expect(a.facialHair, 'beard');
    expect(a.outfitColor, 'rose');
    expect(['darkBrown', 'brown'], contains(a.hairColor));
  });

  test('skin above the forehead means bald', () {
    final skin = img.ColorRgb8(230, 190, 160);
    final a = SelfieAvatarScanner.fromImage(
      selfie(skin: skin, hair: skin, shirt: img.ColorRgb8(240, 240, 238)),
      face: face,
      base: const AvatarConfig(),
    ).avatar;
    expect(a.hair, 'bald');
    expect(a.outfitColor, 'white');
    expect(['skin1', 'skin2'], contains(a.skin));
  });

  test('darker skin maps to a darker swatch', () {
    String skinFor(int r, int g, int b) => SelfieAvatarScanner.fromImage(
      selfie(
        skin: img.ColorRgb8(r, g, b),
        hair: img.ColorRgb8(20, 15, 12),
        shirt: img.ColorRgb8(50, 50, 52),
      ),
      face: face,
      base: const AvatarConfig(),
    ).avatar.skin;
    final light = AvatarConfig.skins.indexWhere(
      (s) => s.id == skinFor(235, 200, 175),
    );
    final deep = AvatarConfig.skins.indexWhere(
      (s) => s.id == skinFor(95, 60, 40),
    );
    expect(deep, greaterThan(light + 2));
  });
}
