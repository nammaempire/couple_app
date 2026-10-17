import 'dart:ui';

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/stickers/data/sticker_quotes.dart';
import 'package:couple_app/features/stickers/models/sticker_category.dart';
import 'package:couple_app/features/stickers/models/sticker_quote.dart';
import 'package:couple_app/features/stickers/models/sticker_scene.dart';

/// Every couple sticker scene, grouped by category in picker order.
///
/// Scene ids are stored on messages: never rename or remove one. A scene
/// this version doesn't know falls back to its category's first scene.
abstract final class StickerCatalog {
  static const _love = [Color(0xFFFFE6EE), Color(0xFFFFC4D6)];
  static const _loveAccent = Color(0xFFE8466E);
  static const _romantic = [Color(0xFFF3E6FF), Color(0xFFFFD3E6)];
  static const _romanticAccent = Color(0xFFD6458A);
  static const _romanticNight = [Color(0xFFDFE4FF), Color(0xFFEBD8FF)];
  static const _romanticNightAccent = Color(0xFFC9488F);
  static const _missYou = [Color(0xFFE4EEFF), Color(0xFFD6DCF4)];
  static const _missYouAccent = Color(0xFFE06A88);
  static const _sorry = [Color(0xFFFFF1E2), Color(0xFFFFD9D0)];
  static const _sorryAccent = Color(0xFFE5596F);
  static const _goodMorning = [Color(0xFFFFF5CC), Color(0xFFFFDCB8)];
  static const _goodMorningAccent = Color(0xFFEF6B5A);
  static const _goodNight = [Color(0xFFDDE1FB), Color(0xFFC9C2EF)];
  static const _goodNightAccent = Color(0xFFB8509A);
  static const _cheer = [Color(0xFFE4F7E7), Color(0xFFFFF0C2)];
  static const _cheerAccent = Color(0xFFF0567A);
  static const _funny = [Color(0xFFFFF0D4), Color(0xFFDDF1FF)];
  static const _funnyAccent = Color(0xFFFF6F61);

