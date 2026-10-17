/// The kinds of one-tap love message a partner can send.
enum LoveTap {
  thinking('thinking', '💭', 'Thinking of you', 'is thinking of you'),
  love('love', '❤️', 'Love you', 'sent you love'),
  missYou('miss', '🥺', 'Miss you', 'misses you'),
  hug('hug', '🤗', 'Hug', 'sent you a hug'),
  kiss('kiss', '😘', 'Kiss', 'sent you a kiss');

  const LoveTap(this.id, this.emoji, this.label, this.receivedText);

  final String id;
  final String emoji;
  final String label;

  /// Completes "[partner name] …" on the receiving phone.
  final String receivedText;

  /// Older nudges have no kind and were all "thinking of you".
  static LoveTap fromId(String? id) {
    for (final tap in LoveTap.values) {
      if (tap.id == id) return tap;
    }
    return LoveTap.thinking;
  }
}
