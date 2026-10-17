/// Whether a card asks a question or sets a playful challenge.
enum TruthOrDareKind {
  truth('truth', 'Truth'),
  dare('dare', 'Dare');

  const TruthOrDareKind(this.id, this.label);
  final String id;
  final String label;

  static TruthOrDareKind? fromId(Object? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// One card from the bank. [id] is stable across app versions, so game
/// documents can refer to it.
class TruthOrDareCard {
  const TruthOrDareCard(this.kind, this.id, this.text);

  final TruthOrDareKind kind;
  final String id;
  final String text;

  Map<String, dynamic> toMap() => {'kind': kind.id, 'id': id, 'text': text};

  /// Null when [data] isn't a card.
  static TruthOrDareCard? fromMap(Object? data) {
    if (data is! Map) return null;
    final kind = TruthOrDareKind.fromId(data['kind']);
    final id = data['id'];
    final text = data['text'];
    if (kind == null || id is! String || text is! String) return null;
    return TruthOrDareCard(kind, id, text);
  }
}

/// The card bank: romantic, PG, and playable long-distance. Dares are
/// done in chat or on a call (voice notes, selfies, songs, drawings).
///
/// Ids never change once shipped; add new cards with new ids.
class TruthOrDareCards {
  const TruthOrDareCards._();

  static const truths = <TruthOrDareCard>[
    _T('t01', 'What was your very first impression of me?'),
    _T('t02', 'What\'s a small thing I do that always makes you smile?'),
    _T('t03', 'Which memory of us do you replay most often?'),
    _T('t04', 'When did you first realise you really liked me?'),
    _T('t05', 'What\'s a song that reminds you of us?'),
    _T('t06', 'What\'s something sweet you\'ve never told me?'),
    _T('t07', 'What\'s your favourite photo of us, and why?'),
    _T('t08', 'What\'s the silliest thing you\'ve done to impress me?'),
    _T('t09', 'If we could teleport anywhere for a day, where would we go?'),
    _T('t10', 'What\'s a habit of mine you secretly find cute?'),
    _T('t11', 'What\'s the best gift I\'ve ever given you?'),
    _T('t12', 'What\'s one dream you want us to chase together?'),
    _T('t13', 'What\'s something you\'d love us to learn together?'),
    _T('t14', 'What nickname would you secretly love me to call you?'),
    _T('t15', 'Which of my outfits is your favourite?'),
    _T('t16', 'What was going through your head on our first date?'),
    _T('t17', 'Which romantic movie scene would you recreate with me?'),
    _T('t18', 'When do you feel most loved by me?'),
    _T('t19', 'What\'s one thing I could do this week to make your day?'),
    _T('t20', 'What\'s a worry you\'ve never really talked about?'),
    _T('t21', 'What does "home" mean to you?'),
    _T('t22', 'What are you proud of that you don\'t say out loud enough?'),
    _T('t23', 'How have I changed you for the better?'),
    _T('t24', 'When did you feel really understood by me?'),
    _T('t25', 'What would your perfect lazy Sunday with me look like?'),
    _T('t26', 'What\'s the funniest misunderstanding we\'ve ever had?'),
    _T('t27', 'If our story were a movie, what would it be called?'),
    _T('t28', 'Who would play me in the movie of our story?'),
    _T('t29', 'What\'s a weird food combo you secretly love?'),
    _T('t30', 'What\'s your guilty-pleasure song?'),
    _T('t31', 'What childhood memory still makes you laugh?'),
    _T('t32', 'What\'s on your bucket list that you\'ve never told anyone?'),
    _T('t33', 'What do you miss most about me when we\'re apart?'),
    _T('t34', 'What\'s a tiny moment from today you\'d like to share?'),
    _T('t35', 'If you could relive one day with me, which would it be?'),
    _T('t36', 'What do you love about the way I laugh?'),
    _T('t37', 'What one word describes us best?'),
    _T('t38', 'Who in your life would you love me to know better?'),
    _T('t39', 'What tradition would you love us to start?'),
    _T('t40', 'Which emoji is basically me?'),
    _T('t41', 'What\'s the cheesiest line you know? Say it like you mean it.'),
    _T('t42', 'If we were animals, what would you be, and what would I be?'),
    _T('t43', 'What did you dream about most recently?'),
    _T('t44', 'What have you bragged to a friend about me?'),
    _T('t45', 'What would you name our future pet?'),
    _T('t46', 'What\'s your love language, and what do you think mine is?'),
    _T('t47', 'What\'s a compliment from me you still remember?'),
    _T('t48', 'What\'s the best advice I\'ve ever given you?'),
    _T('t49', 'What\'s one thing you want us to do more of?'),
    _T('t50', 'Where do you see us in five years?'),
    _T('t51', 'What\'s a small worry I could help you with right now?'),
    _T('t52', 'What\'s the bravest thing you\'ve ever done?'),
    _T('t53', 'What made you laugh hardest this month?'),
    _T('t54', 'Which superpower would make our dates even better?'),
    _T('t55', 'What\'s a place that feels like "us"?'),
  ];

  static const dares = <TruthOrDareCard>[
    _D('d01', 'Send me a voice note singing the chorus of our song.'),
    _D('d02', 'Take a selfie with your goofiest face and send it in chat.'),
    _D('d03', 'Draw a portrait of me in 60 seconds and send a photo.'),
    _D('d04', 'Send three emojis that sum up your day, then explain them.'),
    _D('d05', 'Write me a four-line poem right now and send it.'),
    _D('d06', 'Send a voice note about your favourite memory of us.'),
    _D('d07', 'Do your best impression of me for 20 seconds on a call.'),
    _D('d08', 'Send me a photo of the view from where you are right now.'),
    _D('d09', 'Share a photo from your gallery that always makes you smile.'),
    _D('d10', 'Send me a song that says how you feel about me.'),
    _D('d11', 'Text me a compliment using only emojis.'),
    _D('d12', 'Record a 15-second "weather report" about your mood.'),
    _D('d13', 'Send a selfie in your best model pose.'),
    _D('d14', 'Write my name in the most creative way and send a photo.'),
    _D('d15', 'Narrate our love story in a movie-trailer voice note.'),
    _D('d16', 'Make a heart with your hands and send a selfie.'),
    _D('d17', 'Tell me three things you love about me in a voice note.'),
    _D('d18', 'Send a photo of something near you that reminds you of me.'),
    _D('d19', 'Hum a song in a voice note and let me guess it.'),
    _D('d20', 'Plan our next date in exactly five messages. Go!'),
    _D('d21', 'Send a GIF that sums up our relationship.'),
    _D('d22', 'Do a 10-second happy dance on a video call or send a clip.'),
    _D('d23', 'Invent a secret handshake and teach it to me on video.'),
    _D('d24', 'Write a tiny love note on paper and send a photo of it.'),
    _D('d25', 'Send a voice note saying "I love you" in a funny accent.'),
    _D('d26', 'Describe our first date like a sports commentator.'),
    _D('d27', 'Share the song you\'ve played most lately, and why.'),
    _D('d28', 'Draw us as cartoon characters and send it.'),
    _D('d29', 'Send me a voice note of your best laugh.'),
    _D('d30', 'Take a selfie with your favourite mug or snack and send it.'),
    _D('d31', 'Give me a sweet new name in your contacts and screenshot it.'),
    _D('d32', 'Write a haiku about my smile.'),
    _D('d33', 'Send a photo of your hands making a heart around something.'),
    _D('d34', 'Tell me a joke so bad it\'s good.'),
    _D('d35', 'Read your last message to me aloud, dramatically.'),
    _D('d36', 'Set a photo of us as your phone wallpaper for a day.'),
    _D('d37', 'Recreate one of our old photos and send it.'),
    _D('d38', 'Send a "postcard": a photo plus one line from where you are.'),
    _D('d39', 'Name five things you\'re grateful for about us in a minute.'),
    _D('d40', 'Say something romantic in your best robot voice.'),
    _D('d41', 'Send a voice note describing your perfect date with me.'),
    _D('d42', 'Sketch our dream home and send it.'),
    _D('d43', 'Send a selfie with your best "I miss you" face.'),
    _D('d44', 'Write me an acrostic poem with my name.'),
    _D('d45', 'Teach me a sweet word in another language by voice note.'),
    _D('d46', 'Send a voice note of you whistling or humming our song.'),
    _D('d47', 'Show me something you\'ve kept that reminds you of me.'),
    _D('d48', 'Speak only in rhymes for your next three messages.'),
    _D('d49', 'Send a "thank you" voice note for something I did lately.'),
    _D('d50', 'Make me a mini playlist of three songs and share it.'),
    _D('d51', 'Write a two-sentence fairy tale starring us.'),
    _D('d52', 'Send a photo of the sky right now.'),
    _D('d53', 'Give me a voice-note tour of your room like a tour guide.'),
    _D('d54', 'Send a selfie with a cute filter of your choice.'),
    _D('d55', 'Give me a pet name for today and use it in every message.'),
  ];

  static List<TruthOrDareCard> of(TruthOrDareKind kind) =>
      kind == TruthOrDareKind.truth ? truths : dares;

  static final Map<String, TruthOrDareCard> _byId = {
    for (final c in [...truths, ...dares]) c.id: c,
  };

  /// The card with [id], or null if this version doesn't know it.
  static TruthOrDareCard? byId(String id) => _byId[id];
}

class _T extends TruthOrDareCard {
  const _T(String id, String text) : super(TruthOrDareKind.truth, id, text);
}

class _D extends TruthOrDareCard {
  const _D(String id, String text) : super(TruthOrDareKind.dare, id, text);
}