  static const scenes = <StickerScene>[
    StickerScene(
      id: 'love-big-heart',
      category: StickerCategory.love,
      label: 'Big heart',
      layout: StickerLayout.heads,
      senderExpression: AvatarExpression.love,
      partnerExpression: AvatarExpression.love,
      props: [StickerProp.bigHeart, StickerProp.floatingHearts],
      gradient: _love,
      accent: _loveAccent,
      defaultQuoteId: 'love-05',
    ),
    StickerScene(
      id: 'love-hug',
      category: StickerCategory.love,
      label: 'Warm hug',
      layout: StickerLayout.hug,
      senderExpression: AvatarExpression.happy,
      partnerExpression: AvatarExpression.blush,
      props: [StickerProp.floatingHearts, StickerProp.sparkles],
      gradient: _love,
      accent: _loveAccent,
      defaultQuoteId: 'love-04',
    ),
    StickerScene(
      id: 'love-kiss',
      category: StickerCategory.love,
      label: 'A kiss',
      layout: StickerLayout.heads,
      senderExpression: AvatarExpression.kiss,
      partnerExpression: AvatarExpression.blush,
      props: [StickerProp.floatingHearts],
      gradient: _love,
      accent: _loveAccent,
      defaultQuoteId: 'love-09',
    ),
    StickerScene(
      id: 'love-solo-heart',
      category: StickerCategory.love,
      label: 'Holding a heart',
      layout: StickerLayout.solo,
      senderExpression: AvatarExpression.love,
      props: [StickerProp.bigHeart, StickerProp.sparkles],
      gradient: _love,
      accent: _loveAccent,
      defaultQuoteId: 'love-06',
    ),
    StickerScene(
      id: 'love-song',
      category: StickerCategory.love,
      label: 'Our song',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.laugh,
      partnerExpression: AvatarExpression.happy,
      props: [StickerProp.musicNotes, StickerProp.floatingHearts],
      gradient: _love,
      accent: _loveAccent,
      defaultQuoteId: 'love-18',
    ),
    StickerScene(
      id: 'romantic-moon',
      category: StickerCategory.romantic,
      label: 'Under the moon',
      layout: StickerLayout.heads,
      senderExpression: AvatarExpression.love,
      partnerExpression: AvatarExpression.love,
      props: [StickerProp.moonStars, StickerProp.floatingHearts],
      gradient: _romanticNight,
      accent: _romanticNightAccent,
      defaultQuoteId: 'rom-01',
    ),
    StickerScene(
      id: 'romantic-flowers',
      category: StickerCategory.romantic,
      label: 'Flowers for you',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.blush,
      partnerExpression: AvatarExpression.happy,
      props: [StickerProp.flowers, StickerProp.floatingHearts],
      gradient: _romantic,
      accent: _romanticAccent,
      defaultQuoteId: 'rom-05',
    ),
    StickerScene(
      id: 'romantic-wink',
      category: StickerCategory.romantic,
      label: 'A wink',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.wink,
      partnerExpression: AvatarExpression.blush,
      props: [StickerProp.sparkles, StickerProp.floatingHearts],
      gradient: _romantic,
      accent: _romanticAccent,
      defaultQuoteId: 'rom-17',
    ),
    StickerScene(
      id: 'romantic-dance',
      category: StickerCategory.romantic,
      label: 'Slow dance',
      layout: StickerLayout.hug,
      senderExpression: AvatarExpression.happy,
      partnerExpression: AvatarExpression.love,
      props: [StickerProp.musicNotes, StickerProp.floatingHearts],
      gradient: _romantic,
      accent: _romanticAccent,
      defaultQuoteId: 'rom-04',
    ),
    StickerScene(
      id: 'miss-apart',
      category: StickerCategory.missYou,
      label: 'Far apart',
      layout: StickerLayout.apart,
      senderExpression: AvatarExpression.sad,
      partnerExpression: AvatarExpression.sad,
      props: [StickerProp.heartTrail],
      gradient: _missYou,
      accent: _missYouAccent,
      defaultQuoteId: 'miss-12',
    ),
    StickerScene(
      id: 'miss-rain',
      category: StickerCategory.missYou,
      label: 'Rainy day without you',
      layout: StickerLayout.apart,
      senderExpression: AvatarExpression.crying,
      partnerExpression: AvatarExpression.sad,
      props: [StickerProp.rainCloud, StickerProp.heartTrail],
      gradient: _missYou,
      accent: _missYouAccent,
      defaultQuoteId: 'miss-01',
    ),
    StickerScene(
      id: 'miss-pout',
      category: StickerCategory.missYou,
      label: 'Come back',
      layout: StickerLayout.solo,
      senderExpression: AvatarExpression.pout,
      props: [StickerProp.floatingHearts],
      gradient: _missYou,
      accent: _missYouAccent,
      defaultQuoteId: 'miss-07',
    ),
    StickerScene(
      id: 'miss-moon',
      category: StickerCategory.missYou,
      label: 'Same moon',
      layout: StickerLayout.apart,
      senderExpression: AvatarExpression.sad,
      partnerExpression: AvatarExpression.sleepy,
      props: [StickerProp.moonStars, StickerProp.heartTrail],
      gradient: _romanticNight,
      accent: _romanticNightAccent,
      defaultQuoteId: 'miss-03',
    ),
    StickerScene(
      id: 'miss-tears',
      category: StickerCategory.missYou,
      label: 'Teary-eyed',
      layout: StickerLayout.solo,
      senderExpression: AvatarExpression.crying,
      props: [StickerProp.rainCloud],
      gradient: _missYou,
      accent: _missYouAccent,
      defaultQuoteId: 'miss-04',
    ),
    StickerScene(
      id: 'sorry-plaster',
      category: StickerCategory.sorry,
      label: 'Patched-up heart',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.sad,
      partnerExpression: AvatarExpression.pout,
      props: [StickerProp.plasterHeart],
      gradient: _sorry,
      accent: _sorryAccent,
      defaultQuoteId: 'sorry-12',
    ),
    StickerScene(
      id: 'sorry-solo',
      category: StickerCategory.sorry,
      label: 'Really sorry',
      layout: StickerLayout.solo,
      senderExpression: AvatarExpression.sad,
      props: [StickerProp.brokenHeart],
      gradient: _sorry,
      accent: _sorryAccent,
      defaultQuoteId: 'sorry-01',
    ),
    StickerScene(
      id: 'sorry-flowers',
      category: StickerCategory.sorry,
      label: 'Peace flowers',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.blush,
      partnerExpression: AvatarExpression.surprised,
      props: [StickerProp.flowers],
      gradient: _sorry,
      accent: _sorryAccent,
      defaultQuoteId: 'sorry-02',
    ),
    StickerScene(
      id: 'sorry-hug',
      category: StickerCategory.sorry,
      label: 'Hug it out',
      layout: StickerLayout.hug,
      senderExpression: AvatarExpression.crying,
      partnerExpression: AvatarExpression.happy,
      props: [StickerProp.floatingHearts],
      gradient: _sorry,
      accent: _sorryAccent,
      defaultQuoteId: 'sorry-05',
    ),
    StickerScene(
      id: 'morning-sun',
      category: StickerCategory.goodMorning,
      label: 'Sunrise',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.happy,
      partnerExpression: AvatarExpression.sleepy,
      props: [StickerProp.sun],
      gradient: _goodMorning,
      accent: _goodMorningAccent,
      defaultQuoteId: 'gm-01',
    ),
    StickerScene(
      id: 'morning-coffee',
      category: StickerCategory.goodMorning,
      label: 'Morning coffee',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.happy,
      partnerExpression: AvatarExpression.happy,
      props: [StickerProp.coffee, StickerProp.sun],
      gradient: _goodMorning,
      accent: _goodMorningAccent,
      defaultQuoteId: 'gm-03',
    ),
    StickerScene(
      id: 'morning-solo',
      category: StickerCategory.goodMorning,
      label: 'Rise and shine',
      layout: StickerLayout.solo,
      senderExpression: AvatarExpression.laugh,
      props: [StickerProp.sun, StickerProp.sparkles],
      gradient: _goodMorning,
      accent: _goodMorningAccent,
      defaultQuoteId: 'gm-02',
    ),
    StickerScene(
      id: 'morning-flowers',
      category: StickerCategory.goodMorning,
      label: 'Fresh flowers',
      layout: StickerLayout.heads,
      senderExpression: AvatarExpression.happy,
      partnerExpression: AvatarExpression.wink,
      props: [StickerProp.flowers, StickerProp.sun],
      gradient: _goodMorning,
      accent: _goodMorningAccent,
      defaultQuoteId: 'gm-10',
    ),
    StickerScene(
      id: 'night-moon',
      category: StickerCategory.goodNight,
      label: 'Sleepy heads',
      layout: StickerLayout.heads,
      senderExpression: AvatarExpression.sleepy,
      partnerExpression: AvatarExpression.sleepy,
      props: [StickerProp.moonStars, StickerProp.zzz],
      gradient: _goodNight,
      accent: _goodNightAccent,
      defaultQuoteId: 'gn-01',
    ),
    StickerScene(
      id: 'night-solo',
      category: StickerCategory.goodNight,
      label: 'Drifting off',
      layout: StickerLayout.solo,
      senderExpression: AvatarExpression.sleepy,
      props: [StickerProp.moonStars, StickerProp.zzz],
      gradient: _goodNight,
      accent: _goodNightAccent,
      defaultQuoteId: 'gn-03',
    ),
    StickerScene(
      id: 'night-kiss',
      category: StickerCategory.goodNight,
      label: 'Goodnight kiss',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.kiss,
      partnerExpression: AvatarExpression.sleepy,
      props: [StickerProp.moonStars, StickerProp.floatingHearts],
      gradient: _goodNight,
      accent: _goodNightAccent,
      defaultQuoteId: 'gn-06',
    ),
    StickerScene(
      id: 'night-apart',
      category: StickerCategory.goodNight,
      label: 'Good night from afar',
      layout: StickerLayout.apart,
      senderExpression: AvatarExpression.sleepy,
      partnerExpression: AvatarExpression.sleepy,
      props: [StickerProp.moonStars, StickerProp.heartTrail],
      gradient: _goodNight,
      accent: _goodNightAccent,
      defaultQuoteId: 'gn-08',
    ),
    StickerScene(
      id: 'cheer-confetti',
      category: StickerCategory.cheer,
      label: 'Celebration',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.laugh,
      partnerExpression: AvatarExpression.happy,
      props: [StickerProp.confetti],
      gradient: _cheer,
      accent: _cheerAccent,
      defaultQuoteId: 'cheer-08',
    ),
    StickerScene(
      id: 'cheer-solo',
      category: StickerCategory.cheer,
      label: 'You\'ve got this',
      layout: StickerLayout.solo,
      senderExpression: AvatarExpression.happy,
      props: [StickerProp.sparkles, StickerProp.confetti],
      gradient: _cheer,
      accent: _cheerAccent,
      defaultQuoteId: 'cheer-01',
    ),
    StickerScene(
      id: 'cheer-proud',
      category: StickerCategory.cheer,
      label: 'So proud',
      layout: StickerLayout.hug,
      senderExpression: AvatarExpression.love,
      partnerExpression: AvatarExpression.laugh,
      props: [StickerProp.confetti, StickerProp.sparkles],
      gradient: _cheer,
      accent: _cheerAccent,
      defaultQuoteId: 'cheer-02',
    ),
    StickerScene(
      id: 'cheer-shine',
      category: StickerCategory.cheer,
      label: 'Superstar',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.happy,
      partnerExpression: AvatarExpression.wink,
      props: [StickerProp.sun, StickerProp.sparkles],
      gradient: _cheer,
      accent: _cheerAccent,
      defaultQuoteId: 'cheer-13',
    ),
    StickerScene(
      id: 'funny-laugh',
      category: StickerCategory.funny,
      label: 'Giggles',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.laugh,
      partnerExpression: AvatarExpression.laugh,
      props: [StickerProp.confetti],
      gradient: _funny,
      accent: _funnyAccent,
      defaultQuoteId: 'fun-10',
    ),
    StickerScene(
      id: 'funny-wink',
      category: StickerCategory.funny,
      label: 'Cheeky wink',
      layout: StickerLayout.solo,
      senderExpression: AvatarExpression.wink,
      props: [StickerProp.sparkles],
      gradient: _funny,
      accent: _funnyAccent,
      defaultQuoteId: 'fun-07',
    ),
    StickerScene(
      id: 'funny-snacks',
      category: StickerCategory.funny,
      label: 'Coffee break',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.pout,
      partnerExpression: AvatarExpression.laugh,
      props: [StickerProp.coffee],
      gradient: _funny,
      accent: _funnyAccent,
      defaultQuoteId: 'fun-04',
    ),
    StickerScene(
      id: 'funny-surprise',
      category: StickerCategory.funny,
      label: 'Plot twist',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.surprised,
      partnerExpression: AvatarExpression.wink,
      props: [StickerProp.sparkles],
      gradient: _funny,
      accent: _funnyAccent,
      defaultQuoteId: 'fun-15',
    ),
    StickerScene(
      id: 'funny-sleepy',
      category: StickerCategory.funny,
      label: 'Asleep on call',
      layout: StickerLayout.together,
      senderExpression: AvatarExpression.laugh,
      partnerExpression: AvatarExpression.sleepy,
      props: [StickerProp.zzz],
      gradient: _funny,
      accent: _funnyAccent,
      defaultQuoteId: 'fun-06',
    ),
  ];

  /// Scenes in [category], in catalog order.
  static List<StickerScene> forCategory(StickerCategory category) =>
      scenes.where((s) => s.category == category).toList(growable: false);

  static StickerScene? byId(String? id) {
    for (final scene in scenes) {
      if (scene.id == id) return scene;
    }
    return null;
  }

  /// The scene to draw for a stored sticker: [id] if known, else the first
  /// scene of [categoryId], else the very first scene.
  static StickerScene resolve(String? id, String? categoryId) {
    final exact = byId(id);
    if (exact != null) return exact;
    final category = StickerCategory.fromId(categoryId);
    if (category != null) {
      final inCategory = forCategory(category);
      if (inCategory.isNotEmpty) return inCategory.first;
    }
    return scenes.first;
  }

  /// The quote a scene shows until another is chosen.
  static StickerQuote defaultQuote(StickerScene scene) =>
      StickerQuotes.byId(scene.defaultQuoteId) ??
      StickerQuotes.forCategory(scene.category).first;
}
