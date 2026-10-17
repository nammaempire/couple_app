import 'dart:math';

import 'package:flutter/painting.dart';

/// One choosable option for an avatar part.
class AvatarOption {
  const AvatarOption(this.id, this.label);
  final String id;
  final String label;
}

/// A colour option for an avatar part.
class AvatarSwatch {
  const AvatarSwatch(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;
}

/// Faces an avatar can pull. Stickers pick one per partner.
enum AvatarExpression {
  neutral,
  happy,
  laugh,
  love,
  kiss,
  wink,
  blush,
  sad,
  crying,
  sleepy,
  surprised,
  pout,
}

/// The parts that make up one person's avatar, stored on their profile as
/// `users/{uid}.avatar`. Every field is an option id from the lists below;
/// unknown or missing ids (say, from a newer app version) fall back to that
/// field's default, the same as a fresh [AvatarConfig].
class AvatarConfig {
  const AvatarConfig({
    this.skin = 'skin3',
    this.face = 'oval',
    this.hair = 'short',
    this.hairColor = 'black',
    this.eyes = 'round',
    this.eyeColor = 'brown',
    this.brows = 'soft',
    this.facialHair = 'none',
    this.glasses = 'none',
    this.accessory = 'none',
    this.faceAccessory = 'none',
    this.outfit = 'tee',
    this.outfitColor = 'rose',
    this.background = 'blush',
  });

  final String skin;
  final String face;
  final String hair;
  final String hairColor;
  final String eyes;
  final String eyeColor;
  final String brows;
  final String facialHair;
  final String glasses;

  /// Something worn on the head or ears, from [accessories]. Older avatars
  /// may still hold 'bindi' here, from before [faceAccessory] existed.
  final String accessory;

  /// Something worn on the face, from [faceAccessories]; combines with any
  /// [accessory].
  final String faceAccessory;
  final String outfit;
  final String outfitColor;
  final String background;

  // ---- Options ---------------------------------------------------------

  static const skins = [
    AvatarSwatch('skin1', 'Porcelain', Color(0xFFFBE3D3)),
    AvatarSwatch('skin2', 'Light', Color(0xFFF5CFB2)),
    AvatarSwatch('skin3', 'Warm', Color(0xFFE5B08A)),
    AvatarSwatch('skin4', 'Golden', Color(0xFFD39A6A)),
    AvatarSwatch('skin5', 'Tan', Color(0xFFB97D52)),
    AvatarSwatch('skin6', 'Brown', Color(0xFF8F5B3A)),
    AvatarSwatch('skin7', 'Deep', Color(0xFF6B4129)),
    AvatarSwatch('skin8', 'Rich', Color(0xFF4A2C1C)),
  ];

  static const faces = [
    AvatarOption('oval', 'Oval'),
    AvatarOption('round', 'Round'),
    AvatarOption('heart', 'Heart'),
    AvatarOption('square', 'Square'),
    AvatarOption('long', 'Long'),
  ];

  static const hairs = [
    AvatarOption('short', 'Short'),
    AvatarOption('buzz', 'Buzz'),
    AvatarOption('side', 'Side part'),
    AvatarOption('quiff', 'Quiff'),
    AvatarOption('curly', 'Curly'),
    AvatarOption('afro', 'Afro'),
    AvatarOption('bob', 'Bob'),
    AvatarOption('long', 'Long'),
    AvatarOption('wavy', 'Wavy'),
    AvatarOption('ponytail', 'Ponytail'),
    AvatarOption('bun', 'Bun'),
    AvatarOption('braids', 'Braids'),
    AvatarOption('bald', 'Bald'),
  ];

  static const hairColors = [
    AvatarSwatch('black', 'Black', Color(0xFF231A17)),
    AvatarSwatch('darkBrown', 'Dark brown', Color(0xFF4A2E22)),
    AvatarSwatch('brown', 'Brown', Color(0xFF7A4A2E)),
    AvatarSwatch('auburn', 'Auburn', Color(0xFF9C4A2C)),
    AvatarSwatch('blonde', 'Blonde', Color(0xFFD9B26A)),
    AvatarSwatch('grey', 'Grey', Color(0xFF9E9A98)),
    AvatarSwatch('pink', 'Pink', Color(0xFFE48AAE)),
    AvatarSwatch('blue', 'Blue', Color(0xFF5C7FC9)),
  ];

  static const eyeStyles = [
    AvatarOption('round', 'Round'),
    AvatarOption('almond', 'Almond'),
    AvatarOption('smiley', 'Smiley'),
    AvatarOption('lashes', 'Lashes'),
  ];

  static const eyeColors = [
    AvatarSwatch('brown', 'Brown', Color(0xFF4E3426)),
    AvatarSwatch('hazel', 'Hazel', Color(0xFF7A6232)),
    AvatarSwatch('green', 'Green', Color(0xFF3F7552)),
    AvatarSwatch('blue', 'Blue', Color(0xFF3E6FA8)),
    AvatarSwatch('grey', 'Grey', Color(0xFF6E7378)),
  ];

