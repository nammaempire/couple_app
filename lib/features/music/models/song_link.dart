/// Where a song link points.
enum SongSource {
  spotify('spotify', 'Spotify'),
  youtube('youtube', 'YouTube'),
  youtubeMusic('youtubeMusic', 'YouTube Music'),
  appleMusic('appleMusic', 'Apple Music'),
  jioSaavn('jioSaavn', 'JioSaavn'),
  soundCloud('soundCloud', 'SoundCloud'),
  other('other', 'Link');

  const SongSource(this.id, this.label);
  final String id;
  final String label;

  static SongSource fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return SongSource.other;
  }

  /// Whether the app can play this source itself (through the YouTube
  /// player), so both phones can be kept in sync to the second.
  bool get playsInApp => this == youtube || this == youtubeMusic;
}

/// What the link is: a single song, or a collection.
enum SongKind {
  track('track'),
  video('video'),
  album('album'),
  playlist('playlist'),
  other('other');

  const SongKind(this.id);
  final String id;

  static SongKind fromId(String? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return SongKind.other;
  }
}

/// A song link, understood: its source, what it is, and the id that
/// source uses for it.
class SongLink {
  const SongLink({
    required this.url,
    required this.source,
    required this.kind,
    this.mediaId = '',
    this.slugTitle = '',
  });

  /// The link to store and open: always https, tracking parameters removed
  /// where that is safe.
  final String url;
  final SongSource source;
  final SongKind kind;

  /// YouTube video id, or Spotify id; '' when unknown.
  final String mediaId;

  /// A best-guess title from the link itself ("Tum Hi Ho" from
  /// `.../song/tum-hi-ho/...`), for sources without a lookup; '' if none.
  final String slugTitle;

  /// Whether the app can play it itself, in sync on both phones.
  bool get playsInApp =>
      source.playsInApp && kind == SongKind.video && mediaId.isNotEmpty;

  /// A thumbnail that works without a lookup (YouTube only), or ''.
  String get fallbackThumbnail =>
      playsInApp ? 'https://i.ytimg.com/vi/$mediaId/hqdefault.jpg' : '';

  static const maxUrl = 2000;

  static final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _spotifyId = RegExp(r'^[A-Za-z0-9]{10,40}$');
  static final _spotifyUri = RegExp(
    r'^spotify:(track|album|playlist|episode|artist):([A-Za-z0-9]+)$',
  );

  /// Understands a pasted link, or returns null if it isn't a web link.
  ///
  /// Accepts text around the link ("Listen to this 😍 https://…") because
  /// that is what share sheets paste.
  static SongLink? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final uriMatch = _spotifyUri.firstMatch(text);
    if (uriMatch != null) {
      final type = uriMatch.group(1)!;
      final id = uriMatch.group(2)!;
      return SongLink(
        url: 'https://open.spotify.com/$type/$id',
        source: SongSource.spotify,
        kind: _spotifyKind(type),
        mediaId: id,
      );
    }

