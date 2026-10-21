import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/data/playback_sync.dart';
import 'package:couple_app/features/music/data/song_metadata_service.dart';
import 'package:couple_app/features/music/data/song_player.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/models/song_link.dart';
import 'package:couple_app/features/music/providers/music_providers.dart';
import 'package:couple_app/features/music/screens/listen_together_screen.dart';
import 'package:couple_app/features/music/screens/music_screen.dart';
import 'package:couple_app/features/music/screens/song_editor_screen.dart';
import 'package:couple_app/features/music/widgets/listening_banner.dart';
import 'package:couple_app/features/together/screens/together_screen.dart';

import 'music_fakes.dart';

const me = AppUser(uid: 'u1', displayName: 'Asha', coupleId: 'c1');
const partner = AppUser(uid: 'u2', displayName: 'Ravi', coupleId: 'c1');
const couple = Couple(id: 'c1', inviteCode: 'X', memberIds: ['u1', 'u2']);

const t0 = 1000000;

void main() {
  late FakeMusicService service;
  late FakeSongPlayer player;
  late List<String> launched;
  late List<Uri> lookups;
  late Map<String, Object?> oEmbed;

  setUp(() {
    service = FakeMusicService(nowMs: t0);
    player = FakeSongPlayer();
    launched = [];
    lookups = [];
    oEmbed = {'title': 'Kesariya', 'thumbnail_url': ''};
  });

  /// A tall phone, so the player and its controls fit without scrolling.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => ProviderScope(
    overrides: [
      musicServiceProvider.overrideWithValue(service),
      songPlayerFactoryProvider.overrideWithValue(() => player),
      songLinkLauncherProvider.overrideWithValue((url) async {
        launched.add(url);
        return true;
      }),
      songMetadataServiceProvider.overrideWithValue(
        SongMetadataService(
          client: MockClient((request) async {
            lookups.add(request.url);
            return http.Response(jsonEncode(oEmbed), 200);
          }),
        ),
      ),
      currentUserProvider.overrideWithBuild((ref, notifier) => me),
      coupleProvider.overrideWith((ref) => Stream.value(couple)),
      partnerProvider.overrideWith((ref) => Stream.value(partner)),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );

  /// A home screen with a button that pushes [screen], so it can pop.
  Widget host(Widget screen) => Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('open'),
        ),
      ),
    ),
  );

  final ours = testSong(
    'a',
    title: 'Tum Hi Ho',
    artist: 'Arijit Singh',
    source: SongSource.youtube,
    mediaId: 'Umqb9KENgmk',
    moment: SongMoment.ourSong,
    lovedBy: {'u1', 'u2'},
    note: 'Our first dance',
  );
  final happy = testSong(
    'b',
    title: 'Kesariya',
    artist: 'Pritam',
    moment: SongMoment.happy,
    lovedBy: {'u2'},
    addedBy: 'u2',
    playCount: 2,
    createdAt: DateTime(2026, 10, 2),
  );
  final chill = testSong(
    'c',
    title: 'Ilahi',
    source: SongSource.jioSaavn,
    moment: SongMoment.chill,
    createdAt: DateTime(2026, 10, 1),
  );

  group('MusicScreen', () {
    testWidgets('empty library invites the first song', (tester) async {
      phone(tester);
      await tester.pumpWidget(app(const MusicScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Your songs, together'), findsOneWidget);
      expect(find.textContaining('Spotify, YouTube'), findsOneWidget);
      await tester.tap(find.text('Add your first song'));
      await tester.pumpAndSettle();
      expect(find.text('Add a song'), findsOneWidget);
    });

    testWidgets('lives in the Together tab as Music', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        app(const TogetherScreen(initialTab: TogetherScreenState.musicTab)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('Your songs, together'), findsOneWidget);
    });

    testWidgets('filters, search and hearts', (tester) async {
      phone(tester);
      service = FakeMusicService(songs: [chill, happy, ours], nowMs: t0);
      await tester.pumpWidget(app(const MusicScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Tum Hi Ho'), findsOneWidget);
      expect(find.text('Kesariya'), findsOneWidget);
      expect(find.text('Ilahi'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('JioSaavn'), findsOneWidget);

      await tester.ensureVisible(find.text('😄 Happy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('😄 Happy'));
      await tester.pumpAndSettle();
      expect(find.text('Kesariya'), findsOneWidget);
      expect(find.text('Tum Hi Ho'), findsNothing);

      await tester.ensureVisible(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loved by both 💞'));
      await tester.pumpAndSettle();
      expect(find.text('Tum Hi Ho'), findsOneWidget);
      expect(find.text('Kesariya'), findsNothing);
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'pritam');
      await tester.pumpAndSettle();
      expect(find.text('Kesariya'), findsOneWidget);
      expect(find.text('Ilahi'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches'), findsOneWidget);
      await tester.tap(find.text('Show all songs'));
      await tester.pumpAndSettle();
      expect(find.text('Ilahi'), findsOneWidget);

      // Kesariya is loved by Ravi only: my heart is empty.
      final kesariya = find.ancestor(
        of: find.text('Kesariya'),
        matching: find.byType(InkWell),
      );
      await tester.tap(
        find.descendant(
          of: kesariya.first,
          matching: find.byTooltip('Love it'),
        ),
      );
      await tester.tap(find.byTooltip('Remove your love'));
      await tester.pumpAndSettle();
      expect(service.calls, ['loved b true', 'loved a false']);
    });

    testWidgets('details sheet: open, listen together, delete', (tester) async {
      phone(tester);
      service = FakeMusicService(songs: [chill, happy, ours], nowMs: t0);
      await tester.pumpWidget(app(const MusicScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kesariya'));
      await tester.pumpAndSettle();
      expect(find.text('Added by Ravi · played 2 times'), findsOneWidget);
      await tester.tap(find.text('Open in Spotify'));
      await tester.pumpAndSettle();
      expect(launched, [happy.url]);

      await tester.tap(find.text('Ilahi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this song?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(service.calls, ['delete c']);

      await tester.tap(find.text('Tum Hi Ho'));
      await tester.pumpAndSettle();
      expect(find.text('“Our first dance”'), findsOneWidget);
      await tester.tap(find.text('Listen together'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Queue: the rest of the shown list after it, wrapping around.
      expect(service.calls, contains('start a b,c'));
      expect(find.byType(ListenTogetherScreen), findsOneWidget);
      expect(find.text('Starting together in'), findsOneWidget);
    });

    testWidgets('switching songs asks first', (tester) async {
      phone(tester);
      service = FakeMusicService(
        songs: [happy, ours],
        nowMs: t0,
        session: testSession(ours, at: t0 - 5000),
      );
      await tester.pumpWidget(app(const MusicScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Listening together'), findsOneWidget);
      expect(find.text('Playing now'), findsOneWidget);

      final kesariya = find.ancestor(
        of: find.text('Kesariya'),
        matching: find.byType(InkWell),
      );
      await tester.tap(
        find.descendant(
          of: kesariya.first,
          matching: find.byTooltip('Listen together'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Switch to Kesariya for both of you?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
    });

    testWidgets('a double tap starts listening once', (tester) async {
      phone(tester);
      service = FakeMusicService(songs: [happy], nowMs: t0);
      await tester.pumpWidget(app(const MusicScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Listen together'));
      await tester.tap(find.byTooltip('Listen together'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.calls.where((c) => c.startsWith('start')), hasLength(1));
      expect(
        find.byType(ListenTogetherScreen, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a session that ended meanwhile explains itself', (
      tester,
    ) async {
      phone(tester);
      service = FakeMusicService(songs: [happy], nowMs: t0)
        ..sessionError = const ListeningException(
          'Listening together has ended.',
        );
      await tester.pumpWidget(app(const MusicScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Listen together'));
      await tester.pumpAndSettle();
      expect(find.text('Listening together has ended.'), findsOneWidget);
      expect(find.byType(ListenTogetherScreen), findsNothing);
    });
  });

  group('SongEditorScreen', () {
    void mockClipboard(WidgetTester tester, String text) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': text} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    testWidgets('paste a link, details fill in, save', (tester) async {
      phone(tester);
      mockClipboard(
        tester,
        'Listen 😍 https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh?si=x',
      );
      await tester.pumpWidget(app(host(const SongEditorScreen())));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paste'));
      await tester.pump();
      expect(
        find.text('Opens in Spotify on both phones at the same moment'),
        findsOneWidget,
      );
      expect(lookups, isEmpty); // Debounced.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(lookups.single.host, 'open.spotify.com');
      expect(
        find.widgetWithText(TextField, 'Kesariya'),
        findsOneWidget,
        reason: 'Title filled from the lookup',
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Artist (optional)'),
        'Arijit Singh',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final song = service.saved.single;
      expect(song.id, '');
      expect(song.title, 'Kesariya');
      expect(song.artist, 'Arijit Singh');
      expect(song.source, SongSource.spotify);
      expect(song.url, 'https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh');
      expect(song.moment, SongMoment.ourSong); // First song in the library.
      expect(song.addedBy, 'u1');
      expect(find.byType(SongEditorScreen), findsNothing);
    });

    testWidgets('a lookup never overwrites what you typed', (tester) async {
      phone(tester);
      service = FakeMusicService(songs: [happy], nowMs: t0);
      oEmbed = {
        'title': 'Arijit Singh - Tum Hi Ho (Official Video)',
        'author_name': 'T-Series',
      };
      await tester.pumpWidget(app(host(const SongEditorScreen())));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Our song',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Song link'),
        'https://youtu.be/Umqb9KENgmk',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Plays inside the app, in sync'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Our song'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Arijit Singh'), findsOneWidget);
      // Not the first song: defaults to "Other".
      final other = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '🎵 Other'),
      );
      expect(other.selected, isTrue);
    });

    testWidgets('editing around the same link keeps the pending lookup', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(app(host(const SongEditorScreen())));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final link = find.widgetWithText(TextField, 'Song link');
      const url = 'https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh';
      await tester.enterText(link, url);
      await tester.pump(const Duration(milliseconds: 300));
      // Same link once normalised: the lookup must still happen.
      await tester.enterText(link, '$url?si=abc ');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(lookups, hasLength(1));
      expect(find.widgetWithText(TextField, 'Kesariya'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a new link clears details filled in for the old one', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(app(host(const SongEditorScreen())));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final link = find.widgetWithText(TextField, 'Song link');
      await tester.enterText(
        link,
        'https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Kesariya'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Artist (optional)'),
        'Typed by me',
      );

      oEmbed = {'title': ''};
      await tester.enterText(
        link,
        'https://soundcloud.com/someone/night-drive',
      );
      await tester.pump();
      // The auto-filled title is gone at once; the typed artist stays.
      expect(find.widgetWithText(TextField, 'Kesariya'), findsNothing);
      expect(find.widgetWithText(TextField, 'Typed by me'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(lookups, hasLength(2));
      // Nothing from the lookup: falls back to the link's own title.
      expect(find.widgetWithText(TextField, 'Night Drive'), findsOneWidget);
    });

    testWidgets('invalid and duplicate links are caught', (tester) async {
      phone(tester);
      service = FakeMusicService(songs: [happy], nowMs: t0);
      await tester.pumpWidget(app(host(const SongEditorScreen())));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final link = find.widgetWithText(TextField, 'Song link');
      await tester.enterText(link, 'just some words');
      await tester.pump();
      expect(find.text('That doesn’t look like a link'), findsOneWidget);

      await tester.enterText(link, happy.url);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Already in your songs: Kesariya'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.saved, isEmpty);
    });

    testWidgets('editing keeps the link and saves details', (tester) async {
      phone(tester);
      service = FakeMusicService(songs: [happy], nowMs: t0);
      await tester.pumpWidget(app(host(SongEditorScreen(song: happy))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Edit song'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Song link'), findsNothing);
      expect(find.text('Spotify'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Why it’s yours (optional)'),
        'Road trip to Coorg',
      );
      await tester.tap(find.text('🚗 Road trip'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = service.saved.single;
      expect(saved.id, 'b');
      expect(saved.note, 'Road trip to Coorg');
      expect(saved.moment, SongMoment.roadTrip);
      expect(saved.url, happy.url);
    });
  });

  group('ListenTogetherScreen', () {
    Future<void> tick(WidgetTester tester, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    testWidgets('external song: counts down and opens once', (tester) async {
      phone(tester);
      service = FakeMusicService(
        songs: [happy, chill],
        nowMs: t0,
        session: testSession(
          happy,
          status: ListeningStatus.countdown,
          at: t0 + 3000,
          version: 3,
          queue: ['c'],
          listeners: {'u2': t0},
        ),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester);
      expect(find.text('Starting in 3…'), findsOneWidget);
      await tick(tester);
      expect(find.text('Ravi is listening with you'), findsOneWidget);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('Ilahi'), findsOneWidget);
      expect(launched, isEmpty);

      service.nowMs = t0 + 3100;
      await tick(tester, times: 4);
      expect(launched, [happy.url]);
      expect(find.text('Playing in Spotify on both phones'), findsOneWidget);

      await tester.tap(find.text('Open again'));
      await tick(tester);
      expect(launched, [happy.url, happy.url]);

      await tester.tap(find.text('Start together again'));
      await tick(tester);
      expect(service.calls, contains('status countdown'));

      // The restart arrives: a new countdown opens it again at zero.
      service.session = testSession(
        happy,
        status: ListeningStatus.countdown,
        at: t0 + 5000,
        version: 4,
      );
      service.nowMs = t0 + 5200;
      await tick(tester, times: 2);
      expect(launched, hasLength(3));

      await tester.tap(find.text('Next song'));
      await tick(tester);
      expect(service.calls, contains('next b'));
      expect(player.calls, isEmpty);
    });

    testWidgets('joining long after an external start does not open it', (
      tester,
    ) async {
      phone(tester);
      service = FakeMusicService(
        songs: [happy],
        nowMs: t0,
        session: testSession(
          happy,
          status: ListeningStatus.countdown,
          at: t0 - 60000,
        ),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester, times: 3);
      expect(launched, isEmpty);
      expect(find.text('Open again'), findsOneWidget);
    });

    testWidgets('in-app song follows the session', (tester) async {
      phone(tester);
      service = FakeMusicService(
        songs: [ours],
        nowMs: t0,
        session: testSession(ours, at: t0),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester, times: 2);
      // Loaded at the expected spot and started.
      expect(player.calls.take(2), ['cue Umqb9KENgmk 0', 'play']);
      expect(service.calls, contains('heartbeat'));
      expect(
        find.text('Waiting for Ravi to join — they’ll see a banner'),
        findsOneWidget,
      );

      // Drift: the player is 10 s ahead of where the session says.
      player.calls.clear();
      service.nowMs = t0 + 4000;
      player.emitPosition(14000);
      await tick(tester);
      expect(player.calls, ['seek 4000', 'play']);

      // Paused on the other phone.
      player.calls.clear();
      service.session = testSession(
        ours,
        status: ListeningStatus.paused,
        positionMs: 4200,
        at: t0 + 4200,
        version: 2,
      );
      await tick(tester);
      expect(player.calls.first, 'pause');
      expect(find.byTooltip('Play for both'), findsOneWidget);

      // Our own controls go through the session.
      await tester.tap(find.byTooltip('Play for both'));
      await tick(tester);
      expect(service.calls, contains('status playing'));

      // Resumed, then the video ends: move on.
      service.session = testSession(
        ours,
        positionMs: 4200,
        at: t0 + 4000,
        version: 3,
      );
      await tick(tester);
      player.emitState(SongPlayerState.ended);
      await tick(tester, times: 2);
      expect(
        service.calls.where((c) => c == 'next a'),
        hasLength(1),
        reason: 'Asked once per song',
      );
    });

    testWidgets('countdown overlay, then plays at zero', (tester) async {
      phone(tester);
      service = FakeMusicService(
        songs: [ours],
        nowMs: t0,
        session: testSession(
          ours,
          status: ListeningStatus.countdown,
          positionMs: 30000,
          at: t0 + 2500,
        ),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester);
      expect(player.calls, ['cue Umqb9KENgmk 30000']);
      expect(find.text('Starting together in'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      service.nowMs = t0 + 2600;
      await tick(tester);
      expect(player.calls.last, 'play');
      expect(find.text('Starting together in'), findsNothing);
    });

    testWidgets('stop for both asks, and ended shows a way back', (
      tester,
    ) async {
      phone(tester);
      service = FakeMusicService(
        songs: [ours],
        nowMs: t0,
        session: testSession(ours, at: t0),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester);
      await tester.tap(find.byTooltip('Stop for both'));
      await tick(tester, times: 2);
      expect(find.text('Stop for both of you?'), findsOneWidget);
      await tester.tap(find.text('Stop'));
      await tick(tester, times: 2);
      expect(service.calls, contains('status ended'));

      service.session = testSession(
        ours,
        status: ListeningStatus.ended,
        at: t0,
        version: 2,
      );
      await tick(tester);
      expect(find.text('Listening together ended'), findsOneWidget);
      expect(find.text('Back to songs'), findsOneWidget);
      expect(player.disposed, isTrue);
    });

    testWidgets('a video that cannot be embedded opens in YouTube', (
      tester,
    ) async {
      phone(tester);
      service = FakeMusicService(
        songs: [ours],
        nowMs: t0,
        session: testSession(ours, at: t0),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester);
      player.emitError(SongPlayerError.notEmbeddable);
      await tick(tester);
      expect(find.textContaining('can’t play inside the app'), findsWidgets);
      expect(find.textContaining('Playing in YouTube'), findsOneWidget);
      await tester.tap(find.text('Open again'));
      await tick(tester);
      expect(launched, [ours.url]);
    });
  });

  group('ListenTogetherScreen details', () {
    Future<void> tick(WidgetTester tester, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    testWidgets('blocked autoplay offers Tap to play', (tester) async {
      phone(tester);
      player.blockPlay = true;
      service = FakeMusicService(
        songs: [ours],
        nowMs: t0,
        session: testSession(ours, at: t0),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester, times: 2);
      expect(find.text('Tap to play'), findsNothing);
      // Still not playing three seconds later.
      service.nowMs = t0 + 3500;
      await tick(tester, times: 2);
      expect(find.text('Tap to play'), findsOneWidget);

      player.blockPlay = false;
      player.calls.clear();
      await tester.tap(find.text('Tap to play'));
      await tick(tester);
      expect(player.calls.take(2), ['play', 'seek 3500']);
      expect(find.text('Tap to play'), findsNothing);
    });

    testWidgets('a removed video says so', (tester) async {
      phone(tester);
      service = FakeMusicService(
        songs: [ours],
        nowMs: t0,
        session: testSession(ours, at: t0),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester);
      player.emitError(SongPlayerError.notFound);
      await tick(tester);
      expect(find.textContaining('removed or is private'), findsWidgets);
      expect(find.text('Open again'), findsNothing);
      expect(find.text('Next song'), findsOneWidget);
    });

    testWidgets('external copy depends on whether the partner is there', (
      tester,
    ) async {
      phone(tester);
      service = FakeMusicService(
        songs: [happy],
        nowMs: t0,
        session: testSession(happy, at: t0 - 1000),
      );
      await tester.pumpWidget(app(const ListenTogetherScreen()));
      await tick(tester, times: 2);
      expect(
        find.text('Playing in Spotify — Ravi will join when they open the app'),
        findsOneWidget,
      );
      expect(
        find.textContaining('When the count hits zero, Spotify opens on both'),
        findsOneWidget,
      );
      expect(find.textContaining('Spotify Jam'), findsOneWidget);
    });

    testWidgets('reopening during the same start does not reopen the app', (
      tester,
    ) async {
      phone(tester);
      service = FakeMusicService(
        songs: [happy],
        nowMs: t0 + 1000,
        session: testSession(
          happy,
          status: ListeningStatus.countdown,
          at: t0,
          version: 7,
        ),
      );
      await tester.pumpWidget(app(host(const ListenTogetherScreen())));
      await tester.tap(find.text('open'));
      await tick(tester, times: 3);
      expect(launched, hasLength(1));

      await tester.pageBack();
      await tick(tester, times: 3);
      await tester.tap(find.text('open'));
      await tick(tester, times: 3);
      expect(find.byType(ListenTogetherScreen), findsOneWidget);
      expect(launched, hasLength(1));
    });

    testWidgets('a session error offers a retry', (tester) async {
      phone(tester);
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicServiceProvider.overrideWithValue(service),
            songPlayerFactoryProvider.overrideWithValue(() => player),
            currentUserProvider.overrideWithBuild((ref, notifier) => me),
            coupleProvider.overrideWith((ref) => Stream.value(couple)),
            partnerProvider.overrideWith((ref) => Stream.value(partner)),
            listeningSessionProvider.overrideWith((ref) {
              attempts++;
              return Stream.error(StateError('offline'));
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ListenTogetherScreen(),
          ),
        ),
      );
      await tick(tester, times: 2);
      expect(
        find.text('Couldn’t reach your listening session'),
        findsOneWidget,
      );
      expect(find.text('Listening together ended'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tick(tester, times: 2);
      expect(attempts, 2);
    });

    for (final external in [false, true]) {
      testWidgets(
        'fits a 360×640 phone with large text (${external ? 'external' : 'in-app'})',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 1920);
          tester.view.devicePixelRatio = 3;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final song = external ? happy : ours;
          service = FakeMusicService(
            songs: [ours, happy, chill],
            nowMs: t0,
            session: testSession(song, at: t0 - 1000, queue: ['b', 'c', 'a']),
          );
          await tester.pumpWidget(app(const ListenTogetherScreen()));
          await tick(tester, times: 3);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('ListeningBanner', () {
    Widget shell() => app(
      const Scaffold(body: Text('tab'), bottomNavigationBar: ListeningBanner()),
    );

    testWidgets('hidden without a session', (tester) async {
      phone(tester);
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      expect(find.textContaining('Listening together'), findsNothing);
    });

    testWidgets('shows the partner playing, pauses for both', (tester) async {
      phone(tester);
      service = FakeMusicService(
        songs: [ours],
        nowMs: t0,
        session: testSession(ours, at: t0, listeners: {'u2': t0}),
      );
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      expect(find.textContaining('Ravi is playing Tum Hi Ho'), findsOneWidget);
      expect(find.textContaining('Join'), findsOneWidget);

      await tester.tap(find.byTooltip('Pause for both'));
      await tester.pumpAndSettle();
      expect(service.calls, ['status paused']);

      service.session = testSession(ours, at: t0, version: 2);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Listening together · Tum Hi Ho'),
        findsOneWidget,
      );

      // Opens the player; asking again before it's up opens it once.
      await tester.tap(find.textContaining('Listening together'));
      unawaited(ListenTogetherScreen.open(tester.element(find.text('tab'))));
      await tester.pump();
      unawaited(ListenTogetherScreen.open(tester.element(find.text('tab'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byType(ListenTogetherScreen, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a forgotten session shows no banner', (tester) async {
      phone(tester);
      service = FakeMusicService(
        songs: [ours],
        nowMs: t0 + ListeningSession.staleAfterMs + 60000,
        session: testSession(ours, at: t0, listeners: {'u1': t0}),
      );
      await tester.pumpWidget(shell());
      await tester.pumpAndSettle();
      expect(find.textContaining('Tum Hi Ho'), findsNothing);
    });
  });

  group('Watch together', () {
    final vlog = testSong(
      'v1',
      title: 'Goa trip vlog',
      artist: 'Travel Duo',
      source: SongSource.youtube,
      mediaId: 'dQw4w9WgXcQ',
      moment: SongMoment.travel,
    );
    final trailer = testSong(
      'v2',
      title: 'Dune trailer',
      source: SongSource.youtube,
      mediaId: 'n9xhJrPXop4',
      moment: SongMoment.movieNight,
    );

    Future<void> tick(WidgetTester tester, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    testWidgets('Videos segment: empty, then cards that start watching', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(app(const MusicScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();
      expect(
        find.text('Watch together — paste a YouTube link'),
        findsOneWidget,
      );
      expect(find.text('Add your first video'), findsOneWidget);

      service.videos.songs = [vlog, trailer];
      await tester.pumpAndSettle();
      expect(find.text('Goa trip vlog'), findsOneWidget);
      expect(find.text('Travel Duo'), findsOneWidget);
      expect(find.text('✈️ Travel'), findsWidgets);
      expect(find.text('Add video'), findsOneWidget);

      await tester.tap(find.byTooltip('Watch together').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.videos.calls, contains('start v1 v2'));
      expect(service.calls.where((c) => c.startsWith('start')), isEmpty);
      expect(find.byType(WatchTogetherScreen), findsOneWidget);
      expect(find.text('Watching together'), findsOneWidget);
    });

    testWidgets('the video editor only takes YouTube links', (tester) async {
      phone(tester);
      oEmbed = {
        'title': 'Arijit Singh - Our Song (Official Video)',
        'author_name': 'T-Series',
      };
      await tester.pumpWidget(
        app(host(const SongEditorScreen(shelf: MediaShelf.videos))),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add a video'), findsOneWidget);

      final link = find.widgetWithText(TextField, 'YouTube link');
      await tester.enterText(
        link,
        'https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(
        find.text('Only YouTube links can be watched together for now'),
        findsOneWidget,
      );
      expect(lookups, isEmpty);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.videos.saved, isEmpty);

      await tester.enterText(link, 'https://youtu.be/dQw4w9WgXcQ');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      // A video keeps its whole title, and the channel.
      expect(
        find.widgetWithText(
          TextField,
          'Arijit Singh - Our Song (Official Video)',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'T-Series'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = service.videos.saved.single;
      expect(saved.mediaId, 'dQw4w9WgXcQ');
      expect(saved.moment, SongMoment.movieNight);
      expect(service.saved, isEmpty);
    });

    testWidgets('the watch screen plays and pauses through the session', (
      tester,
    ) async {
      phone(tester);
      service.videos.songs = [vlog, trailer];
      service.videos.session = testSession(
        vlog,
        at: t0,
        queue: ['v2'],
        listeners: {'u2': t0},
      );
      await tester.pumpWidget(app(const WatchTogetherScreen()));
      await tick(tester, times: 3);
      expect(player.calls.take(2), ['cue dQw4w9WgXcQ 0', 'play']);
      expect(find.text('Ravi is watching with you'), findsOneWidget);
      expect(find.text('Dune trailer'), findsOneWidget);
      expect(service.videos.calls, contains('heartbeat'));

      await tester.tap(find.byTooltip('Pause for both'));
      await tick(tester);
      expect(service.videos.calls, contains('status paused'));
      expect(service.calls.where((c) => c.startsWith('status')), isEmpty);

      player.calls.clear();
      service.videos.session = testSession(
        vlog,
        status: ListeningStatus.paused,
        positionMs: 900,
        at: t0 + 900,
        version: 2,
      );
      await tick(tester);
      expect(player.calls.first, 'pause');
    });

    testWidgets('fullscreen goes landscape and back, keeping the player', (
      tester,
    ) async {
      phone(tester);
      final system = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          system.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      service.videos.songs = [vlog];
      service.videos.session = testSession(vlog, at: t0);
      await tester.pumpWidget(app(const WatchTogetherScreen()));
      await tick(tester, times: 2);

      await tester.tap(find.byTooltip('Fullscreen'));
      await tick(tester);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      expect(
        system
            .firstWhere(
              (c) => c.method == 'SystemChrome.setPreferredOrientations',
            )
            .arguments,
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
      );

      // Controls in fullscreen still go through the session.
      await tester.tap(find.byTooltip('Pause for both'));
      await tick(tester);
      expect(service.videos.calls, contains('status paused'));

      system.clear();
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tick(tester);
      expect(find.byType(AppBar), findsOneWidget);
      expect(
        system
            .firstWhere(
              (c) => c.method == 'SystemChrome.setPreferredOrientations',
            )
            .arguments,
        isEmpty,
      );
      // Same player throughout: loaded once, never thrown away.
      expect(player.calls.where((c) => c.startsWith('cue')), hasLength(1));
      expect(player.disposed, isFalse);
    });

    testWidgets('the banner shows the watch session, or the newest one', (
      tester,
    ) async {
      phone(tester);
      service.videos.songs = [vlog];
      service.videos.session = testSession(
        vlog,
        at: t0 - 1000,
        listeners: {'u2': t0},
      );
      await tester.pumpWidget(
        app(
          const Scaffold(
            body: Text('tab'),
            bottomNavigationBar: ListeningBanner(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Ravi is watching Goa trip vlog'),
        findsOneWidget,
      );

      // A music session changed more recently wins.
      service.session = testSession(ours, at: t0);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Listening together · Tum Hi Ho'),
        findsOneWidget,
      );
      // Then the video is resumed: it's the newest again.
      service.videos.session = testSession(vlog, at: t0 + 500, version: 2);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Watching together · Goa trip vlog'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Pause for both'));
      await tester.pumpAndSettle();
      expect(service.videos.calls, ['status paused']);
    });
  });

  group('PlaybackSync', () {
    const playing = SongPlayerValue(
      state: SongPlayerState.playing,
      positionMs: 10000,
      durationMs: 200000,
    );
    const paused = SongPlayerValue(
      state: SongPlayerState.paused,
      positionMs: 10000,
      durationMs: 200000,
    );
    final song = testSong(
      'a',
      source: SongSource.youtube,
      mediaId: 'Umqb9KENgmk',
    );

    test('no session or ended stops', () {
      final sync = PlaybackSync();
      expect(
        sync.decide(session: null, nowMs: t0, player: playing, loaded: true),
        const SyncEnded(),
      );
      expect(
        sync.decide(
          session: testSession(song, status: ListeningStatus.ended, at: t0),
          nowMs: t0,
          player: playing,
          loaded: true,
        ),
        const SyncEnded(),
      );
    });

    test('countdown cues, holds, then plays', () {
      final sync = PlaybackSync();
      final s = testSession(
        song,
        status: ListeningStatus.countdown,
        positionMs: 5000,
        at: t0 + 3000,
      );
      expect(
        sync.decide(
          session: s,
          nowMs: t0,
          player: const SongPlayerValue(),
          loaded: false,
        ),
        const SyncCue(5000),
      );
      const cued = SongPlayerValue(
        state: SongPlayerState.cued,
        positionMs: 5000,
      );
      expect(
        sync.decide(session: s, nowMs: t0, player: cued, loaded: true),
        const SyncWaitCountdown(3000),
      );
      // "Start together again" while playing: pause at the start point.
      expect(
        sync.decide(session: s, nowMs: t0, player: playing, loaded: true),
        const SyncPause(seekToMs: 5000),
      );
      // Zero: play from where it was cued.
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0 + 3200,
          player: cued,
          loaded: true,
        ),
        const SyncPlay(),
      );
    });

    test('joining part-way loads at the expected spot and plays', () {
      expect(
        PlaybackSync().decide(
          session: testSession(song, positionMs: 1000, at: t0),
          nowMs: t0 + 60000,
          player: const SongPlayerValue(),
          loaded: false,
        ),
        const SyncCue(61000, thenPlay: true),
      );
    });

    test('playing: small drift is fine, big drift seeks once', () {
      final sync = PlaybackSync();
      final s = testSession(song, at: t0);
      expect(
        sync.decide(
          session: s,
          nowMs: t0 + 11000,
          player: playing,
          loaded: true,
        ),
        const SyncNone(),
      );
      expect(
        sync.decide(
          session: s,
          nowMs: t0 + 20000,
          player: playing,
          loaded: true,
        ),
        const SyncPlay(seekToMs: 20000),
      );
      // The player hasn't caught up yet: don't seek again straight away.
      expect(
        sync.decide(
          session: s,
          nowMs: t0 + 21000,
          player: playing,
          loaded: true,
        ),
        const SyncNone(),
      );
      expect(
        sync.decide(
          session: s,
          nowMs: t0 + 30000,
          player: playing,
          loaded: true,
        ),
        const SyncPlay(seekToMs: 30000),
      );
    });

    test('playing session with a paused player resumes', () {
      final s = testSession(song, at: t0);
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0 + 10500,
          player: paused,
          loaded: true,
        ),
        const SyncPlay(),
      );
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0 + 50000,
          player: paused,
          loaded: true,
        ),
        const SyncPlay(seekToMs: 50000),
      );
    });

    test('paused session pauses and pins the position', () {
      final s = testSession(
        song,
        status: ListeningStatus.paused,
        positionMs: 10500,
        at: t0,
      );
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0 + 9999,
          player: playing,
          loaded: true,
        ),
        // 500 ms off: paused seeks are silent, so pin it.
        const SyncPause(seekToMs: 10500),
      );
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0 + 9999,
          player: playing.copyWith(positionMs: 10400),
          loaded: true,
        ),
        const SyncPause(),
      );
      expect(
        PlaybackSync().decide(
          session: s.withStatus(
            ListeningStatus.paused,
            uid: 'u2',
            nowMs: t0,
            positionMs: 90000,
          ),
          nowMs: t0 + 9999,
          player: paused,
          loaded: true,
        ),
        const SyncPause(seekToMs: 90000),
      );
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0,
          player: paused.copyWith(positionMs: 10600),
          loaded: true,
        ),
        const SyncNone(),
      );
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0,
          player: const SongPlayerValue(),
          loaded: false,
        ),
        const SyncCue(10500),
      );
    });

    test('a cued video is re-cued rather than seeked (seeking starts it)', () {
      final s = testSession(
        song,
        status: ListeningStatus.paused,
        positionMs: 42000,
        at: t0,
      );
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0,
          player: const SongPlayerValue(
            state: SongPlayerState.cued,
            positionMs: 0,
          ),
          loaded: true,
        ),
        const SyncCue(42000),
      );
    });

    test('the end of the song moves on', () {
      final s = testSession(song, at: t0);
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0 + 1000,
          player: playing.copyWith(state: SongPlayerState.ended),
          loaded: true,
        ),
        const SyncNext(),
      );
      // Joined after the song would have finished.
      expect(
        PlaybackSync().decide(
          session: s,
          nowMs: t0 + 205000,
          player: playing,
          loaded: true,
        ),
        const SyncNext(),
      );
    });
  });
}
