import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/music/models/song_link.dart';

/// What a song (or video) means to you two. Used to group and filter the
/// library. Songs offer [forSongs], videos [forVideos]; both are stored the
/// same way, by [id].
enum SongMoment {
  ourSong('ourSong', 'Our song', '💞'),
  romantic('romantic', 'Romantic', '🌹'),
  missYou('missYou', 'Missing you', '🥺'),
  happy('happy', 'Happy', '😄'),
  sad('sad', 'Sad', '🌧️'),
  roadTrip('roadTrip', 'Road trip', '🚗'),
  dance('dance', 'Dance', '💃'),
  chill('chill', 'Chill', '🌙'),
  // Videos.
  movieNight('movieNight', 'Movie night', '🍿'),
  funny('funny', 'Funny', '😂'),
  food('food', 'Food', '🍜'),
  travel('travel', 'Travel', '✈️'),
  music('music', 'Music', '🎶'),
  learn('learn', 'Learn', '📚'),
  other('other', 'Other', '🎵');

  const SongMoment(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;

  static SongMoment fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return SongMoment.other;
  }

  /// The moments the song editor offers.
  static const forSongs = [
    ourSong,
    romantic,
    missYou,
    happy,
    sad,
    roadTrip,
    dance,
    chill,
    other,
  ];

  /// The moments the video editor offers.
  static const forVideos = [
    movieNight,
    funny,
    romantic,
    food,
    travel,
    music,
    learn,
    other,
  ];
}

/// A song in the couple's library, saved as a link.
/// Stored at `couples/{coupleId}/songs/{songId}`.
class Song {
  static const maxTitle = 200;
  static const maxArtist = 200;
  static const maxNote = 500;
  static const maxThumbnail = 2000;

  final String id;
  final String url;
  final SongSource source;
  final SongKind kind;

  /// YouTube video id or Spotify id, or ''.
  final String mediaId;

  final String title;
  final String artist;

  /// Cover art or video thumbnail, or ''.
  final String thumbnailUrl;

  /// Why it's yours ("Played at our first dance").
  final String note;
  final SongMoment moment;

  /// Who loves it: uids.
  final Set<String> lovedBy;

  final String addedBy;
  final int playCount;
  final DateTime? createdAt;
  final DateTime? lastPlayedAt;

  const Song({
    required this.id,
    required this.url,
    required this.source,
    required this.addedBy,
    this.kind = SongKind.other,
    this.mediaId = '',
    this.title = '',
    this.artist = '',
    this.thumbnailUrl = '',
    this.note = '',
    this.moment = SongMoment.other,
    this.lovedBy = const {},
    this.playCount = 0,
    this.createdAt,
    this.lastPlayedAt,
  });

  /// A new, unsaved song from a parsed link.
  factory Song.fromLink(SongLink link, {required String addedBy}) => Song(
    id: '',
    url: link.url,
    source: link.source,
    kind: link.kind,
    mediaId: link.mediaId,
    title: link.slugTitle,
    thumbnailUrl: link.fallbackThumbnail,
    addedBy: addedBy,
  );

  /// Whether the app plays it itself, in sync on both phones.
  bool get playsInApp =>
      source.playsInApp && kind == SongKind.video && mediaId.isNotEmpty;

  /// The title to show: the saved one, or the source's name.
  String get displayTitle =>
      title.trim().isNotEmpty ? title.trim() : '${source.label} link';

  bool isLovedBy(String uid) => lovedBy.contains(uid);

  /// True when both of you love it.
  bool lovedByBoth(String a, String? b) =>
      b != null && lovedBy.contains(a) && lovedBy.contains(b);

  factory Song.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Song.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  /// Builds a song from stored fields, tolerating missing or malformed ones.
  static Song fromMap(String id, Map<String, dynamic> data) {
    final loved = data['lovedBy'];
    return Song(
      id: id,
      url: _string(data['url']) ?? '',
      source: SongSource.fromId(_string(data['source'])),
      kind: SongKind.fromId(_string(data['kind'])),
      mediaId: _string(data['mediaId']) ?? '',
      title: _string(data['title']) ?? '',
      artist: _string(data['artist']) ?? '',
      thumbnailUrl: _string(data['thumbnailUrl']) ?? '',
      note: _string(data['note']) ?? '',
      moment: SongMoment.fromId(_string(data['moment'])),
      lovedBy: loved is Map
          ? {
              for (final e in loved.entries)
                if (e.key is String && e.value == true) e.key as String,
            }
          : const {},
      addedBy: _string(data['addedBy']) ?? '',
      playCount: data['playCount'] is num
          ? (data['playCount'] as num).toInt().clamp(0, 1 << 30)
          : 0,
      createdAt: _date(data['createdAt']),
      lastPlayedAt: _date(data['lastPlayedAt']),
    );
  }