  static const browStyles = [
    AvatarOption('soft', 'Soft'),
    AvatarOption('thick', 'Thick'),
    AvatarOption('arched', 'Arched'),
    AvatarOption('straight', 'Straight'),
  ];

  static const facialHairs = [
    AvatarOption('none', 'None'),
    AvatarOption('stubble', 'Stubble'),
    AvatarOption('moustache', 'Moustache'),
    AvatarOption('beard', 'Beard'),
    AvatarOption('goatee', 'Goatee'),
  ];

  static const glassesStyles = [
    AvatarOption('none', 'None'),
    AvatarOption('round', 'Round'),
    AvatarOption('square', 'Square'),
    AvatarOption('sun', 'Sunglasses'),
  ];

  /// Head and ear accessories offered in the builder.
  static const headAccessories = [
    AvatarOption('none', 'None'),
    AvatarOption('earrings', 'Earrings'),
    AvatarOption('flower', 'Flower'),
    AvatarOption('bow', 'Bow'),
    AvatarOption('cap', 'Cap'),
    AvatarOption('beanie', 'Beanie'),
    AvatarOption('headphones', 'Headphones'),
    AvatarOption('turban', 'Turban'),
    AvatarOption('headscarf', 'Headscarf'),
  ];

  /// Every id [accessory] may hold: [headAccessories], plus 'bindi' kept
  /// for avatars saved before it moved to [faceAccessory].
  static const accessories = [
    ...headAccessories,
    AvatarOption('bindi', 'Bindi'),
  ];

  static const faceAccessories = [
    AvatarOption('none', 'None'),
    AvatarOption('bindi', 'Bindi'),
  ];

  static const outfits = [
    AvatarOption('tee', 'T-shirt'),
    AvatarOption('hoodie', 'Hoodie'),
    AvatarOption('shirt', 'Shirt'),
    AvatarOption('kurta', 'Kurta'),
    AvatarOption('saree', 'Saree'),
    AvatarOption('dress', 'Dress'),
    AvatarOption('sweater', 'Sweater'),
  ];

  static const outfitColors = [
    AvatarSwatch('rose', 'Rose', Color(0xFFE05C7B)),
    AvatarSwatch('coral', 'Coral', Color(0xFFF08A6B)),
    AvatarSwatch('mustard', 'Mustard', Color(0xFFE2B33F)),
    AvatarSwatch('sage', 'Sage', Color(0xFF8DAA82)),
    AvatarSwatch('teal', 'Teal', Color(0xFF2E9C93)),
    AvatarSwatch('navy', 'Navy', Color(0xFF2F4A7A)),
    AvatarSwatch('lilac', 'Lilac', Color(0xFFA48BD6)),
    AvatarSwatch('white', 'White', Color(0xFFF4F1EE)),
    AvatarSwatch('charcoal', 'Charcoal', Color(0xFF3A3638)),
  ];

  static const backgrounds = [
    AvatarSwatch('blush', 'Blush', Color(0xFFFCE1E7)),
    AvatarSwatch('peach', 'Peach', Color(0xFFFDE5D2)),
    AvatarSwatch('butter', 'Butter', Color(0xFFFFF1C7)),
    AvatarSwatch('mint', 'Mint', Color(0xFFDDF2E3)),
    AvatarSwatch('sky', 'Sky', Color(0xFFDCEBFA)),
    AvatarSwatch('lavender', 'Lavender', Color(0xFFE9E1F8)),
  ];

  // ---- Lookups ---------------------------------------------------------

  /// The defaults every unknown or missing id falls back to.
  static const _defaults = AvatarConfig();

  /// The swatch for [id], or for [fallback] (a field's default) when [id]
  /// is unknown.
  static AvatarSwatch _swatch(
    List<AvatarSwatch> list,
    String id,
    String fallback,
  ) => list.firstWhere(
    (s) => s.id == id,
    orElse: () => list.firstWhere((s) => s.id == fallback),
  );

  static String _option(List<AvatarOption> list, String? id, String fallback) =>
      list.any((o) => o.id == id) ? id! : fallback;

  static String _swatchId(
    List<AvatarSwatch> list,
    String? id,
    String fallback,
  ) => list.any((s) => s.id == id) ? id! : fallback;

  Color get skinColor => _swatch(skins, skin, _defaults.skin).color;
  Color get hairTint =>
      _swatch(hairColors, hairColor, _defaults.hairColor).color;
  Color get eyeTint => _swatch(eyeColors, eyeColor, _defaults.eyeColor).color;
  Color get outfitTint =>
      _swatch(outfitColors, outfitColor, _defaults.outfitColor).color;
  Color get backgroundColor =>
      _swatch(backgrounds, background, _defaults.background).color;

