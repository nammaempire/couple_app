import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:couple_app/features/music/data/server_clock.dart';
import 'package:couple_app/features/music/data/song_metadata_service.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/models/song_link.dart';

void main() {
  group('SongLink.parse', () {
    test('YouTube in all its shapes', () {
      for (final input in [
        'https://www.youtube.com/watch?v=BddP6PYo2gs',
        'https://youtube.com/watch?v=BddP6PYo2gs&t=42s&si=abc',
        'http://m.youtube.com/watch?v=BddP6PYo2gs',
        'https://youtu.be/BddP6PYo2gs?si=xyz',
        'youtu.be/BddP6PYo2gs',
        'https://www.youtube.com/shorts/BddP6PYo2gs',
        'https://www.youtube.com/embed/BddP6PYo2gs',
        'Our song 😍 https://youtu.be/BddP6PYo2gs.',
      ]) {
        final link = SongLink.parse(input);
        expect(link, isNotNull, reason: input);
        expect(link!.source, SongSource.youtube, reason: input);
        expect(link.kind, SongKind.video, reason: input);
        expect(link.mediaId, 'BddP6PYo2gs', reason: input);
        expect(link.url, 'https://www.youtube.com/watch?v=BddP6PYo2gs');
        expect(link.playsInApp, isTrue);
        expect(link.fallbackThumbnail, contains('BddP6PYo2gs'));
      }
    });

    test('YouTube Music keeps its own app but plays in the YouTube player', () {
      final link = SongLink.parse(
        'https://music.youtube.com/watch?v=BddP6PYo2gs&feature=share',
      )!;
      expect(link.source, SongSource.youtubeMusic);
      expect(link.url, 'https://music.youtube.com/watch?v=BddP6PYo2gs');
      expect(link.playsInApp, isTrue);
    });

    test('YouTube playlists are saved but not played in the app', () {
      final link = SongLink.parse(
        'https://www.youtube.com/playlist?list=PL1234567890',
      )!;
      expect(link.kind, SongKind.playlist);
      expect(link.playsInApp, isFalse);
    });

    test('Spotify links and URIs', () {
      final track = SongLink.parse(
        'https://open.spotify.com/intl-en/track/4cOdK2wGLETKBW3PvgPWqT?si=abc',
      )!;
      expect(track.source, SongSource.spotify);
      expect(track.kind, SongKind.track);
      expect(track.mediaId, '4cOdK2wGLETKBW3PvgPWqT');
      expect(
        track.url,
        'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
      );
      expect(track.playsInApp, isFalse);

      final uri = SongLink.parse('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M')!;
      expect(uri.kind, SongKind.playlist);
      expect(
        uri.url,
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );

      final short = SongLink.parse('https://spotify.link/AbCdEf')!;
      expect(short.source, SongSource.spotify);
      expect(short.kind, SongKind.other);
    });

    test(
      'Apple Music, JioSaavn and SoundCloud guess a title from the link',
      () {
        final apple = SongLink.parse(
          'https://music.apple.com/in/album/tum-hi-ho/1440818839?i=1440818854',
        )!;
        expect(apple.source, SongSource.appleMusic);
        expect(apple.kind, SongKind.track);
        expect(apple.slugTitle, 'Tum Hi Ho');

        final saavn = SongLink.parse(
          'https://www.jiosaavn.com/song/kesariya/OgwhbhtDRwM',
        )!;
        expect(saavn.source, SongSource.jioSaavn);
        expect(saavn.kind, SongKind.track);
        expect(saavn.slugTitle, 'Kesariya');

        final cloud = SongLink.parse(
          'https://soundcloud.com/artist/night-drive',
        )!;
        expect(cloud.source, SongSource.soundCloud);
        expect(cloud.slugTitle, 'Night Drive');
      },
    );

    test('escaped characters in a slug are not decoded twice', () {
      final saavn = SongLink.parse('https://jiosaavn.com/song/100%25-pyaar/x')!;
      expect(saavn.source, SongSource.jioSaavn);
      expect(saavn.slugTitle, '100% Pyaar');
    });

    test('other web links are kept; non-links are rejected', () {
      expect(
        SongLink.parse('https://gaana.com/song/x')!.source,
        SongSource.other,
      );
      expect(SongLink.parse(''), isNull);
      expect(SongLink.parse('just words'), isNull);
      expect(SongLink.parse('ftp://example.com/a.mp3'), isNull);
      expect(SongLink.parse('javascript:alert(1)'), isNull);
    });
  });

  group('SongMetadataService', () {
    final yt = SongLink.parse('https://youtu.be/BddP6PYo2gs')!;

    test('splits "Artist - Title (Official Video)"', () {
      final meta = SongMetadataService.parseOEmbed(yt, {
        'title': 'Arijit Singh - Tum Hi Ho (Official Video) [HD]',
        'author_name': 'T-Series',
        'thumbnail_url': 'https://i.ytimg.com/vi/BddP6PYo2gs/hqdefault.jpg',
      });
      expect(meta.title, 'Tum Hi Ho');
      expect(meta.artist, 'Arijit Singh');
      expect(meta.thumbnailUrl, startsWith('https://'));
    });

    test('drops "- Topic" from auto-generated channels', () {
      final meta = SongMetadataService.parseOEmbed(yt, {
        'title': 'Kesariya',
        'author_name': 'Arijit Singh - Topic',
      });
      expect(meta.title, 'Kesariya');
      expect(meta.artist, 'Arijit Singh');
    });

    test('Spotify gives a title and cover only', () {
      final link = SongLink.parse(
        'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
      )!;
      final meta = SongMetadataService.parseOEmbed(link, {
        'title': 'Perfect',
        'author_name': 'ignored',
        'thumbnail_url': 'https://i.scdn.co/image/abc',
      });
      expect(meta.title, 'Perfect');
      expect(meta.artist, '');
      expect(meta.thumbnailUrl, 'https://i.scdn.co/image/abc');
    });

    test('lookup calls oEmbed and falls back on failure', () async {
      Uri? asked;
      final ok = SongMetadataService(
        client: MockClient((req) async {
          asked = req.url;
          return http.Response(
            jsonEncode({'title': 'A - B', 'author_name': 'C'}),
            200,
          );
        }),
      );
      final meta = await ok.lookup(yt);
      expect(asked!.host, 'www.youtube.com');
      expect(asked!.path, '/oembed');
      expect(meta.artist, 'A');
      expect(meta.title, 'B');

      final failing = SongMetadataService(
        client: MockClient((_) async => http.Response('nope', 404)),
      );
      final fallback = await failing.lookup(yt);
      expect(fallback.title, '');
      expect(fallback.thumbnailUrl, yt.fallbackThumbnail);

      final throwing = SongMetadataService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect((await throwing.lookup(yt)).thumbnailUrl, yt.fallbackThumbnail);
    });

    test(
      'sources without oEmbed use the title in the link, with no request',
      () async {
        var calls = 0;
        final service = SongMetadataService(
          client: MockClient((_) async {
            calls++;
            return http.Response('{}', 200);
          }),
        );
        final apple = SongLink.parse(
          'https://music.apple.com/in/album/tum-hi-ho/1440818839?i=1440818854',
        )!;
        expect((await service.lookup(apple)).title, 'Tum Hi Ho');
        expect(calls, 0);
      },
    );
  });

  group('Song', () {
    test('round-trips and tolerates junk', () {
      final link = SongLink.parse('https://youtu.be/BddP6PYo2gs')!;
      final song = Song.fromLink(link, addedBy: 'a').copyWith(
        title: 'Tum Hi Ho',
        artist: 'Arijit Singh',
        moment: SongMoment.ourSong,
        note: 'First dance',
      );
      final back = Song.fromMap('s1', {
        ...song.toMap(),
        'lovedBy': {'a': true, 'b': false, 'c': 'yes'},
        'playCount': 3.0,
      });
      expect(back.title, 'Tum Hi Ho');
      expect(back.moment, SongMoment.ourSong);
      expect(back.playsInApp, isTrue);
      expect(back.lovedBy, {'a'});
      expect(back.playCount, 3);

      final junk = Song.fromMap('x', {
        'source': 42,
        'moment': 'nope',
        'lovedBy': 'all',
      });
      expect(junk.source, SongSource.other);
      expect(junk.moment, SongMoment.other);
      expect(junk.lovedBy, isEmpty);
      expect(junk.displayTitle, 'Link link');
    });

    test('long titles are clipped without splitting an emoji', () {
      final title = '${'a' * (Song.maxTitle - 1)}😍';
      final map = Song(
        id: '',
        url: 'https://x.y/z',
        source: SongSource.other,
        addedBy: 'a',
        title: title,
      ).toMap();
      expect((map['title'] as String).length, lessThanOrEqualTo(Song.maxTitle));
      expect((map['title'] as String).endsWith('\uD83D'), isFalse);
    });

    test('non-https thumbnails are dropped', () {
      final map = const Song(
        id: '',
        url: 'https://x.y/z',
        source: SongSource.other,
        addedBy: 'a',
        thumbnailUrl: 'http://x/y.jpg',
      ).toMap();
      expect(map['thumbnailUrl'], '');
    });
  });

  group('SongLists', () {
    Song s(
      String id, {
      SongMoment m = SongMoment.other,
      Set<String> loved = const {},
      int day = 1,
      String title = '',
    }) => Song(
      id: id,
      url: 'https://youtu.be/$id',
      source: SongSource.youtube,
      addedBy: 'a',
      moment: m,
      lovedBy: loved,
      title: title,
      createdAt: DateTime(2026, 1, day),
    );

    test('our song first, then loved by both, then newest', () {
      final list = SongLists.filter(
        [
          s('old', day: 1),
          s('new', day: 9),
          s('both', loved: {'a', 'b'}, day: 2),
          s('ours', m: SongMoment.ourSong),
        ],
        myUid: 'a',
        partnerUid: 'b',
      );
      expect(list.map((e) => e.id), ['ours', 'both', 'new', 'old']);
    });

    test('filters by moment, search and both-love', () {
      final all = [
        s('1', m: SongMoment.sad, title: 'Channa Mereya'),
        s('2', loved: {'a', 'b'}, title: 'Perfect'),
      ];
      expect(
        SongLists.filter(
          all,
          moment: SongMoment.sad,
          myUid: 'a',
        ).map((e) => e.id),
        ['1'],
      );
      expect(
        SongLists.filter(all, query: 'perf', myUid: 'a').map((e) => e.id),
        ['2'],
      );
      expect(
        SongLists.filter(
          all,
          bothLoveOnly: true,
          myUid: 'a',
          partnerUid: 'b',
        ).map((e) => e.id),
        ['2'],
      );
      expect(SongLists.momentsUsed(all), [SongMoment.sad, SongMoment.other]);
    });

    test('queueAfter wraps around and skips the current song', () {
      final list = [s('a'), s('b'), s('c')];
      expect(SongLists.queueAfter(list, 'b'), ['c', 'a']);
      expect(SongLists.queueAfter(list, 'zz'), isEmpty);
      expect(SongLists.queueAfter(list, 'a', max: 1), ['b']);
    });

    test('duplicateOf matches the same video however it was linked', () {
      final list = [s('BddP6PYo2gs').copyWith()];
      final saved = Song.fromLink(
        SongLink.parse('https://youtu.be/BddP6PYo2gs')!,
        addedBy: 'a',
      );
      final again = SongLink.parse(
        'https://www.youtube.com/watch?v=BddP6PYo2gs&t=3',
      )!;
      expect(SongLists.duplicateOf([saved], again), isNotNull);
      expect(
        SongLists.duplicateOf(
          list,
          SongLink.parse('https://youtu.be/AAAAAAAAAAA')!,
        ),
        isNull,
      );
    });
  });

  group('ListeningSession', () {
    const song = Song(
      id: 's1',
      url: 'https://www.youtube.com/watch?v=BddP6PYo2gs',
      source: SongSource.youtube,
      kind: SongKind.video,
      mediaId: 'BddP6PYo2gs',
      title: 'Tum Hi Ho',
      addedBy: 'a',
    );

    test('a new session counts down, then plays from 0', () {
      final s = ListeningSession.start(
        song: song,
        uid: 'a',
        nowMs: 10000,
        queue: ['s2'],
        previousVersion: 4,
      );
      expect(s.status, ListeningStatus.countdown);
      expect(s.at, 10000 + ListeningSession.countdownMs);
      expect(s.version, 5);
      expect(s.countdownLeftMs(11000), 3000);
      expect(s.countdownDone(13999), isFalse);
      expect(s.countdownDone(14000), isTrue);
      expect(s.expectedPositionMs(12000), -2000);
      expect(s.expectedPositionMs(16500), 2500);
      expect(s.isListening('a', 12000), isTrue);
      expect(s.playsInApp, isTrue);
    });

    test('pausing keeps the position; resuming carries on from it', () {
      final playing = ListeningSession.start(song: song, uid: 'a', nowMs: 0)
          .withStatus(
            ListeningStatus.playing,
            uid: 'a',
            nowMs: 4000,
            positionMs: 0,
          );
      final paused = playing.withStatus(
        ListeningStatus.paused,
        uid: 'b',
        nowMs: 34000,
      );
      expect(paused.positionMs, 30000);
      expect(paused.expectedPositionMs(99999), 30000);
      final resumed = paused.withStatus(
        ListeningStatus.playing,
        uid: 'a',
        nowMs: 50000,
      );
      expect(resumed.expectedPositionMs(51000), 31000);
      expect(resumed.updatedBy, 'a');
      expect(resumed.version, paused.version + 1);
    });

    test('listeners time out; check-ins do not bump the version', () {
      final s = ListeningSession.start(
        song: song,
        uid: 'a',
        nowMs: 0,
      ).withListener('b', 1000);
      expect(s.version, 1);
      expect(
        s.isListening('b', 1000 + ListeningSession.listenerTimeoutMs - 1),
        isTrue,
      );
      expect(
        s.isListening('b', 1000 + ListeningSession.listenerTimeoutMs),
        isFalse,
      );
    });

    test(
      'a forgotten session goes stale; a recent or attended one does not',
      () {
        const tenMin = ListeningSession.staleAfterMs;
        const timeout = ListeningSession.listenerTimeoutMs;
        final s = ListeningSession.start(song: song, uid: 'a', nowMs: 0);
        final at = s.at;
        // Recent: never stale, even with nobody listening.
        expect(s.isStale(at + tenMin), isFalse);
        expect(s.isActive(at + tenMin), isTrue);
        // Old, and the only check-in timed out long ago.
        expect(s.isStale(at + tenMin + 1), isTrue);
        expect(s.isActive(at + tenMin + 1), isFalse);
        // Old, but someone checked in recently.
        final attended = s.withListener('b', at + tenMin);
        expect(attended.isStale(at + tenMin + timeout - 1), isFalse);
        expect(attended.isStale(at + tenMin + timeout), isTrue);
        // An ended session is never active.
        final ended = s.withStatus(ListeningStatus.ended, uid: 'a', nowMs: at);
        expect(ended.isActive(at), isFalse);
      },
    );

    test('round-trips through a map and tolerates junk', () {
      final s = ListeningSession.start(
        song: song,
        uid: 'a',
        nowMs: 5,
        queue: ['x', 'y'],
      );
      final back = ListeningSession.fromMap(s.toMap());
      expect(back.toMap(), s.toMap());
      final junk = ListeningSession.fromMap({
        'status': 'weird',
        'positionMs': 'x',
        'queue': [1, 'a'],
        'listeners': {'a': 'x', 'b': 3},
      });
      expect(junk.status, ListeningStatus.ended);
      expect(junk.isLive, isFalse);
      expect(junk.queue, ['a']);
      expect(junk.listeners, {'b': 3});
    });

    test('only noticeable drift triggers a seek', () {
      expect(ListeningSession.needsSeek(10000, 10800), isFalse);
      expect(ListeningSession.needsSeek(10000, 12000), isTrue);
    });
  });

  group('ServerClock', () {
    test('keeps the measurement with the shortest round trip', () {
      var local = 1000;
      final clock = ServerClock(localNowMs: () => local);
      expect(clock.nowMs(), 1000);
      expect(clock.isCalibrated, isFalse);

      clock.observe(sentMs: 0, receivedMs: 800, serverMs: 5400); // ±400
      expect(clock.offsetMs, 5000);
      clock.observe(sentMs: 0, receivedMs: 100, serverMs: 5100); // ±50
      expect(clock.offsetMs, 5050);
      clock.observe(
        sentMs: 0,
        receivedMs: 600,
        serverMs: 9999,
      ); // worse: ignored
      expect(clock.offsetMs, 5050);
      local = 2000;
      expect(clock.nowMs(), 7050);
      expect(clock.isCalibrated, isTrue);
    });
  });
}
