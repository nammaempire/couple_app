import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/features/calls/data/active_call.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/data/ongoing_call_notification.dart';
import 'package:couple_app/features/calls/data/webrtc_call_engine.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// WebRTC stand-in: "joins" at once and lets the test drive the connection.
class FakeEngine extends WebRtcCallEngine {
  FakeEngine({
    required super.coupleId,
    required super.callId,
    required super.myUid,
    required super.partnerUid,
    required super.isCaller,
    required super.video,
  });

  int joins = 0;
  bool disposed = false;

  @override
  Future<void> join() async {
    joins++;
  }

  void setConnected(bool value) {
    remoteConnected = value;
    if (value) partnerHasJoined = true;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    // Nothing was opened (join is faked), so the real teardown is a no-op.
    super.dispose();
  }
}

class FakeNotification extends OngoingCallNotification {
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> start({required String partnerName, required bool video}) async {
    starts++;
    return true;
  }

  @override
  Future<void> stop() async => stops++;
}

StorageService _noStorage() => StorageService(
  files: Files(
    ApiClient(
      baseUrl: 'http://localhost',
      token: ({bool forceRefresh = false}) async => null,
    ),
  ),
);

void main() {
  late Db db;
  late CallService calls;
  late ChatService chat;
  late FakeNotification notification;
  FakeEngine? engine;

  WebRtcCallEngine factory({
    required String coupleId,
    required String callId,
    required String myUid,
    required String partnerUid,
    required bool isCaller,
    required bool video,
  }) => engine = FakeEngine(
    coupleId: coupleId,
    callId: callId,
    myUid: myUid,
    partnerUid: partnerUid,
    isCaller: isCaller,
    video: video,
  );

  setUp(() {
    db = Db(MemoryBackend());
    calls = CallService(db: db);
    chat = ChatService(db: db, storage: _noStorage());
    notification = FakeNotification();
    engine = null;
    ActiveCall.current.value = null;
  });

  ActiveCall startOutgoing(CallSession session) => ActiveCall.start(
    session: session,
    isOutgoing: true,
    coupleId: 'c1',
    myUid: 'ann',
    partnerName: 'Bob',
    calls: calls,
    chat: chat,
    engineFactory: factory,
    notification: notification,
  );

  Future<CallSession> ring() => calls.startCall(
    coupleId: 'c1',
    callerId: 'ann',
    calleeId: 'bob',
    type: CallType.video,
  );

  testWidgets('the call keeps going without its screen, until hang-up', (
    tester,
  ) async {
    final ActiveCall call;
    call = startOutgoing(await ring());
    await tester.pump();
    expect(ActiveCall.current.value, same(call));
    expect(call.statusLabel, 'Ringing…');

    // Bob answers on his phone.
    await calls.acceptCall('c1');
    await tester.pump();
    expect(engine!.joins, 1);
    expect(call.hasJoined, isTrue);
    expect(notification.starts, 1, reason: 'ongoing-call notification');

    engine!.setConnected(true);
    // The screen opens and closes (back button): the call carries on.
    call.screenShown();
    call.screenHidden();
    await tester.pump(const Duration(minutes: 3));
    expect(call.ended, isFalse);
    expect(ActiveCall.current.value, same(call));

    await call.hangUp();
    await tester.pump();
    expect(call.ended, isTrue);
    expect(ActiveCall.current.value, isNull);
    expect(engine!.disposed, isTrue);
    expect(notification.stops, 1);
  });

  testWidgets('the partner hanging up ends it on this phone too', (
    tester,
  ) async {
    final ActiveCall call;
    call = startOutgoing(await ring());
    await tester.pump();
    await calls.acceptCall('c1');
    await tester.pump();
    engine!.setConnected(true);

    await calls.endCall('c1');
    await tester.pump();
    expect(call.ended, isTrue);
    expect(ActiveCall.current.value, isNull);
  });

  testWidgets('a declined call says so', (tester) async {
    final ActiveCall call;
    call = startOutgoing(await ring());
    await tester.pump();
    await calls.declineCall('c1');
    await tester.pump();
    expect(call.ended, isTrue);
    expect(call.endMessage, 'Bob declined');
    expect(engine!.joins, 0);
  });

  testWidgets('a short network drop recovers; a long one ends the call', (
    tester,
  ) async {
    final ActiveCall call;
    call = startOutgoing(await ring());
    await tester.pump();
    await calls.acceptCall('c1');
    await tester.pump();
    engine!.setConnected(true);

    // Lift or tunnel: back within the limit.
    engine!.setConnected(false);
    expect(call.statusLabel, 'Reconnecting…');
    await tester.pump(const Duration(seconds: 20));
    engine!.setConnected(true);
    await tester.pump(const Duration(seconds: 30));
    expect(call.ended, isFalse);

    // Gone for good (the other phone was switched off).
    engine!.setConnected(false);
    await tester.pump(ActiveCall.lostTimeout + const Duration(seconds: 1));
    expect(call.ended, isTrue);
    expect(call.endMessage, 'Call lost');
    expect(notification.stops, 1);
  });

  testWidgets('only one call at a time', (tester) async {
    final ActiveCall first;
    first = startOutgoing(await ring());
    await tester.pump();
    final again = startOutgoing(
      CallSession(
        callerId: 'ann',
        calleeId: 'bob',
        type: CallType.voice,
        status: CallStatus.ringing,
        channelName: 'other',
        startedAt: DateTime.now(),
      ),
    );
    expect(again, same(first));
    await first.hangUp();
    await tester.pump();
  });
}