  /// This avatar with an older 'bindi' [accessory] moved to
  /// [faceAccessory], so it can be combined with a head accessory.
  AvatarConfig get withBindiOnFace => accessory == 'bindi'
      ? copyWith(accessory: 'none', faceAccessory: 'bindi')
      : this;

  /// Whether a bindi is worn, either as the face accessory or (for older
  /// avatars) as the head accessory.
  bool get hasBindi => faceAccessory == 'bindi' || accessory == 'bindi';

  // ---- Storage ---------------------------------------------------------

  Map<String, dynamic> toMap() => {
    'skin': skin,
    'face': face,
    'hair': hair,
    'hairColor': hairColor,
    'eyes': eyes,
    'eyeColor': eyeColor,
    'brows': brows,
    'facialHair': facialHair,
    'glasses': glasses,
    'accessory': accessory,
    'faceAccessory': faceAccessory,
    'outfit': outfit,
    'outfitColor': outfitColor,
    'background': background,
  };

  /// Null when there is no avatar yet. Unknown or missing option ids fall
  /// back to that field's default (never just the first option, so an
  /// unknown skin tone doesn't turn into the lightest one).
  static AvatarConfig? fromMap(Object? raw) {
    if (raw is! Map) return null;
    String? s(String key) => raw[key] is String ? raw[key] as String : null;
    const d = _defaults;
    return AvatarConfig(
      skin: _swatchId(skins, s('skin'), d.skin),
      face: _option(faces, s('face'), d.face),
      hair: _option(hairs, s('hair'), d.hair),
      hairColor: _swatchId(hairColors, s('hairColor'), d.hairColor),
      eyes: _option(eyeStyles, s('eyes'), d.eyes),
      eyeColor: _swatchId(eyeColors, s('eyeColor'), d.eyeColor),
      brows: _option(browStyles, s('brows'), d.brows),
      facialHair: _option(facialHairs, s('facialHair'), d.facialHair),
      glasses: _option(glassesStyles, s('glasses'), d.glasses),
      accessory: _option(accessories, s('accessory'), d.accessory),
      faceAccessory: _option(
        faceAccessories,
        s('faceAccessory'),
        d.faceAccessory,
      ),
      outfit: _option(outfits, s('outfit'), d.outfit),
      outfitColor: _swatchId(outfitColors, s('outfitColor'), d.outfitColor),
      background: _swatchId(backgrounds, s('background'), d.background),
    );
  }

  /// A random but tasteful avatar, for "Surprise me" in the builder.
  static AvatarConfig random([Random? random]) {
    final r = random ?? Random();
    T pick<T>(List<T> list) => list[r.nextInt(list.length)];
    return AvatarConfig(
      skin: pick(skins).id,
      face: pick(faces).id,
      hair: pick(hairs).id,
      hairColor: pick(hairColors.take(6).toList()).id,
      eyes: pick(eyeStyles).id,
      eyeColor: pick(eyeColors).id,
      brows: pick(browStyles).id,
      facialHair: r.nextInt(3) == 0 ? pick(facialHairs).id : 'none',
      glasses: r.nextInt(3) == 0 ? pick(glassesStyles).id : 'none',
      accessory: r.nextInt(2) == 0 ? pick(headAccessories).id : 'none',
      faceAccessory: r.nextInt(4) == 0 ? 'bindi' : 'none',
      outfit: pick(outfits).id,
      outfitColor: pick(outfitColors).id,
      background: pick(backgrounds).id,
    );
  }

  AvatarConfig copyWith({
    String? skin,
    String? face,
    String? hair,
    String? hairColor,
    String? eyes,
    String? eyeColor,
    String? brows,
    String? facialHair,
    String? glasses,
    String? accessory,
    String? faceAccessory,
    String? outfit,
    String? outfitColor,
    String? background,
  }) => AvatarConfig(
    skin: skin ?? this.skin,
    face: face ?? this.face,
    hair: hair ?? this.hair,
    hairColor: hairColor ?? this.hairColor,
    eyes: eyes ?? this.eyes,
    eyeColor: eyeColor ?? this.eyeColor,
    brows: brows ?? this.brows,
    facialHair: facialHair ?? this.facialHair,
    glasses: glasses ?? this.glasses,
    accessory: accessory ?? this.accessory,
    faceAccessory: faceAccessory ?? this.faceAccessory,
    outfit: outfit ?? this.outfit,
    outfitColor: outfitColor ?? this.outfitColor,
    background: background ?? this.background,
  );

  @override
  bool operator ==(Object other) =>
      other is AvatarConfig && _equalMaps(other.toMap(), toMap());

  @override
  int get hashCode => Object.hashAll(toMap().values);

  static bool _equalMaps(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a.length == b.length && a.keys.every((k) => a[k] == b[k]);
}
