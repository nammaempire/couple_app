import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:couple_app/features/music/models/song_link.dart';

/// What a lookup found about a link. Empty strings for anything unknown.
class SongMetadata {
  const SongMetadata({
    this.title = '',
    this.artist = '',
    this.thumbnailUrl = '',
  });

  final String title;
  final String artist;
  final String thumbnailUrl;

  bool get isEmpty => title.isEmpty && artist.isEmpty && thumbnailUrl.isEmpty;

  static const empty = SongMetadata();
}

/// Fills in a song's title, artist and cover from its link, using the
/// public oEmbed endpoints of YouTube, Spotify and SoundCloud (no API keys).
/// Other sources fall back to what the link itself says.
///
/// Never throws: a failed or slow lookup just returns less, and the person
/// can type the details themselves.
class SongMetadataService {
  SongMetadataService({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// The oEmbed request for [link], or null if its source has none.
  static Uri? oEmbedUri(SongLink link) {
    switch (link.source) {
      case SongSource.youtube:
      case SongSource.youtubeMusic:
        // YouTube's endpoint doesn't know music.youtube.com links.
        final url = link.mediaId.isNotEmpty
            ? 'https://www.youtube.com/watch?v=${link.mediaId}'
            : link.url.replaceFirst('music.youtube.com', 'www.youtube.com');
        return Uri.https('www.youtube.com', '/oembed', {
          'format': 'json',
          'url': url,
        });
      case SongSource.spotify:
        return Uri.https('open.spotify.com', '/oembed', {'url': link.url});
      case SongSource.soundCloud:
        return Uri.https('soundcloud.com', '/oembed', {
          'format': 'json',
          'url': link.url,
        });
      case SongSource.appleMusic:
      case SongSource.jioSaavn:
      case SongSource.other:
        return null;
    }
  }

  /// Looks [link] up. Falls back to the title in the link and YouTube's
  /// standard thumbnail. With [asSong] false (videos to watch), YouTube
  /// titles are kept whole and the channel is the "artist".
  Future<SongMetadata> lookup(SongLink link, {bool asSong = true}) async {
    final fallback = SongMetadata(
      title: link.slugTitle,
      thumbnailUrl: link.fallbackThumbnail,
    );
    final uri = oEmbedUri(link);
    if (uri == null) return fallback;
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) return fallback;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) return fallback;
      return parseOEmbed(link, body, fallback: fallback, asSong: asSong);
    } on Object {
      // Offline, timed out, blocked or malformed: use what we have.
      return fallback;
    }
  }

  /// Reads an oEmbed response. YouTube titles often carry the artist
  /// ("Arijit Singh - Tum Hi Ho (Official Video)"); that is split out and
  /// the "(Official Video)"-style noise dropped. Spotify gives no artist.
  static SongMetadata parseOEmbed(
    SongLink link,
    Map<String, dynamic> body, {
    SongMetadata fallback = SongMetadata.empty,
    bool asSong = true,
  }) {
    var title = _str(body['title']);
    var artist = _str(body['author_name']);
    final thumb = _str(body['thumbnail_url']);

    if (!asSong) {
      // A video: its own title, by its channel.
    } else if (link.source == SongSource.youtube ||
        link.source == SongSource.youtubeMusic) {
      title = _cleanYoutubeTitle(title);
      final dash = RegExp(r'\s+[-–—|]\s+').firstMatch(title);
      if (dash != null) {
        final left = title.substring(0, dash.start).trim();
        final right = title.substring(dash.end).trim();
        if (left.isNotEmpty && right.isNotEmpty) {
          artist = left;
          title = right;
        }
      } else {
        // Channel names like "T-Series" or "Arijit Singh - Topic".
        artist = artist.replaceFirst(RegExp(r'\s*-\s*Topic$'), '');
        if (artist.toLowerCase().endsWith('vevo')) {
          artist = artist.substring(0, artist.length - 4).trim();
        }
      }
    } else if (link.source == SongSource.spotify) {
      artist = '';
    }

    return SongMetadata(
      title: title.isNotEmpty ? title : fallback.title,
      artist: artist,
      thumbnailUrl: thumb.startsWith('https://')
          ? thumb
          : fallback.thumbnailUrl,
    );
  }

  static final _noise = RegExp(
    r'\s*[\(\[](official|full|lyric|lyrics|audio|video|hd|4k|music video|'
    r'official (music |lyric(al)? )?video|official audio|lyrical( video)?|'
    r'video song|full (video )?song|visualizer)[^\)\]]*[\)\]]',
    caseSensitive: false,
  );

  static String _cleanYoutubeTitle(String title) =>
      title.replaceAll(_noise, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  static String _str(Object? v) => v is String ? v.trim() : '';

  void close() => _client.close();
}
