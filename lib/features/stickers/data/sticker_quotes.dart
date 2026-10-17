import 'package:couple_app/features/stickers/models/sticker_category.dart';
import 'package:couple_app/features/stickers/models/sticker_quote.dart';

/// The quotes bank: short, original lines for each [StickerCategory].
///
/// Ids are stable (scenes name their default by id); add new quotes at the
/// end of a category with the next number rather than renumbering.
abstract final class StickerQuotes {
  static const all = <StickerQuote>[
    // ---- love ----
    StickerQuote(
      'love-01',
      StickerCategory.love,
      'You\'re my favourite notification.',
    ),
    StickerQuote(
      'love-02',
      StickerCategory.love,
      'Out of everyone in the world, my heart keeps choosing you.',
    ),
    StickerQuote(
      'love-03',
      StickerCategory.love,
      'I love you more than yesterday, and yesterday was a lot.',
    ),
    StickerQuote(
      'love-04',
      StickerCategory.love,
      'You make ordinary days feel like a soft place to land.',
    ),
    StickerQuote(
      'love-05',
      StickerCategory.love,
      'Home isn\'t a place anymore. It\'s you.',
    ),
    StickerQuote(
      'love-06',
      StickerCategory.love,
      'Just a reminder: you are so, so loved.',
    ),
    StickerQuote(
      'love-07',
      StickerCategory.love,
      'If hearts could smile, mine would be grinning at you.',
    ),
    StickerQuote(
      'love-08',
      StickerCategory.love,
      'You + me = the best equation I know.',
    ),
    StickerQuote(
      'love-09',
      StickerCategory.love,
      'I\'d pick you in every lifetime, every time.',
    ),
    StickerQuote(
      'love-10',
      StickerCategory.love,
      'Loving you is the easiest thing I\'ve ever done.',
    ),
    StickerQuote(
      'love-11',
      StickerCategory.love,
      'You\'re the best part of my every day.',
    ),
    StickerQuote(
      'love-12',
      StickerCategory.love,
      'My heart does a little happy dance whenever you text.',
    ),
    StickerQuote(
      'love-13',
      StickerCategory.love,
      'Thank you for being exactly you. That\'s who I love.',
    ),
    StickerQuote(
      'love-14',
      StickerCategory.love,
      'Still falling for you, a little more each day.',
    ),
    StickerQuote(
      'love-15',
      StickerCategory.love,
      'You\'re my calm, my chaos and my favourite person.',
    ),
    StickerQuote(
      'love-16',
      StickerCategory.love,
      'I love you. That\'s the whole message.',
    ),
    StickerQuote(
      'love-17',
      StickerCategory.love,
      'Some people find gold. I found you.',
    ),
    StickerQuote(
      'love-18',
      StickerCategory.love,
      'Your laugh is the best sound in the whole world.',
    ),
    // ---- romantic ----
    StickerQuote(
      'rom-01',
      StickerCategory.romantic,
      'Every star tonight is just the sky showing off for you.',
    ),
    StickerQuote(
      'rom-02',
      StickerCategory.romantic,
      'I want a hundred more slow mornings with you.',
    ),
    StickerQuote(
      'rom-03',
      StickerCategory.romantic,
      'Your hand in mine is the loveliest kind of quiet.',
    ),
    StickerQuote(
      'rom-04',
      StickerCategory.romantic,
      'Let\'s dance in the kitchen like nobody\'s watching.',
    ),
    StickerQuote(
      'rom-05',
      StickerCategory.romantic,
      'You still give me butterflies, and I hope you always will.',
    ),
    StickerQuote(
      'rom-06',
      StickerCategory.romantic,
      'One look from you and the whole room goes soft.',
    ),
    StickerQuote(
      'rom-07',
      StickerCategory.romantic,
      'I keep replaying the way you looked at me.',
    ),
    StickerQuote(
      'rom-08',
      StickerCategory.romantic,
      'Save me a dance, and maybe forever too.',
    ),
    StickerQuote(
      'rom-09',
      StickerCategory.romantic,
      'You\'re the sweetest line in every story I tell.',
    ),
    StickerQuote(
      'rom-10',
      StickerCategory.romantic,
      'Meet me under the moon? I\'ll bring the flowers.',
    ),
    StickerQuote(
      'rom-11',
      StickerCategory.romantic,
      'Every love song suddenly makes sense with you.',
    ),
    StickerQuote(
      'rom-12',
      StickerCategory.romantic,
      'I\'d cross the whole city at midnight just to hold you.',
    ),
    StickerQuote(
      'rom-13',
      StickerCategory.romantic,
      'With you, even silence feels like a love letter.',
    ),
    StickerQuote(
      'rom-14',
      StickerCategory.romantic,
      'Can we get lost somewhere, just the two of us?',
    ),
    StickerQuote(
      'rom-15',
      StickerCategory.romantic,
      'You\'re the daydream I keep having, and the real you is even better.',
    ),
    StickerQuote(
      'rom-16',
      StickerCategory.romantic,
      'Wherever you are is exactly where I want to be.',
    ),
    StickerQuote(
      'rom-17',
      StickerCategory.romantic,
      'Your kisses should come with a warning: dangerously sweet.',
    ),
    // ---- missYou ----
    StickerQuote(
      'miss-01',
      StickerCategory.missYou,
      'The distance is loud today. I miss you.',
    ),
    StickerQuote(
      'miss-02',
      StickerCategory.missYou,
      'Counting the sleeps until I can hug you again.',
    ),
    StickerQuote(
      'miss-03',
      StickerCategory.missYou,
      'Same moon, different windows. Thinking of you.',
    ),
    StickerQuote(
      'miss-04',
      StickerCategory.missYou,
      'My arms feel empty without you in them.',
    ),
    StickerQuote(
      'miss-05',
      StickerCategory.missYou,
      'I miss your voice, your laugh and your terrible jokes.',
    ),
    StickerQuote(
      'miss-06',
      StickerCategory.missYou,
      'Everything reminds me of you. Even the boring stuff.',
    ),
    StickerQuote(
      'miss-07',
      StickerCategory.missYou,
      'Come back soon. The couch misses you too.',
    ),
    StickerQuote(
      'miss-08',
      StickerCategory.missYou,
      'Missing you is my full-time job today.',
    ),
    StickerQuote(
      'miss-09',
      StickerCategory.missYou,
      'I\'d trade every minute of today for one hour with you.',
    ),
    StickerQuote(
      'miss-10',
      StickerCategory.missYou,
      'Wish you were here. No, really. Right here.',
    ),
    StickerQuote(
      'miss-11',
      StickerCategory.missYou,
      'My heart is on your side of the map.',
    ),
    StickerQuote(
      'miss-12',
      StickerCategory.missYou,
      'Miles apart, but you\'re still the closest person to me.',
    ),
    StickerQuote(
      'miss-13',
      StickerCategory.missYou,
      'Today I miss you a little more than usual.',
    ),
    StickerQuote(
      'miss-14',
      StickerCategory.missYou,
      'Sending a hug through the screen. Catch it?',
    ),
    StickerQuote(
      'miss-15',
      StickerCategory.missYou,
      'Not long now. Then I\'m never letting go.',
    ),
    StickerQuote(
      'miss-16',
      StickerCategory.missYou,
      'Every song on shuffle is about you today.',
    ),
    StickerQuote(
      'miss-17',
      StickerCategory.missYou,
      'Our next hug is going to be a really long one.',
    ),
    StickerQuote(
      'miss-18',
      StickerCategory.missYou,
      'Our spot on the sofa feels way too big without you.',
    ),
    // ---- sorry ----
    StickerQuote(
      'sorry-01',
      StickerCategory.sorry,
      'I\'m sorry. You matter more to me than being right.',
    ),
    StickerQuote(
      'sorry-02',
      StickerCategory.sorry,
      'I messed up. Can I make it up to you?',
    ),
    StickerQuote(
      'sorry-03',
      StickerCategory.sorry,
      'I hate it when we\'re not okay. I\'m sorry.',
    ),
    StickerQuote(
      'sorry-04',
      StickerCategory.sorry,
      'Sorry for being grumpy. You deserve my best, not my worst.',
    ),
    StickerQuote(
      'sorry-05',
      StickerCategory.sorry,
      'Can we hug it out? I\'ll go first.',
    ),
    StickerQuote(
      'sorry-06',
      StickerCategory.sorry,
      'I\'m sorry I hurt you. I\'m listening now.',
    ),
    StickerQuote(
      'sorry-07',
      StickerCategory.sorry,
      'Truce? I\'ll bring snacks and a real apology.',
    ),
    StickerQuote(
      'sorry-08',
      StickerCategory.sorry,
      'You and me against the problem, not each other.',
    ),
    StickerQuote(
      'sorry-09',
      StickerCategory.sorry,
      'My pride can wait. You can\'t. I\'m sorry.',
    ),
    StickerQuote(
      'sorry-10',
      StickerCategory.sorry,
      'I said things I didn\'t mean. I\'m really sorry.',
    ),
    StickerQuote(
      'sorry-11',
      StickerCategory.sorry,
      'I miss us. Can we start over from hello?',
    ),
    StickerQuote(
      'sorry-12',
      StickerCategory.sorry,
      'Here\'s a plaster for the heart I bruised. I\'m sorry.',
    ),
    StickerQuote(
      'sorry-13',
      StickerCategory.sorry,
      'No excuses, just sorry, and a promise to do better.',
    ),
    StickerQuote(
      'sorry-14',
      StickerCategory.sorry,
      'Forgive me? I\'ll even let you pick the movie.',
    ),
    StickerQuote(
      'sorry-15',
      StickerCategory.sorry,
      'Thank you for being patient with me. I\'m sorry.',
    ),
    StickerQuote(
      'sorry-16',
      StickerCategory.sorry,
      'I was wrong. There, I said it. Love you.',
    ),
    // ---- goodMorning ----
    StickerQuote(
      'gm-01',
      StickerCategory.goodMorning,
      'Good morning, sunshine. The day just got brighter.',
    ),
    StickerQuote(
      'gm-02',
      StickerCategory.goodMorning,
      'Rise and shine, my favourite human.',
    ),
    StickerQuote(
      'gm-03',
      StickerCategory.goodMorning,
      'Coffee\'s brewing and I\'m thinking of you already.',
    ),
    StickerQuote(
      'gm-04',
      StickerCategory.goodMorning,
      'Good morning! You were my first thought today.',
    ),
    StickerQuote(
      'gm-05',
      StickerCategory.goodMorning,
      'Wake up, sleepyhead. The world needs your smile.',
    ),
    StickerQuote(
      'gm-06',
      StickerCategory.goodMorning,
      'Sending you a warm cup of good vibes this morning.',
    ),
    StickerQuote(
      'gm-07',
      StickerCategory.goodMorning,
      'Morning, love. Go be amazing today.',
    ),
    StickerQuote(
      'gm-08',
      StickerCategory.goodMorning,
      'Another day to love you. Lucky me.',
    ),
    StickerQuote(
      'gm-09',
      StickerCategory.goodMorning,
      'Good morning to the reason I smile before breakfast.',
    ),
    StickerQuote(
      'gm-10',
      StickerCategory.goodMorning,
      'Hope your day is as lovely as you are.',
    ),
    StickerQuote(
      'gm-11',
      StickerCategory.goodMorning,
      'Open your eyes, it\'s a brand new day for us.',
    ),
    StickerQuote(
      'gm-12',
      StickerCategory.goodMorning,
      'Morning kisses incoming. Brace yourself.',
    ),
    StickerQuote(
      'gm-13',
      StickerCategory.goodMorning,
      'The sun is up, and so is my love for you.',
    ),
    StickerQuote(
      'gm-14',
      StickerCategory.goodMorning,
      'Hey you. Drink water, eat breakfast, remember I love you.',
    ),
    StickerQuote(
      'gm-15',
      StickerCategory.goodMorning,
      'Five more minutes? Fine. Then I\'m calling you.',
    ),
    StickerQuote(
      'gm-16',
      StickerCategory.goodMorning,
      'Good morning! Today is a good day to be adored.',
    ),
    // ---- goodNight ----
    StickerQuote(
      'gn-01',
      StickerCategory.goodNight,
      'Good night, love. Dream of us.',
    ),
    StickerQuote(
      'gn-02',
      StickerCategory.goodNight,
      'Sleep tight. I\'ll be right here in the morning.',
    ),
    StickerQuote(
      'gn-03',
      StickerCategory.goodNight,
      'Closing my eyes and holding you in my thoughts.',
    ),
    StickerQuote(
      'gn-04',
      StickerCategory.goodNight,
      'The stars are out, and I\'m thinking of you.',
    ),
    StickerQuote(
      'gn-05',
      StickerCategory.goodNight,
      'Sweet dreams to the best part of my day.',
    ),
    StickerQuote(
      'gn-06',
      StickerCategory.goodNight,
      'Goodnight kiss, delivered. Sleep well.',
    ),
    StickerQuote(
      'gn-07',
      StickerCategory.goodNight,
      'Rest now. You did enough today.',
    ),
    StickerQuote(
      'gn-08',
      StickerCategory.goodNight,
      'Wish I could fall asleep on your shoulder tonight.',
    ),
    StickerQuote(
      'gn-09',
      StickerCategory.goodNight,
      'Leaving the moon on for you. Good night.',
    ),
    StickerQuote(
      'gn-10',
      StickerCategory.goodNight,
      'I\'ll meet you in my dreams. Don\'t be late.',
    ),
    StickerQuote(
      'gn-11',
      StickerCategory.goodNight,
      'Snuggle up. I\'m sending the warmest hug.',
    ),
    StickerQuote(
      'gn-12',
      StickerCategory.goodNight,
      'Night night. You are loved, even while you sleep.',
    ),
    StickerQuote(
      'gn-13',
      StickerCategory.goodNight,
      'Put the phone down and sleep, you cutie.',
    ),
    StickerQuote(
      'gn-14',
      StickerCategory.goodNight,
      'Tomorrow I\'ll love you more. Good night for now.',
    ),
    StickerQuote(
      'gn-15',
      StickerCategory.goodNight,
      'The day was better because you were in it. Sleep well.',
    ),
    StickerQuote(
      'gn-16',
      StickerCategory.goodNight,
      'Sleepy kisses and a whole lot of love.',
    ),
    // ---- cheer ----
    StickerQuote(
      'cheer-01',
      StickerCategory.cheer,
      'You\'ve got this. I\'ve got you.',
    ),
    StickerQuote(
      'cheer-02',
      StickerCategory.cheer,
      'I\'m so proud of you, I could burst.',
    ),
    StickerQuote(
      'cheer-03',
      StickerCategory.cheer,
      'Go show them what I already know: you\'re brilliant.',
    ),
    StickerQuote(
      'cheer-04',
      StickerCategory.cheer,
      'Deep breath. You\'re stronger than you feel right now.',
    ),
    StickerQuote(
      'cheer-05',
      StickerCategory.cheer,
      'Whatever happens, I\'m in your corner.',
    ),
    StickerQuote(
      'cheer-06',
      StickerCategory.cheer,
      'Your hard work is going to pay off. I believe in you.',
    ),
    StickerQuote(
      'cheer-07',
      StickerCategory.cheer,
      'Tough day? Hand it over, we\'ll carry it together.',
    ),
    StickerQuote(
      'cheer-08',
      StickerCategory.cheer,
      'You did it! Happy dance in your honour.',
    ),
    StickerQuote(
      'cheer-09',
      StickerCategory.cheer,
      'One step at a time. I\'m cheering at every one.',
    ),
    StickerQuote(
      'cheer-10',
      StickerCategory.cheer,
      'Not every day is easy, but you are amazing every day.',
    ),
    StickerQuote(
      'cheer-11',
      StickerCategory.cheer,
      'I\'m your biggest fan, and I\'m wearing the T-shirt.',
    ),
    StickerQuote(
      'cheer-12',
      StickerCategory.cheer,
      'Remember how far you\'ve come. I do.',
    ),
    StickerQuote('cheer-13', StickerCategory.cheer, 'Go get them, superstar.'),
    StickerQuote(
      'cheer-14',
      StickerCategory.cheer,
      'You don\'t have to be perfect to be wonderful.',
    ),
    StickerQuote(
      'cheer-15',
      StickerCategory.cheer,
      'Whatever today brings, you come home to me.',
    ),
    StickerQuote(
      'cheer-16',
      StickerCategory.cheer,
      'Proud of you. Always have been, always will be.',
    ),
    // ---- funny ----
    StickerQuote(
      'fun-01',
      StickerCategory.funny,
      'I love you even when you steal the blanket.',
    ),
    StickerQuote(
      'fun-02',
      StickerCategory.funny,
      'You\'re my number one person to do nothing with.',
    ),
    StickerQuote(
      'fun-03',
      StickerCategory.funny,
      'Warning: I\'m about to text you seventeen more times.',
    ),
    StickerQuote(
      'fun-04',
      StickerCategory.funny,
      'Thinking about you. Also about snacks. Mostly you.',
    ),
    StickerQuote(
      'fun-05',
      StickerCategory.funny,
      'I\'d share my fries with you. That\'s true love.',
    ),
    StickerQuote(
      'fun-06',
      StickerCategory.funny,
      'You fell asleep on call again. It was adorable.',
    ),
    StickerQuote(
      'fun-07',
      StickerCategory.funny,
      'Who gave you permission to be this cute?',
    ),
    StickerQuote(
      'fun-08',
      StickerCategory.funny,
      'Reminder: you still owe me a hundred kisses.',
    ),
    StickerQuote(
      'fun-09',
      StickerCategory.funny,
      'I\'m not clingy, I just want to be with you every second.',
    ),
    StickerQuote(
      'fun-10',
      StickerCategory.funny,
      'Let\'s be weird together forever.',
    ),
    StickerQuote(
      'fun-11',
      StickerCategory.funny,
      'Your silly faces are my favourite memes.',
    ),
    StickerQuote(
      'fun-12',
      StickerCategory.funny,
      'Love you more than pizza. Don\'t tell the pizza.',
    ),
    StickerQuote(
      'fun-13',
      StickerCategory.funny,
      'Annoying you is my love language.',
    ),
    StickerQuote(
      'fun-14',
      StickerCategory.funny,
      'You + me + pyjamas + food = perfect evening.',
    ),
    StickerQuote(
      'fun-15',
      StickerCategory.funny,
      'Plot twist: I\'m thinking about you. Again.',
    ),
    StickerQuote(
      'fun-16',
      StickerCategory.funny,
      'Officially reporting: I miss your silly face.',
    ),
  ];

  /// Quotes for [category], in bank order.
  static List<StickerQuote> forCategory(StickerCategory category) =>
      all.where((q) => q.category == category).toList(growable: false);

  static StickerQuote? byId(String id) {
    for (final quote in all) {
      if (quote.id == id) return quote;
    }
    return null;
  }
}
