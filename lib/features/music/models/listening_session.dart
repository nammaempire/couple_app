import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/models/song_link.dart';

/// Where a shared listening session is.
enum ListeningStatus {
  /// Counting down to [ListeningSession.at], when both phones start.
  countdown('countdown'),
  playing('playing'),
  paused('paused'),

  /// Stopped by one of you; the document is kept so the other phone sees
  /// that it ended rather than just disappearing.
  ended('ended');

  const ListeningStatus(this.id);
  final String id;

  static ListeningStatus fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return ListeningStatus.ended;
  }
}

/// The one "listening together" session a couple has.
/// Stored at `couples/{coupleId}/listening/now`.
///
/// Times are in server milliseconds (see `ServerClock`), so two phones
/// whose clocks disagree still agree on where the song is.
class ListeningSession {
  static const docId = 'now';

  /// How long the countdown runs before both phones start.
  static const countdownMs = 4000;

  /// A listener whose phone hasn't checked in for this long has left.
  static const listenerTimeoutMs = 90 * 1000;

  final String songId;
  final String url;
  final SongSource source;
  final String mediaId;
  final String title;
  final String artist;
  final String thumbnailUrl;

  final ListeningStatus status;

  /// Where the song was at [at], in milliseconds. During the countdown it
  /// is where playback will start.
  final int positionMs;

  /// Server time (ms) at which [positionMs] was true; during the countdown,
  /// when playback starts.
  final int at;

  /// Song ids still to play, in order.
  final List<String> queue;

  /// Who started the session.
  final String hostUid;
  final String updatedBy;

  /// uid → server time (ms) that phone last checked in.
  final Map<String, int> listeners;

  /// Goes up by one with every change, so two phones pressing buttons at
  /// once can't overwrite each other unseen.
  final int version;

  const ListeningSession({
    required this.songId,
    required this.url,
    required this.source,
    required this.status,
    required this.positionMs,
    required this.at,
    required this.hostUid,
    required this.updatedBy,
    required this.version,
    this.mediaId = '',
    this.title = '',
    this.artist = '',
    this.thumbnailUrl = '',
    this.queue = const [],
    this.listeners = const {},
  });

  /// A session that was left running with nobody on it is stale after this
  /// long without a change.
  static const staleAfterMs = 10 * 60 * 1000;

  bool get isLive => status != ListeningStatus.ended;

  /// Same rule as `Song.playsInApp`. The session doesn't store the link's
  /// kind; it relies on `mediaId` being set for YouTube links only when they
  /// are single videos (see `SongLink.parse`), so a playlist never matches.
  bool get playsInApp => source.playsInApp && mediaId.isNotEmpty;

  /// Left running and forgotten: nobody has checked in for
  /// [listenerTimeoutMs] and the last change (or start) was more than
  /// [staleAfterMs] ago. The document stays live, but nothing should
  /// advertise it.
  bool isStale(int nowMs) {
    if (nowMs - at <= staleAfterMs) return false;
    for (final seen in listeners.values) {
      if (nowMs - seen < listenerTimeoutMs) return false;
    }
    return true;
  }

  /// Live and not [isStale]: worth a banner.
  bool isActive(int nowMs) => isLive && !isStale(nowMs);

  String get displayTitle =>
      title.trim().isNotEmpty ? title.trim() : '${source.label} link';

  /// Where the song should be at server time [nowMs], in milliseconds.
  /// Negative while counting down (minus the time left).
  int expectedPositionMs(int nowMs) => switch (status) {
    ListeningStatus.countdown => positionMs + (nowMs - at),
    ListeningStatus.playing => positionMs + (nowMs - at),
    ListeningStatus.paused || ListeningStatus.ended => positionMs,
  };

  /// Whether the countdown has run out at [nowMs]: start playing.
  bool countdownDone(int nowMs) =>
      status == ListeningStatus.countdown && nowMs >= at;

  /// Milliseconds of countdown left at [nowMs] (0 once it has run out).
  int countdownLeftMs(int nowMs) =>
      status == ListeningStatus.countdown ? (at - nowMs).clamp(0, 1 << 31) : 0;

  /// Whether [uid] has checked in recently enough to count as listening.
  bool isListening(String uid, int nowMs) {
    final seen = listeners[uid];
    return isLive && seen != null && nowMs - seen < listenerTimeoutMs;
  }

  /// A player [actualMs] off from [expectedMs] by more than [toleranceMs]
  /// should seek. Small drift is left alone, since seeking stutters.
  static bool needsSeek(
    int actualMs,
    int expectedMs, {
    int toleranceMs = 1500,
  }) => (actualMs - expectedMs).abs() > toleranceMs;

