import 'package:couple_app/features/play/know_me/know_me_question.dart';

/// Every question the quiz can deal. Ids are stored in games, so keep them
/// stable: add new questions freely, but never rename or reorder options
/// of one that has shipped.
class KnowMeBank {
  const KnowMeBank._();

  static const all = <KnowMeQuestion>[
    KnowMeQuestion(
      id: 'ideal_sunday',
      self: 'My ideal Sunday is…',
      partner: '{name}\'s ideal Sunday is…',
      options: [
        'Sleeping in late',
        'A long walk outside',
        'Movies and snacks',
        'Seeing friends',
      ],
    ),
    KnowMeQuestion(
      id: 'comfort_food',
      self: 'My go-to comfort food is…',
      partner: '{name}\'s go-to comfort food is…',
      options: ['Pizza', 'Something spicy', 'Ice cream', 'A home-cooked meal'],
    ),
    KnowMeQuestion(
      id: 'dream_trip',
      self: 'My dream trip would be…',
      partner: '{name}\'s dream trip would be…',
      options: [
        'A beach island',
        'Snowy mountains',
        'A big-city adventure',
        'A countryside road trip',
      ],
    ),
    KnowMeQuestion(
      id: 'feel_loved',
      self: 'I feel most loved when you…',
      partner: '{name} feels most loved when you…',
      options: [
        'Say something sweet',
        'Spend quality time together',
        'Help without being asked',
        'Give a little surprise',
      ],
    ),
    KnowMeQuestion(
      id: 'bird_or_owl',
      self: 'I\'m more of a…',
      partner: '{name} is more of a…',
      options: [
        'Early bird',
        'Night owl',
        'Afternoon person',
        'Depends on the day',
      ],
    ),
    KnowMeQuestion(
      id: 'superpower',
      self: 'The superpower I\'d pick is…',
      partner: 'The superpower {name} would pick is…',
      options: ['Flying', 'Teleporting', 'Reading minds', 'Stopping time'],
    ),
    KnowMeQuestion(
      id: 'surprise_day_off',
      self: 'With a surprise day off, I\'d…',
      partner: 'With a surprise day off, {name} would…',
      options: [
        'Stay in bed',
        'Go on an adventure',
        'Catch up on chores',
        'Binge a show',
      ],
    ),
    KnowMeQuestion(
      id: 'drink_order',
      self: 'My usual drink order is…',
      partner: '{name}\'s usual drink order is…',
      options: ['Coffee', 'Tea', 'Juice or a smoothie', 'Just water'],
    ),
    KnowMeQuestion(
      id: 'movie_genre',
      self: 'Tonight, the movie genre I\'d pick is…',
      partner: 'Tonight, the movie genre {name} would pick is…',
      options: ['Comedy', 'Romance', 'Thriller', 'Animation'],
    ),
    KnowMeQuestion(
      id: 'stress_relief',
      self: 'When I\'m stressed, I…',
      partner: 'When {name} is stressed, they…',
      options: [
        'Need some quiet',
        'Want to talk it out',
        'Go for a walk',
        'Eat something nice',
      ],
    ),
    KnowMeQuestion(
      id: 'ideal_pet',
      self: 'My ideal pet is…',
      partner: '{name}\'s ideal pet is…',
      options: ['A dog', 'A cat', 'Something unusual', 'No pets, thanks'],
    ),
    KnowMeQuestion(
      id: 'season',
      self: 'My favourite season is…',
      partner: '{name}\'s favourite season is…',
      options: ['Spring', 'Summer', 'Rainy season', 'Winter'],
    ),
    KnowMeQuestion(
      id: 'lottery',
      self: 'If I won the lottery, I\'d first…',
      partner: 'If {name} won the lottery, they\'d first…',
      options: [
        'Travel the world',
        'Buy a dream home',
        'Spoil family and friends',
        'Stop working and relax',
      ],
    ),
    KnowMeQuestion(
      id: 'date_night',
      self: 'My perfect date night is…',
      partner: '{name}\'s perfect date night is…',
      options: [
        'A fancy dinner out',
        'A cosy night in',
        'Something adventurous',
        'A long late-night call',
      ],
    ),
    KnowMeQuestion(
      id: 'snack',
      self: 'My favourite snack is…',
      partner: '{name}\'s favourite snack is…',
      options: ['Chips', 'Chocolate', 'Fruit', 'Something fried'],
    ),
    KnowMeQuestion(
      id: 'secret_talent',
      self: 'My secret talent is…',
      partner: '{name}\'s secret talent is…',
      options: [
        'Cooking',
        'Singing',
        'Making people laugh',
        'Remembering details',
      ],
    ),
    KnowMeQuestion(
      id: 'dream_job',
      self: 'If I could have any job, I\'d be…',
      partner: 'If {name} could have any job, they\'d be…',
      options: [
        'An artist or writer',
        'A chef',
        'An explorer',
        'A business owner',
      ],
    ),
    KnowMeQuestion(
      id: 'holiday_style',
      self: 'On holiday, I like to…',
      partner: 'On holiday, {name} likes to…',
      options: [
        'Plan every detail',
        'Wing it',
        'Relax by the water',
        'See every sight',
      ],
    ),
    KnowMeQuestion(
      id: 'road_trip_music',
      self: 'On a road trip, I\'d play…',
      partner: 'On a road trip, {name} would play…',
      options: [
        'Old classics',
        'The latest hits',
        'Movie soundtracks',
        'Podcasts instead',
      ],
    ),
    KnowMeQuestion(
      id: 'sick_day',
      self: 'When I\'m unwell, I want…',
      partner: 'When {name} is unwell, they want…',
      options: [
        'Peace and quiet',
        'Lots of looking after',
        'Soup and a blanket',
        'To pretend all is fine',
      ],
    ),
    KnowMeQuestion(
      id: 'forever_cuisine',
      self: 'If I could eat one cuisine forever, it\'d be…',
      partner: 'If {name} could eat one cuisine forever, it\'d be…',
      options: ['Indian', 'Italian', 'Chinese', 'Mexican'],
    ),
    KnowMeQuestion(
      id: 'least_fav_chore',
      self: 'The chore I dislike most is…',
      partner: 'The chore {name} dislikes most is…',
      options: [
        'Washing dishes',
        'Laundry',
        'Cleaning the bathroom',
        'Grocery shopping',
      ],
    ),
    KnowMeQuestion(
      id: 'best_gift',
      self: 'The gift that would make me happiest is…',
      partner: 'The gift that would make {name} happiest is…',
      options: [
        'A handwritten letter',
        'A surprise outing',
        'Something practical',
        'Flowers or sweets',
      ],
    ),
    KnowMeQuestion(
      id: 'cancelled_plans',
      self: 'When plans get cancelled last minute, I feel…',
      partner: 'When plans get cancelled last minute, {name} feels…',
      options: ['Secretly relieved', 'A bit sad', 'Annoyed', 'Totally fine'],
    ),
    KnowMeQuestion(
      id: 'party_self',
      self: 'At a party, I\'m usually…',
      partner: 'At a party, {name} is usually…',
      options: [
        'The life of the party',
        'Chatting in a corner',
        'Near the food',
        'Ready to leave early',
      ],
    ),
    KnowMeQuestion(
      id: 'time_travel',
      self: 'If I could time travel, I\'d visit…',
      partner: 'If {name} could time travel, they\'d visit…',
      options: [
        'Ancient times',
        'The far future',
        'Childhood days',
        'The day we met',
      ],
    ),
    KnowMeQuestion(
      id: 'cosy_spot',
      self: 'My favourite spot at home is…',
      partner: '{name}\'s favourite spot at home is…',
      options: ['The bed', 'The sofa', 'The kitchen', 'By the window'],
    ),
    KnowMeQuestion(
      id: 'most_used_app',
      self: 'The app I open the most is…',
      partner: 'The app {name} opens the most is…',
      options: ['Chat apps', 'Social media', 'Videos', 'Music or podcasts'],
    ),
    KnowMeQuestion(
      id: 'dessert',
      self: 'My favourite dessert is…',
      partner: '{name}\'s favourite dessert is…',
      options: ['Cake', 'Ice cream', 'A traditional sweet', 'Fresh fruit'],
    ),
    KnowMeQuestion(
      id: 'rainy_day',
      self: 'On a rainy day, I\'d rather…',
      partner: 'On a rainy day, {name} would rather…',
      options: [
        'Curl up with a book',
        'Watch the rain with chai',
        'Take a nap',
        'Dance in it',
      ],
    ),
    KnowMeQuestion(
      id: 'cheer_up',
      self: 'The fastest way to cheer me up is…',
      partner: 'The fastest way to cheer {name} up is…',
      options: [
        'Jokes and silly memes',
        'Good food',
        'A hug or kind words',
        'A chance to vent',
      ],
    ),
    KnowMeQuestion(
      id: 'new_skill',
      self: 'A skill I\'d love to learn is…',
      partner: 'A skill {name} would love to learn is…',
      options: [
        'A new language',
        'An instrument',
        'Dancing',
        'Cooking like a pro',
      ],
    ),
    KnowMeQuestion(
      id: 'first_thing_morning',
      self: 'The first thing I do in the morning is…',
      partner: 'The first thing {name} does in the morning is…',
      options: [
        'Check the phone',
        'Make a hot drink',
        'Hit snooze',
        'Stretch or exercise',
      ],
    ),
    KnowMeQuestion(
      id: 'trip_role',
      self: 'On a long trip, I\'m the one who…',
      partner: 'On a long trip, {name} is the one who…',
      options: [
        'Packs too much',
        'Handles the directions',
        'Finds the best food',
        'Falls asleep first',
      ],
    ),
    KnowMeQuestion(
      id: 'celebrate',
      self: 'My favourite way to celebrate is…',
      partner: '{name}\'s favourite way to celebrate is…',
      options: [
        'A big party',
        'A quiet dinner',
        'A trip away',
        'Something spontaneous',
      ],
    ),
    KnowMeQuestion(
      id: 'spooks',
      self: 'The thing that spooks me most is…',
      partner: 'The thing that spooks {name} most is…',
      options: ['Spiders and bugs', 'Heights', 'The dark', 'Scary movies'],
    ),
    KnowMeQuestion(
      id: 'zombie_movie',
      self: 'In a zombie movie, I\'d be…',
      partner: 'In a zombie movie, {name} would be…',
      options: [
        'The leader',
        'The one with a plan',
        'The first to run',
        'The comic relief',
      ],
    ),
    KnowMeQuestion(
      id: 'ice_cream',
      self: 'My ice cream pick is…',
      partner: '{name}\'s ice cream pick is…',
      options: [
        'Chocolate',
        'Vanilla',
        'Something fruity',
        'The weirdest flavour',
      ],
    ),
    KnowMeQuestion(
      id: 'dream_home',
      self: 'My dream home is…',
      partner: '{name}\'s dream home is…',
      options: [
        'A cosy cottage',
        'A city apartment',
        'A beach house',
        'A farmhouse with land',
      ],
    ),
    KnowMeQuestion(
      id: 'after_disagreement',
      self: 'After a disagreement, I prefer to…',
      partner: 'After a disagreement, {name} prefers to…',
      options: [
        'Talk it out right away',
        'Cool off first',
        'Hug it out',
        'Write it in a message',
      ],
    ),
    KnowMeQuestion(
      id: 'binge_show',
      self: 'The kind of show I binge is…',
      partner: 'The kind of show {name} binges is…',
      options: [
        'Crime and mystery',
        'Comedy',
        'Reality shows',
        'Documentaries',
      ],
    ),
    KnowMeQuestion(
      id: 'fav_compliment',
      self: 'The compliment I love most is about my…',
      partner: 'The compliment {name} loves most is about their…',
      options: ['Looks', 'Kindness', 'Sense of humour', 'Smarts'],
    ),
    KnowMeQuestion(
      id: 'shopping_style',
      self: 'When shopping, I…',
      partner: 'When shopping, {name}…',
      options: [
        'Know exactly what to buy',
        'Browse for hours',
        'Hunt for deals',
        'Avoid it if possible',
      ],
    ),
    KnowMeQuestion(
      id: 'spirit_animal',
      self: 'If I were an animal, I\'d be…',
      partner: 'If {name} were an animal, they\'d be…',
      options: ['A cat', 'A dog', 'An owl', 'A dolphin'],
    ),
    KnowMeQuestion(
      id: 'breakfast',
      self: 'My ideal breakfast is…',
      partner: '{name}\'s ideal breakfast is…',
      options: [
        'Dosa or idli',
        'Eggs and toast',
        'Oats or cereal',
        'Just coffee',
      ],
    ),
    KnowMeQuestion(
      id: 'shower_habit',
      self: 'In the shower, I…',
      partner: 'In the shower, {name}…',
      options: [
        'Sing loudly',
        'Plan the day',
        'Think deep thoughts',
        'Get out fast',
      ],
    ),
    KnowMeQuestion(
      id: 'bucket_list',
      self: 'Near the top of my bucket list is…',
      partner: 'Near the top of {name}\'s bucket list is…',
      options: [
        'Seeing the northern lights',
        'Skydiving',
        'Running a marathon',
        'Learning to surf',
      ],
    ),
    KnowMeQuestion(
      id: 'fav_memories',
      self: 'My favourite memories with you are…',
      partner: '{name}\'s favourite memories with you are…',
      options: [
        'Our trips',
        'Lazy days together',
        'Late-night talks',
        'Our silly inside jokes',
      ],
    ),
  ];

  static final Map<String, KnowMeQuestion> _byId = {
    for (final q in all) q.id: q,
  };

  /// The question with [id], or null if this app version doesn't have it.
  static KnowMeQuestion? byId(String id) => _byId[id];
}
