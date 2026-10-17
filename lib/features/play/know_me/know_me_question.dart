/// One "How well do you know me?" question, phrased two ways.
///
/// The person being guessed about reads [self] ("My ideal Sunday is…");
/// their partner reads [partner] with `{name}` filled in ("Asha's ideal
/// Sunday is…"). [options] are the same for both, so an answer and a guess
/// are both just an index into them.
class KnowMeQuestion {
  const KnowMeQuestion({
    required this.id,
    required this.self,
    required this.partner,
    required this.options,
  });

  /// Stable id stored in the game, so never rename one that has shipped.
  final String id;
  final String self;

  /// Contains `{name}`.
  final String partner;
  final List<String> options;

  static const namePlaceholder = '{name}';

  /// The question as the guesser reads it, about [name].
  String about(String name) => partner.replaceAll(namePlaceholder, name);

  /// The text for whoever is reading: [self] when [aboutName] is null.
  String textFor({String? aboutName}) =>
      aboutName == null ? self : about(aboutName);
}
