import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/data/server_clock.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/models/song_link.dart';

/// The real MusicService against an in-memory database.
void main() {
  const couple = 'c1';
  late Db db;
  late int now;
  late ServerClock clock;
  late MusicService service;

  Song song(String id) => Song(
    id: id,
    url: 'https://www.youtube.com/watch?v=${id * 11}',
    source: SongSource.youtube,
    kind: SongKind.video,
    mediaId: id * 11,
    title: 'Song $id',
    addedBy: 'u1',
  );

  Future<void> addSong(Song s) => db
      .collection('couples')
      .doc(couple)
      .collection('songs')
      .doc(s.id)
      .set({...s.toMap(), 'playCount': 0});

  Future<ListeningSession?> session() async {
    final snap = await db
        .collection('couples')
        .doc(couple)
        .collection('listening')
        .doc(ListeningSession.docId)
        .get();
    return snap.exists ? ListeningSession.fromDoc(snap) : null;
  }

  setUp(() async {
    db = Db(MemoryBackend());
    now = 1000000;
    clock = ServerClock(localNowMs: () => now)
      // Already calibrated (offset 0), so times are predictable.
      ..observe(sentMs: 0, receivedMs: 0, serverMs: 0);
    service = MusicService(db: db, clock: clock);
    for (final id in ['a', 'b', 'c']) {
      await addSong(song(id));
    }
  });

  test('an uncalibrated clock is calibrated before the first write', () async {
    final fresh = MusicService(
      db: db,
      clock: ServerClock(localNowMs: () => now),
    );
    expect(fresh.clock.isCalibrated, isFalse);
    await fresh.startSession(coupleId: couple, song: song('a'), uid: 'u1');
    expect(fresh.clock.isCalibrated, isTrue);
    final stamp = await db
        .collection('couples')
        .doc(couple)
        .collection('listening')
        .doc('clock-u1')
        .get();
    expect(stamp.exists, isTrue);
  });

  test(
    'startSession replaces an existing session and bumps its version',
    () async {
      await db
          .collection('couples')
          .doc(couple)
          .collection('listening')
          .doc(ListeningSession.docId)
          .set(
            ListeningSession.start(
              song: song('b'),
              uid: 'u2',
              nowMs: now - 60000,
              previousVersion: 4,
            ).toMap(),
          );
      expect((await session())!.version, 5);

      await service.startSession(
        coupleId: couple,
        song: song('a'),
        uid: 'u1',
        queue: ['a', 'b', 'c'],
      );
      final s = (await session())!;
      expect(s.version, 6);
      expect(s.songId, 'a');
      expect(s.status, ListeningStatus.countdown);
      expect(s.at, now + ListeningSession.countdownMs);
      expect(s.queue, ['b', 'c'], reason: 'The song itself is not queued');
      expect(s.hostUid, 'u1');
      final played = await db
          .collection('couples')
          .doc(couple)
          .collection('songs')
          .doc('a')
          .get();
      expect(played.data()!['playCount'], 1);
    },
  );

  test('setStatus pauses, resumes and restarts together', () async {
    await service.startSession(coupleId: couple, song: song('a'), uid: 'u1');
    final started = (await session())!;

    // 6 s after the countdown ran out, the other phone pauses.
    now = started.at + 6000;
    await service.setStatus(
      coupleId: couple,
      uid: 'u2',
      status: ListeningStatus.paused,
    );
    var s = (await session())!;
    expect(s.status, ListeningStatus.paused);
    expect(s.positionMs, 6000);
    expect(s.updatedBy, 'u2');
    expect(s.version, started.version + 1);

    // A minute later: resume from the same spot.
    now += 60000;
    await service.setStatus(
      coupleId: couple,
      uid: 'u1',
      status: ListeningStatus.playing,
    );
    s = (await session())!;
    expect(s.status, ListeningStatus.playing);
    expect(s.positionMs, 6000);
    expect(s.at, now);
    expect(s.expectedPositionMs(now + 1000), 7000);

    // "Start together again": count down to where it is now.
    now += 2000;
    await service.setStatus(
      coupleId: couple,
      uid: 'u1',
      status: ListeningStatus.countdown,
    );
    s = (await session())!;
    expect(s.status, ListeningStatus.countdown);
    expect(s.positionMs, 8000);
    expect(s.at, now + ListeningSession.countdownMs);
    expect(s.version, started.version + 3);

    // Stopped: further changes explain that it ended.
    await service.setStatus(
      coupleId: couple,
      uid: 'u1',
      status: ListeningStatus.ended,
    );
    expect((await session())!.isLive, isFalse);
    await expectLater(
      service.setStatus(
        coupleId: couple,
        uid: 'u2',
        status: ListeningStatus.playing,
      ),
      throwsA(isA<ListeningException>()),
    );
  });

  test('when both phones reach the end, only one advances', () async {
    await service.startSession(
      coupleId: couple,
      song: song('a'),
      uid: 'u1',
      queue: ['b', 'c'],
    );
    final v = (await session())!.version;
    await Future.wait([
      service.next(coupleId: couple, uid: 'u1', currentSongId: 'a'),
      service.next(coupleId: couple, uid: 'u2', currentSongId: 'a'),
    ]);
    final s = (await session())!;
    expect(s.songId, 'b');
    expect(s.queue, ['c']);
    expect(s.version, v + 1);
    expect(s.hostUid, 'u1', reason: 'The host stays who started listening');
  });

  test('next skips songs deleted since they were queued', () async {
    await service.startSession(
      coupleId: couple,
      song: song('a'),
      uid: 'u1',
      queue: ['b', 'c'],
    );
    await service.delete(couple, 'b');
    await service.next(coupleId: couple, uid: 'u1', currentSongId: 'a');
    final s = (await session())!;
    expect(s.songId, 'c');
    expect(s.queue, isEmpty);
    expect(s.status, ListeningStatus.countdown);
  });

  test('next ends the session when the queue is empty', () async {
    await service.startSession(coupleId: couple, song: song('a'), uid: 'u1');
    final v = (await session())!.version;
    await service.next(coupleId: couple, uid: 'u2', currentSongId: 'a');
    final s = (await session())!;
    expect(s.status, ListeningStatus.ended);
    expect(s.songId, 'a');
    expect(s.version, v + 1);
  });

  test('heartbeat and leave change listeners, not the version', () async {
    await service.startSession(coupleId: couple, song: song('a'), uid: 'u1');
    final v = (await session())!.version;

    now += 5000;
    await service.heartbeat(couple, 'u2');
    var s = (await session())!;
    expect(s.listeners['u2'], now);
    expect(s.isListening('u2', now), isTrue);
    expect(s.version, v);

    await service.leave(couple, 'u2');
    s = (await session())!;
    expect(s.listeners.containsKey('u2'), isFalse);
    expect(s.listeners.containsKey('u1'), isTrue);
    expect(s.version, v);
  });

  test('the videos shelf uses videos/ and watching/', () async {
    final videos = service.forShelf(MediaShelf.videos);
    expect(videos.shelf, MediaShelf.videos);
    expect(videos.clock, same(clock), reason: 'One clock for both shelves');

    final id = await videos.save(
      couple,
      Song.fromLink(
        SongLink.parse('https://youtu.be/dQw4w9WgXcQ')!,
        addedBy: 'u1',
      ),
    );
    await videos.startSession(
      coupleId: couple,
      song: song('a').copyWith(),
      uid: 'u1',
    );
    await videos.heartbeat(couple, 'u2');

    final c = db.collection('couples').doc(couple);
    final saved = await c.collection('videos').doc(id).get();
    expect(saved.data()!['mediaId'], 'dQw4w9WgXcQ');
    expect(saved.data()!['source'], 'youtube');
    expect(saved.data()!['kind'], 'video');
    expect(saved.data()!['lovedBy'], {'u1': true});
    final watching = await c.collection('watching').doc('now').get();
    expect(watching.data()!['songId'], 'a');
    expect((watching.data()!['listeners'] as Map).keys, contains('u2'));
    // Nothing leaked into the music shelf.
    expect((await c.collection('listening').doc('now').get()).exists, isFalse);
    expect((await c.collection('songs').doc(id).get()).exists, isFalse);
    expect(await videos.watchSession(couple).first, isNotNull);
    expect(await service.watchSession(couple).first, isNull);
  });
}
