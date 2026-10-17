import 'package:couple_app/features/stickers/models/sticker_category.dart';

/// One line from the quotes bank. [id] is stable so scenes can name their
/// default quote.
class StickerQuote {
  const StickerQuote(this.id, this.category, this.text);

  final String id;
  final StickerCategory category;
  final String text;
}