    final raw = _firstUrl(text);
    if (raw == null) return null;
    var uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme == 'http') uri = uri.replace(scheme: 'https');
    if (uri.scheme != 'https') return null;
    if (uri.toString().length > maxUrl) return null;

    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // YouTube Music (checked before YouTube: same ids, different app).
    if (host == 'music.youtube.com') {
      final id = uri.queryParameters['v'] ?? '';
      if (_youtubeId.hasMatch(id)) {
        return SongLink(
          url: 'https://music.youtube.com/watch?v=$id',
          source: SongSource.youtubeMusic,
          kind: SongKind.video,
          mediaId: id,
        );
      }
      final list = uri.queryParameters['list'];
      return SongLink(
        url: uri.toString(),
        source: SongSource.youtubeMusic,
        kind: list != null ? SongKind.playlist : SongKind.other,
      );
    }

    // YouTube, in all its shapes.
    if (host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host == 'youtu.be' ||
        host == 'youtube-nocookie.com') {
      String? id;
      if (host == 'youtu.be') {
        id = segments.isEmpty ? null : segments.first;
      } else if (segments.isNotEmpty &&
          const {'shorts', 'embed', 'live', 'v'}.contains(segments.first) &&
          segments.length > 1) {
        id = segments[1];
      } else {
        id = uri.queryParameters['v'];
      }
      if (id != null && _youtubeId.hasMatch(id)) {
        return SongLink(
          url: 'https://www.youtube.com/watch?v=$id',
          source: SongSource.youtube,
          kind: SongKind.video,
          mediaId: id,
        );
      }
      final list = uri.queryParameters['list'];
      return SongLink(
        url: uri.toString(),
        source: SongSource.youtube,
        kind: list != null ? SongKind.playlist : SongKind.other,
      );
    }

    // Spotify: open.spotify.com/(intl-xx/)?track/<id>
    if (host == 'open.spotify.com') {
      final parts = segments.isNotEmpty && segments.first.startsWith('intl-')
          ? segments.sublist(1)
          : segments;
      if (parts.length >= 2 && _spotifyId.hasMatch(parts[1])) {
        return SongLink(
          url: 'https://open.spotify.com/${parts[0]}/${parts[1]}',
          source: SongSource.spotify,
          kind: _spotifyKind(parts[0]),
          mediaId: parts[1],
        );
      }
      return SongLink(
        url: uri.toString(),
        source: SongSource.spotify,
        kind: SongKind.other,
      );
    }
    if (host == 'spotify.link' || host == 'spotify.app.link') {
      return SongLink(
        url: uri.toString(),
        source: SongSource.spotify,
        kind: SongKind.other,
      );
    }

    // Apple Music: music.apple.com/in/album/<slug>/<id>?i=<trackId>
    if (host == 'music.apple.com' || host == 'itunes.apple.com') {
      final isTrack =
          uri.queryParameters.containsKey('i') ||
          (segments.length > 1 && segments[1] == 'song');
      final type = segments.length > 1 ? segments[1] : '';
      return SongLink(
        url: uri.toString(),
        source: SongSource.appleMusic,
        kind: isTrack
            ? SongKind.track
            : type == 'album'
            ? SongKind.album
            : type == 'playlist'
            ? SongKind.playlist
            : SongKind.other,
        slugTitle: segments.length > 2 ? _titleFromSlug(segments[2]) : '',
      );
    }

    // JioSaavn: jiosaavn.com/song/<slug>/<id>
    if (host == 'jiosaavn.com' || host.endsWith('.jiosaavn.com')) {
      final type = segments.isEmpty ? '' : segments.first;
      return SongLink(
        url: uri.toString(),
        source: SongSource.jioSaavn,
        kind: switch (type) {
          'song' => SongKind.track,
          'album' => SongKind.album,
          'featured' || 's' => SongKind.playlist,
          _ => SongKind.other,
        },
        slugTitle: segments.length > 1 ? _titleFromSlug(segments[1]) : '',
      );
    }

    // SoundCloud: soundcloud.com/<artist>/<track>
    if (host == 'soundcloud.com' ||
        host == 'm.soundcloud.com' ||
        host == 'on.soundcloud.com') {
      return SongLink(
        url: uri.toString(),
        source: SongSource.soundCloud,
        kind: segments.length >= 2 && segments[1] != 'sets'
            ? SongKind.track
            : segments.length >= 3
            ? SongKind.playlist
            : SongKind.other,
        slugTitle: segments.length >= 2 && segments[1] != 'sets'
            ? _titleFromSlug(segments[1])
            : '',
      );
    }

    return SongLink(
      url: uri.toString(),
      source: SongSource.other,
      kind: SongKind.other,
    );
  }

  static SongKind _spotifyKind(String type) => switch (type) {
    'track' || 'episode' => SongKind.track,
    'album' => SongKind.album,
    'playlist' => SongKind.playlist,
    _ => SongKind.other,
  };

  static String? _firstUrl(String text) {
    final match = RegExp(r'https?://[^\s<>"]+').firstMatch(text);
    if (match != null) {
      // Trailing punctuation from a sentence isn't part of the link.
      return match.group(0)!.replaceFirst(RegExp(r'[).,!?\]]+$'), '');
    }
    // A bare "youtu.be/…" or "open.spotify.com/…" without a scheme.
    final bare = RegExp(
      r'^(?:www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}/\S*$',
      caseSensitive: false,
    );
    return bare.hasMatch(text) ? 'https://$text' : null;
  }

  /// "tum-hi-ho" → "Tum Hi Ho". Ids and empty slugs give ''.
  static String _titleFromSlug(String slug) {
    // Path segments are already decoded ("100%25" arrives as "100%").
    final decoded = slug.replaceAll(RegExp(r'[-_]+'), ' ');
    final words = decoded.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '';
    // A slug that is only an id ("1440818839") isn't a title.
    if (words.length == 1 &&
        RegExp(r'^[A-Za-z0-9]{8,}$').hasMatch(words[0]) &&
        RegExp(r'\d').hasMatch(words[0])) {
      return '';
    }
    return words
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
