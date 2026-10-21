/// Which shelf of the couple's media a service, screen or session is for:
/// songs you listen to together, or YouTube videos you watch together.
///
/// Both shelves store the same `Song` fields and the same session shape;
/// only the collection names and the words on screen differ.
enum MediaShelf {
  songs(
    items: 'songs',
    sessions: 'listening',
    item: 'song',
    together: 'Listen together',
    togetherTitle: 'Listening together',
    doing: 'listening',
  ),
  videos(
    items: 'videos',
    sessions: 'watching',
    item: 'video',
    together: 'Watch together',
    togetherTitle: 'Watching together',
    doing: 'watching',
  );

  const MediaShelf({
    required this.items,
    required this.sessions,
    required this.item,
    required this.together,
    required this.togetherTitle,
    required this.doing,
  });

  /// Collection of saved items: `couples/{id}/{items}/{itemId}`.
  final String items;

  /// Collection holding the session (`{sessions}/now`) and the clock
  /// docs (`{sessions}/clock-{uid}`).
  final String sessions;

  /// "song" / "video".
  final String item;

  /// "Listen together" / "Watch together".
  final String together;

  /// "Listening together" / "Watching together".
  final String togetherTitle;

  /// "listening" / "watching".
  final String doing;
}
