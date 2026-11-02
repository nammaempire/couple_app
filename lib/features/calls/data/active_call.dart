import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/data/ongoing_call_notification.dart';
import 'package:couple_app/features/calls/data/webrtc_call_engine.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';

/// Builds the call engine (tests swap in a fake).
typedef CallEngineFactory =
    WebRtcCallEngine Function({
      required String coupleId,
      required String callId,
      required String myUid,
      required String partnerUid,
      required bool isCaller,
      required bool video,
    });

WebRtcCallEngine _defaultEngine({
  required String coupleId,
  required String callId,
  required String myUid,
  required String partnerUid,
  required bool isCaller,
  required bool video,
}) => WebRtcCallEngine(
  coupleId: coupleId,
  callId: callId,
  myUid: myUid,
  partnerUid: partnerUid,
  isCaller: isCaller,
  video: video,
);

/// The call in progress, from ringing to hang-up.
///
/// It lives outside any screen, so the call carries on when the call screen
/// is closed (back button, switching tabs) or the app goes to the
/// background. The call screen and the "return to call" bar are just views
/// of it. Only the hang-up button, the partner hanging up, or a connection
/// that stays lost for [lostTimeout] end it.
class ActiveCall extends ChangeNotifier {
  ActiveCall._({
    required this.session,
    required this.isOutgoing,
    required this.coupleId,
    required this.myUid,
    required this.partnerName,
    required this.calls,
    required this.chat,
    required CallEngineFactory engineFactory,
    required this.notification,
  }) {
    engine = engineFactory(
      coupleId: coupleId,
      callId: session.channelName,
      myUid: myUid,
      partnerUid: session.callerId == myUid
          ? session.calleeId
          : session.callerId,
      isCaller: isOutgoing,
      video: session.isVideo,
    );
  }

  /// The call in progress on this phone, or null.
  static final current = ValueNotifier<ActiveCall?>(null);

  /// How long a lost connection may try to recover before the call ends.
  static const lostTimeout = Duration(seconds: 30);

  /// How long to wait for the first connection after joining.
  static const connectTimeout = Duration(seconds: 40);

  /// Starts tracking [session] as this phone's call. If a call is already in
  /// progress, returns that one instead.
  static ActiveCall start({
    required CallSession session,
    required bool isOutgoing,
    required String coupleId,
    required String myUid,
    required String partnerName,
    required CallService calls,
    required ChatService chat,
    CallEngineFactory? engineFactory,
    OngoingCallNotification? notification,
  }) {
    final existing = current.value;
    if (existing != null && !existing.ended) return existing;
    final call = ActiveCall._(
      session: session,
      isOutgoing: isOutgoing,
      coupleId: coupleId,
      myUid: myUid,
      partnerName: partnerName,
      calls: calls,
      chat: chat,
      engineFactory: engineFactory ?? _defaultEngine,
      notification: notification ?? OngoingCallNotification.instance,
    );
    current.value = call;
    call._begin();
    return call;
  }

  final CallSession session;

  /// True when this phone placed the call.
  final bool isOutgoing;
  final String coupleId;
  final String myUid;
  final String partnerName;

  final CallService calls;
  final ChatService chat;
  final OngoingCallNotification notification;

  late final WebRtcCallEngine engine;

  StreamSubscription<CallSession?>? _callSub;
  Timer? _ticker;
  Timer? _ringTimer;
  Timer? _lostTimer;

  Duration elapsed = Duration.zero;
  bool joining = false;
  bool hasJoined = false;
  String? error;

  /// When the call connected, for the timer and the call log.
  DateTime? acceptedAt;

  /// How the call ended, as last seen on the call document.
  CallStatus? _finalStatus;

  /// Set once the call is over; [endMessage] says why, when worth saying.
  bool ended = false;
  String? endMessage;

  bool _logged = false;

  /// True while the full-screen call view is showing (the bar hides then).
  bool get screenOpen => _screens > 0;
  int _screens = 0;

  void screenShown() {
    _screens++;
    _notify();
  }

  void screenHidden() {
    _screens = _screens > 0 ? _screens - 1 : 0;
    _notify();
  }

  bool get isVideo => session.isVideo;

  bool get connected => engine.remoteConnected;

  void _notify() {
    if (!_disposedListeners) notifyListeners();
  }

  bool _disposedListeners = false;

  void _begin() {
    engine.addListener(_onEngineChanged);
    _callSub = calls.watchCall(coupleId).listen(_onSession);
    if (session.isActive) {
      // The callee accepted before this call was tracked: connect now.
      _onAccepted();
    } else if (isOutgoing) {
      // The caller waits for the answer, but not forever.
      _ringTimer = Timer(CallSession.ringTimeout, _onRingTimeout);
    }
  }

