import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/features/calls/data/active_call.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/calls/widgets/ongoing_call_bar.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/home/models/love_tap.dart';
import 'package:couple_app/features/home/widgets/love_burst.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'active_call_test.dart' show FakeEngine, FakeNotification;

StorageService _noStorage() => StorageService(
  files: Files(
    ApiClient(
      baseUrl: 'http://localhost',
      token: ({bool forceRefresh = false}) async => null,
    ),
  ),
);

void main() {
  testWidgets(
    'the return-to-call bar works above the navigator (no tooltip crash)',
    (tester) async {
      final db = Db(MemoryBackend());
      final calls = CallService(db: db);
      final session = await calls.startCall(
        coupleId: 'c1',
        callerId: 'ann',
        calleeId: 'bob',
        type: CallType.video,
      );
      final call = ActiveCall.start(
        session: session,
        isOutgoing: true,
        coupleId: 'c1',
        myUid: 'ann',
        partnerName: 'Bob',
        calls: calls,
        chat: ChatService(db: db, storage: _noStorage()),
        engineFactory:
            ({
              required coupleId,
              required callId,
              required myUid,
              required partnerUid,
              required isCaller,
              required video,
            }) => FakeEngine(
              coupleId: coupleId,
              callId: callId,
              myUid: myUid,
              partnerUid: partnerUid,
              isCaller: isCaller,
              video: video,
            ),
        notification: FakeNotification(),
      );

      // Exactly how app.dart places it: in MaterialApp.builder, above the
      // navigator and its Overlay.
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => OngoingCallOverlay(child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Tap to return to call'), findsOneWidget);

      // Long-press used to open the tooltip; tapping hangs up.
      await tester.longPress(find.byKey(const Key('ongoing-call-hang-up')));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('ongoing-call-hang-up')));
      await tester.pump();
      expect(call.ended, isTrue);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('the love burst emoji has a normal text style (no yellow bar)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('home'))),
    );
    // The root overlay, as the app uses (outside any Scaffold/Material).
    LoveBurst.play(
      LoveTap.love,
      overlay: tester.state<OverlayState>(find.byType(Overlay).first),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final emoji = find.text('❤️');
    expect(emoji, findsOneWidget);
    final style = DefaultTextStyle.of(tester.element(emoji)).style;
    expect(
      style.decoration,
      isNot(TextDecoration.underline),
      reason: 'Flutter\'s missing-Material style is a yellow double underline',
    );
    expect(style.decorationColor, isNot(const Color(0xFFFFFF00)));
    await tester.pump(LoveBurst.duration);
    await tester.pump();
  });
}
