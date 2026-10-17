/// The kinds of couple stickers, in picker order. [id] is what messages
/// store as `sticker.category`, so ids must never change.
enum StickerCategory {
  love('Love', '❤️'),
  romantic('Romantic', '🌹'),
  missYou('Missing you', '🥺'),
  sorry('Sorry', '🩹'),
  goodMorning('Good morning', '☀️'),
  goodNight('Good night', '🌙'),
  cheer('Cheer up', '🎉'),
  funny('Funny', '😜');

  const StickerCategory(this.label, this.emoji);

  final String label;
  final String emoji;

  String get id => name;

  /// Null for ids this version doesn't know.
  static StickerCategory? fromId(String? id) {
    for (final category in values) {
      if (category.id == id) return category;
    }
    return null;
  }
}