  void _onSession(CallSession? s) {
    if (ended) return;
    // The other side hung up or declined, it rang out, or the document was
    // replaced by a newer call.
    if (s == null || s.channelName != session.channelName || s.isFinished) {
      _finalStatus = s?.channelName == session.channelName ? s?.status : null;
      _finish(
        message: switch (_finalStatus) {
          CallStatus.declined => '$partnerName declined',
          CallStatus.missed when isOutgoing && acceptedAt == null =>
            'No answer',
          _ => null,
        },
      );
      return;
    }
    if (s.isActive && !hasJoined && !joining) _onAccepted();
  }

  void _onAccepted() {
    _ringTimer?.cancel();
    acceptedAt ??= DateTime.now();
    _startTicker();
    unawaited(_connect());
  }

  Future<void> _onRingTimeout() async {
    if (acceptedAt != null || ended) return;
    try {
      // The call-document listener finishes the call once this lands.
      await calls.markMissed(coupleId);
    } catch (_) {
      _finalStatus = CallStatus.missed;
      _finish(message: 'No answer');
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    final from = acceptedAt ?? DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final e = DateTime.now().difference(from);
      elapsed = e.isNegative ? Duration.zero : e;
      _notify();
    });
  }

  Future<void> _connect() async {
    if (joining || hasJoined || ended) return;
    joining = true;
    _notify();
    try {
      await engine.join();
      if (ended) return;
      hasJoined = true;
      // Keeps the microphone/camera and the app alive in the background.
      unawaited(notification.start(partnerName: partnerName, video: isVideo));
      _watchConnection();
    } on CallSetupException catch (e) {
      if (ended) return;
      error = e.message;
      _finish(message: e.message, tellServer: true);
    } catch (_) {
      if (ended) return;
      error = 'Could not connect the call.';
      _finish(message: 'Could not connect the call.', tellServer: true);
    } finally {
      joining = false;
      _notify();
    }
  }

  void _onEngineChanged() {
    _watchConnection();
    _notify();
  }

  /// Ends the call if the phones can't connect, or lose each other and
  /// don't recover, so neither side is left on "Reconnecting…" forever.
  void _watchConnection() {
    if (ended || !hasJoined) return;
    if (engine.remoteConnected) {
      _lostTimer?.cancel();
      _lostTimer = null;
      return;
    }
    if (_lostTimer != null) return;
    final wasConnected = engine.partnerHasJoined;
    _lostTimer = Timer(wasConnected ? lostTimeout : connectTimeout, () async {
      _lostTimer = null;
      if (ended || engine.remoteConnected) return;
      _finalStatus ??= CallStatus.ended;
      _finish(
        message: wasConnected ? 'Call lost' : 'Could not connect the call.',
        tellServer: true,
      );
    });
  }

  /// The red button.
  Future<void> hangUp() async {
    if (ended) return;
    _finalStatus ??= CallStatus.ended;
    _finish(tellServer: true);
    await _ending;
  }

  Future<void> _endOnServer() async {
    try {
      await calls.endCall(coupleId);
    } catch (_) {
      // End locally even if the network write failed.
    }
  }

  Future<void>? _ending;

  /// Ends the call on this phone at once; with [tellServer], also marks it
  /// ended on the server so the partner's phone closes too.
  void _finish({String? message, bool tellServer = false}) {
    if (ended) return;
    ended = true;
    if (tellServer) _ending = _endOnServer();
    endMessage = message;
    _ticker?.cancel();
    _ringTimer?.cancel();
    _lostTimer?.cancel();
    unawaited(_callSub?.cancel());
    _logCall();
    unawaited(notification.stop());
    engine.removeListener(_onEngineChanged);
    engine.dispose();
    if (current.value == this) current.value = null;
    _notify();
  }

  /// The caller records the call in the chat once, however it ended.
  void _logCall() {
    if (!isOutgoing || _logged) return;
    _logged = true;
    final at = acceptedAt;
    final CallOutcome outcome;
    if (at != null) {
      outcome = CallOutcome.completed;
    } else if (_finalStatus == CallStatus.declined) {
      outcome = CallOutcome.declined;
    } else {
      outcome = CallOutcome.missed;
    }
    chat
        .logCall(
          coupleId: coupleId,
          callerId: myUid,
          video: isVideo,
          outcome: outcome,
          talkTime: at == null ? null : DateTime.now().difference(at),
        )
        .catchError((Object _) {});
  }

  /// What the status pill says.
  String get statusLabel {
    if (error != null) return 'Call failed';
    if (!hasJoined) {
      return isOutgoing && acceptedAt == null ? 'Ringing…' : 'Connecting…';
    }
    if (!engine.remoteConnected) {
      return engine.partnerHasJoined ? 'Reconnecting…' : 'Connecting…';
    }
    return formatDuration(elapsed);
  }

  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _disposedListeners = true;
    super.dispose();
  }
}