  factory ListeningSession.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => ListeningSession.fromMap(doc.data() ?? const <String, dynamic>{});

  /// Builds a session from stored fields, tolerating malformed ones.
  static ListeningSession fromMap(Map<String, dynamic> data) {
    final rawListeners = data['listeners'];
    final rawQueue = data['queue'];
    return ListeningSession(
      songId: _string(data['songId']) ?? '',
      url: _string(data['url']) ?? '',
      source: SongSource.fromId(_string(data['source'])),
      mediaId: _string(data['mediaId']) ?? '',
      title: _string(data['title']) ?? '',
      artist: _string(data['artist']) ?? '',
      thumbnailUrl: _string(data['thumbnailUrl']) ?? '',
      status: ListeningStatus.fromId(_string(data['status'])),
      positionMs: _int(data['positionMs']).clamp(0, 1 << 31),
      at: _int(data['at']),
      queue: rawQueue is List
          ? rawQueue.whereType<String>().toList()
          : const [],
      hostUid: _string(data['hostUid']) ?? '',
      updatedBy: _string(data['updatedBy']) ?? '',
      listeners: rawListeners is Map
          ? {
              for (final e in rawListeners.entries)
                if (e.key is String && e.value is num)
                  e.key as String: (e.value as num).toInt(),
            }
          : const {},
      version: _int(data['version']),
    );
  }

  /// Every stored field except `updatedAt` (added by the service).
  Map<String, dynamic> toMap() => {
    'songId': songId,
    'url': url,
    'source': source.id,
    'mediaId': mediaId,
    'title': title,
    'artist': artist,
    'thumbnailUrl': thumbnailUrl,
    'status': status.id,
    'positionMs': positionMs,
    'at': at,
    'queue': queue,
    'hostUid': hostUid,
    'updatedBy': updatedBy,
    'listeners': listeners,
    'version': version,
  };

  /// A fresh session for [song], counting down from server time [nowMs]
  /// (YouTube songs and external links alike: both phones start together).
  factory ListeningSession.start({
    required Song song,
    required String uid,
    required int nowMs,
    List<String> queue = const [],
    int previousVersion = 0,
    Map<String, int> listeners = const {},
    int countdownMs = ListeningSession.countdownMs,
  }) {
    return ListeningSession(
      songId: song.id,
      url: song.url,
      source: song.source,
      mediaId: song.mediaId,
      title: song.title,
      artist: song.artist,
      thumbnailUrl: song.thumbnailUrl,
      status: ListeningStatus.countdown,
      positionMs: 0,
      at: nowMs + countdownMs,
      queue: queue.take(50).toList(),
      hostUid: uid,
      updatedBy: uid,
      listeners: {...listeners, uid: nowMs},
      version: previousVersion + 1,
    );
  }

  /// The same session with playback changed by [uid] at server time
  /// [nowMs]. Position is carried forward so it never jumps.
  ListeningSession withStatus(
    ListeningStatus next, {
    required String uid,
    required int nowMs,
    int? positionMs,
  }) {
    final here = positionMs ?? expectedPositionMs(nowMs).clamp(0, 1 << 31);
    return _copy(
      status: next,
      positionMs: here,
      at: nowMs,
      updatedBy: uid,
      listeners: {...listeners, uid: nowMs},
    );
  }

  /// [uid] checked in at [nowMs].
  ListeningSession withListener(String uid, int nowMs) =>
      _copy(listeners: {...listeners, uid: nowMs}, bump: false);

  ListeningSession _copy({
    ListeningStatus? status,
    int? positionMs,
    int? at,
    String? updatedBy,
    Map<String, int>? listeners,
    bool bump = true,
  }) {
    return ListeningSession(
      songId: songId,
      url: url,
      source: source,
      mediaId: mediaId,
      title: title,
      artist: artist,
      thumbnailUrl: thumbnailUrl,
      status: status ?? this.status,
      positionMs: positionMs ?? this.positionMs,
      at: at ?? this.at,
      queue: queue,
      hostUid: hostUid,
      updatedBy: updatedBy ?? this.updatedBy,
      listeners: listeners ?? this.listeners,
      version: bump ? version + 1 : version,
    );
  }
}

String? _string(Object? v) => v is String ? v : null;

int _int(Object? v) => v is num && !v.isNaN && !v.isInfinite ? v.toInt() : 0;