  /// Fields the editor saves. `lovedBy`, `playCount` and the timestamps are
  /// written by their own service calls.
  Map<String, dynamic> toMap() => {
    'url': url.trim(),
    'source': source.id,
    'kind': kind.id,
    'mediaId': mediaId,
    'title': _clip(title.trim(), maxTitle),
    'artist': _clip(artist.trim(), maxArtist),
    'thumbnailUrl':
        thumbnailUrl.length <= maxThumbnail &&
            thumbnailUrl.startsWith('https://')
        ? thumbnailUrl
        : '',
    'note': _clip(note.trim(), maxNote),
    'moment': moment.id,
    'addedBy': addedBy,
  };

  Song copyWith({
    String? title,
    String? artist,
    String? thumbnailUrl,
    String? note,
    SongMoment? moment,
    Set<String>? lovedBy,
  }) {
    return Song(
      id: id,
      url: url,
      source: source,
      kind: kind,
      mediaId: mediaId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      note: note ?? this.note,
      moment: moment ?? this.moment,
      lovedBy: lovedBy ?? this.lovedBy,
      addedBy: addedBy,
      playCount: playCount,
      createdAt: createdAt,
      lastPlayedAt: lastPlayedAt,
    );
  }
}

/// Pure filtering and sorting for the library.
class SongLists {
  const SongLists._();

  /// Songs matching [moment] (all when null), [query] (title, artist or
  /// note), and optionally only ones you both love.
  ///
  /// Order: "Our song" first, then songs you both love, then newest.
  static List<Song> filter(
    Iterable<Song> all, {
    SongMoment? moment,
    String query = '',
    bool bothLoveOnly = false,
    required String myUid,
    String? partnerUid,
  }) {
    final q = query.trim().toLowerCase();
    final list =
        all.where((s) {
          if (moment != null && s.moment != moment) return false;
          if (bothLoveOnly && !s.lovedByBoth(myUid, partnerUid)) return false;
          if (q.isEmpty) return true;
          return s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q) ||
              s.note.toLowerCase().contains(q);
        }).toList()..sort((a, b) {
          final aOurs = a.moment == SongMoment.ourSong;
          final bOurs = b.moment == SongMoment.ourSong;
          if (aOurs != bOurs) return aOurs ? -1 : 1;
          final aBoth = a.lovedByBoth(myUid, partnerUid);
          final bBoth = b.lovedByBoth(myUid, partnerUid);
          if (aBoth != bBoth) return aBoth ? -1 : 1;
          return _newestFirst(a.createdAt, b.createdAt);
        });
    return list;
  }

  /// Moments in use, in enum order, for the filter chips.
  static List<SongMoment> momentsUsed(Iterable<Song> all) {
    final used = all.map((s) => s.moment).toSet();
    return SongMoment.values.where(used.contains).toList();
  }

  /// The songs to play after [current], in list order, wrapping around:
  /// what "Listen together" queues up. At most [max] ids.
  static List<String> queueAfter(
    List<Song> list,
    String currentId, {
    int max = 50,
  }) {
    final i = list.indexWhere((s) => s.id == currentId);
    if (i < 0) return const [];
    return [
      for (var k = 1; k < list.length && k <= max; k++)
        list[(i + k) % list.length].id,
    ];
  }

  /// Finds an existing song with the same link, so it isn't added twice.
  static Song? duplicateOf(Iterable<Song> all, SongLink link) {
    for (final s in all) {
      if (link.mediaId.isNotEmpty &&
          s.mediaId == link.mediaId &&
          s.source == link.source) {
        return s;
      }
      if (s.url == link.url) return s;
    }
    return null;
  }

  // Unsaved (null) values count as newest.
  static int _newestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return b.compareTo(a);
  }
}

String? _string(Object? v) => v is String ? v : null;

DateTime? _date(Object? v) => switch (v) {
  final Timestamp t => t.toDate(),
  final DateTime d => d,
  _ => null,
};

/// Cuts [s] to at most [max] UTF-16 units without splitting an emoji's
/// surrogate pair (the rules count characters, which is never more).
String _clip(String s, int max) {
  if (s.length <= max) return s;
  var end = max;
  final last = s.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;
  return s.substring(0, end).trimRight();
}
