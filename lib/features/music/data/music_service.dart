import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/music/data/media_shelf.dart';
import 'package:couple_app/features/music/data/server_clock.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';

/// Thrown when a listening-session change can't be applied, e.g. because
/// the session ended on the other phone a moment earlier.
class ListeningException implements Exception {
  const ListeningException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads and writes one shelf of the couple's media and its shared
/// session: songs (`couples/{id}/songs`, `couples/{id}/listening/now`) or
/// videos (`couples/{id}/videos`, `couples/{id}/watching/now`).
class MusicService {
  MusicService({
    FirebaseFirestore? firestore,
    ServerClock? clock,
    this.shelf = MediaShelf.songs,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       clock = clock ?? ServerClock();

  final FirebaseFirestore _db;

  /// Server time on this phone, shared by everything that syncs playback.
  final ServerClock clock;

  /// Which collections this service reads and writes.
  final MediaShelf shelf;

  /// The same service for another shelf, sharing the database and clock
  /// (one calibration serves both).
  MusicService forShelf(MediaShelf other) => other == shelf
      ? this
      : MusicService(firestore: _db, clock: clock, shelf: other);

  CollectionReference<Map<String, dynamic>> _songs(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection(shelf.items);

  CollectionReference<Map<String, dynamic>> _listening(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection(shelf.sessions);

  DocumentReference<Map<String, dynamic>> _session(String coupleId) =>
      _listening(coupleId).doc(ListeningSession.docId);

  // ---- Songs ---------------------------------------------------------------

  /// Every saved song, unsorted (see `SongLists`).
  Stream<List<Song>> watchSongs(String coupleId) => _songs(
    coupleId,
  ).snapshots().map((snap) => snap.docs.map(Song.fromDoc).toList());

  /// Adds [song] when its id is empty (returning the new id), otherwise
  /// updates its details.
  Future<String> save(String coupleId, Song song) async {
    final data = song.toMap();
    if (song.id.isEmpty) {
      final ref = await _songs(coupleId).add({
        ...data,
        'lovedBy': {song.addedBy: true},
        'playCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    }
    // The link and who added it never change after the song is saved.
    final editable = {...data}
      ..remove('url')
      ..remove('source')
      ..remove('kind')
      ..remove('mediaId')
      ..remove('addedBy');
    await _songs(coupleId).doc(song.id).update({
      ...editable,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return song.id;
  }

  /// Marks [songId] as loved (or not) by [uid].
  Future<void> setLoved(
    String coupleId,
    String songId, {
    required String uid,
    required bool loved,
  }) {
    return _songs(
      coupleId,
    ).doc(songId).update({'lovedBy.$uid': loved ? true : FieldValue.delete()});
  }

  Future<void> delete(String coupleId, String songId) =>
      _songs(coupleId).doc(songId).delete();

  // ---- Listening together -------------------------------------------------

  /// The current session, or null when there has never been one.
  Stream<ListeningSession?> watchSession(String coupleId) => _session(coupleId)
      .snapshots()
      .map((snap) => snap.exists ? ListeningSession.fromDoc(snap) : null);

  /// Measures this phone's offset from server time by writing a server
  /// timestamp to `{shelf.sessions}/clock-{uid}` and reading it back. Safe
  /// to call more than once: the fastest round trip wins.
  ///
  /// Only the write is timed: the server stamps `t` while handling it, so
  /// the midpoint of that round trip is the best estimate. The read that
  /// fetches the stamp comes after and isn't counted.
  Future<void> calibrateClock(String coupleId, String uid) async {
    final ref = _listening(coupleId).doc('clock-$uid');
    try {
      final sent = clock.localNowMs();
      await ref.set({'t': FieldValue.serverTimestamp()});
      final received = clock.localNowMs();
      final snap = await ref.get(const GetOptions(source: Source.server));
      final t = snap.data()?['t'];
      if (t is Timestamp) {
        clock.observe(
          sentMs: sent,
          receivedMs: received,
          serverMs: t.millisecondsSinceEpoch,
        );
      }
    } on Object {
      // Offline: keep using the phone's own clock.
    }
  }

  /// Calibrates the clock first if it never has been, so session times
  /// written from this phone are in server time.
  Future<void> _ensureCalibrated(String coupleId, String uid) async {
    if (!clock.isCalibrated) await calibrateClock(coupleId, uid);
  }

  /// Starts listening to [song] together, replacing whatever was playing.
  /// Both phones count down and start at the same moment. [queue] is what
  /// plays after it.
  Future<void> startSession({
    required String coupleId,
    required Song song,
    required String uid,
    List<String> queue = const [],
  }) async {
    await _ensureCalibrated(coupleId, uid);
    final ref = _session(coupleId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final old = snap.exists ? ListeningSession.fromDoc(snap) : null;
      final now = clock.nowMs();
      final session = ListeningSession.start(
        song: song,
        uid: uid,
        nowMs: now,
        queue: queue.where((id) => id != song.id).toList(),
        previousVersion: old?.version ?? 0,
        listeners: _freshListeners(old, now),
      );
      tx.set(ref, {
        ...session.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    await _recordPlay(coupleId, song.id);
  }

  /// Pauses, resumes, restarts or stops the session. [positionMs] pins the
  /// position (after a seek); otherwise it carries on from where it is.
  Future<void> setStatus({
    required String coupleId,
    required String uid,
    required ListeningStatus status,
    int? positionMs,
  }) async {
    await _ensureCalibrated(coupleId, uid);
    return _change(coupleId, (s, now) {
      if (status == ListeningStatus.countdown) {
        // "Start together again": count down to the current position.
        final here = positionMs ?? s.expectedPositionMs(now).clamp(0, 1 << 31);
        return s
            .withStatus(
              ListeningStatus.countdown,
              uid: uid,
              nowMs: now + ListeningSession.countdownMs,
              positionMs: here,
            )
            .withListener(uid, now);
      }
      return s.withStatus(status, uid: uid, nowMs: now, positionMs: positionMs);
    });
  }

  /// Moves to the next song in the queue, if [currentSongId] is still the
  /// one playing (so when both phones reach the end at once, only one
  /// advances). Ends the session when the queue is empty.
  Future<void> next({
    required String coupleId,
    required String uid,
    required String currentSongId,
  }) async {
    await _ensureCalibrated(coupleId, uid);
    final ref = _session(coupleId);
    String? startedSongId;
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final s = ListeningSession.fromDoc(snap);
      if (!s.isLive || s.songId != currentSongId) return;
      final now = clock.nowMs();
      final queue = [...s.queue];
      while (queue.isNotEmpty) {
        final id = queue.removeAt(0);
        final songSnap = await tx.get(_songs(coupleId).doc(id));
        if (!songSnap.exists) continue; // Deleted since it was queued.
        final song = Song.fromDoc(songSnap);
        final nextSession = ListeningSession.start(
          song: song,
          uid: uid,
          nowMs: now,
          queue: queue,
          // The next song follows on quickly; both phones are already here.
          countdownMs: 1500,
          previousVersion: s.version,
          listeners: _freshListeners(s, now),
        );
        tx.set(ref, {
          ...nextSession.toMap(),
          // Keep who started listening; the next song just follows on.
          'hostUid': s.hostUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        startedSongId = song.id;
        return;
      }
      tx.update(ref, {
        ...s.withStatus(ListeningStatus.ended, uid: uid, nowMs: now).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    final id = startedSongId;
    if (id != null) await _recordPlay(coupleId, id);
  }

  /// Checks in: this phone is on the player screen. Doesn't change
  /// playback, so it doesn't bump the version.
  Future<void> heartbeat(String coupleId, String uid) {
    return _session(
      coupleId,
    ).update({'listeners.$uid': clock.nowMs()}).catchError((Object _) {});
  }

  /// This phone closed the player. The session keeps going for the other.
  Future<void> leave(String coupleId, String uid) {
    return _session(
      coupleId,
    ).update({'listeners.$uid': FieldValue.delete()}).catchError((Object _) {});
  }

  Future<void> _change(
    String coupleId,
    ListeningSession Function(ListeningSession s, int nowMs) apply,
  ) {
    final ref = _session(coupleId);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final s = snap.exists ? ListeningSession.fromDoc(snap) : null;
      if (s == null || !s.isLive) {
        throw const ListeningException('Listening together has ended.');
      }
      final next = apply(s, clock.nowMs());
      tx.update(ref, {
        ...next.toMap(),
        'version': s.version + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _recordPlay(String coupleId, String songId) {
    return _songs(coupleId)
        .doc(songId)
        .update({
          'playCount': FieldValue.increment(1),
          'lastPlayedAt': FieldValue.serverTimestamp(),
        })
        .catchError((Object _) {});
  }

  /// Listeners still checked in at [now], so a new song keeps them.
  static Map<String, int> _freshListeners(ListeningSession? s, int now) => {
    if (s != null)
      for (final e in s.listeners.entries)
        if (now - e.value < ListeningSession.listenerTimeoutMs) e.key: e.value,
  };
}
