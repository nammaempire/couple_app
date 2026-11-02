import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/invite.dart';
import 'package:couple_app/features/home/data/daily_question_service.dart';
import 'package:couple_app/features/home/models/daily_question.dart';
import 'package:flutter_test/flutter_test.dart';

StorageService _noStorage() => StorageService(
  files: Files(
    ApiClient(
      baseUrl: 'http://localhost',
      token: ({bool forceRefresh = false}) async => null,
    ),
  ),
);

void main() {
  late MemoryBackend backend;
  late Db db;

  setUp(() {
    backend = MemoryBackend();
    db = Db(backend);
  });

  group('daily question', () {
    test('moves to the next day\'s question at midnight', () async {
      var now = DateTime(2026, 11, 2, 23, 59, 30);
      final service = DailyQuestionService(
        db: db,
        clock: () => now,
        dayCheckInterval: const Duration(milliseconds: 10),
      );
      final seen = <String>[];
      final sub = service.watchToday('c1').listen((e) => seen.add(e.dateKey));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.last, '2026-11-02');

      now = DateTime(2026, 11, 3, 0, 0, 30);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.last, '2026-11-03');
      await sub.cancel();
    });

    test('an answer goes to the question that was shown', () async {
      var now = DateTime(2026, 11, 2, 23, 59);
      final service = DailyQuestionService(db: db, clock: () => now);
      const shown = DailyQuestionEntry(
        dateKey: '2026-11-02',
        prompt: 'What made you smile today?',
      );
      // Typed before midnight, sent after.
      now = DateTime(2026, 11, 3, 0, 1);
      await service.answer(
        coupleId: 'c1',
        uid: 'ann',
        text: ' Your voice note ',
        entry: shown,
      );
      final doc = await db.doc('couples/c1/dailyQuestions/2026-11-02').get();
      expect(doc.data()?['prompt'], shown.prompt);
      expect((doc.data()?['answers'] as Map)['ann']['text'], 'Your voice note');
      expect(
        (await db.doc('couples/c1/dailyQuestions/2026-11-03').get()).exists,
        isFalse,
      );
    });
  });

  group('calls: one at a time', () {
    test(
      'a ringing or answered call blocks a new one; an old one does not',
      () {
        final now = DateTime(2026, 11, 2, 12);
        CallSession call(CallStatus status, Duration ago) => CallSession(
          callerId: 'ann',
          calleeId: 'bob',
          type: CallType.voice,
          status: status,
          channelName: 'x',
          startedAt: now.subtract(ago),
        );
        expect(
          CallService.isBusy(
            call(CallStatus.ringing, const Duration(seconds: 10)),
            now: now,
          ),
          isTrue,
        );
        expect(
          CallService.isBusy(
            call(CallStatus.ringing, const Duration(minutes: 2)),
            now: now,
          ),
          isFalse,
        );
        expect(
          CallService.isBusy(
            call(CallStatus.accepted, const Duration(minutes: 30)),
            now: now,
          ),
          isTrue,
        );
        expect(
          CallService.isBusy(
            call(CallStatus.ended, const Duration(seconds: 5)),
            now: now,
          ),
          isFalse,
        );
      },
    );

    test('calling while the partner is calling you is refused', () async {
      final calls = CallService(db: db);
      await calls.startCall(
        coupleId: 'c1',
        callerId: 'ann',
        calleeId: 'bob',
        type: CallType.voice,
      );
      await expectLater(
        calls.startCall(
          coupleId: 'c1',
          callerId: 'bob',
          calleeId: 'ann',
          type: CallType.video,
        ),
        throwsA(
          isA<CallBusyException>().having((e) => e.incoming, 'incoming', true),
        ),
      );
      // Once it's over, a new call goes through.
      await calls.endCall('c1');
      await calls.startCall(
        coupleId: 'c1',
        callerId: 'bob',
        calleeId: 'ann',
        type: CallType.video,
      );
    });
  });

  group('invite codes', () {
    test(
      'expire after a week; opening the invite renews the same code',
      () async {
        final couples = (service: CoupleService(db: db));
        await db.doc('users/ann').set({'displayName': 'Ann'});
        backend.clock = DateTime.now().subtract(const Duration(days: 8));
        final couple = await couples.service.createCouple(
          'ann',
          inviterName: 'Ann',
        );
        backend.clock = null;

        await expectLater(
          couples.service.lookupInvite(uid: 'bob', code: couple.inviteCode),
          throwsA(
            isA<PairingException>().having(
              (e) => e.message,
              'message',
              contains('expired'),
            ),
          ),
        );

        await couples.service.ensureInvite(
          couple: couple,
          uid: 'ann',
          inviterName: 'Ann',
        );
        final invite = await couples.service.lookupInvite(
          uid: 'bob',
          code: couple.inviteCode,
        );
        expect(invite.coupleId, couple.id);
        expect(invite.isExpired(DateTime.now()), isFalse);
      },
    );

    test('expiry and renewal times', () {
      final made = DateTime(2026, 11, 1);
      final invite = Invite(
        code: 'ABC234',
        coupleId: 'c1',
        createdBy: 'ann',
        inviterName: 'Ann',
        createdAt: made,
      );
      expect(invite.isExpired(made.add(const Duration(days: 6))), isFalse);
      expect(invite.needsRenewal(made.add(const Duration(days: 6))), isTrue);
      expect(invite.isExpired(made.add(Invite.lifetime)), isTrue);
      expect(
        const Invite(
          code: 'ABC234',
          coupleId: 'c1',
          createdBy: 'ann',
          inviterName: 'Ann',
        ).isExpired(made),
        isTrue,
        reason: 'older invites without a time count as expired',
      );
    });
  });

  test('the chat gallery loads photos and videos a page at a time', () async {
    final chat = ChatService(db: db, storage: _noStorage());
    final start = DateTime.utc(2026, 1, 1);
    for (var i = 0; i < 70; i++) {
      backend.clock = start.add(Duration(minutes: i));
      await db.doc('couples/c1/messages/m$i').set({
        'senderId': 'ann',
        'type': i.isEven ? 'image' : 'video',
        'imageUrl': 'https://x/$i.jpg',
        'sentAt': FieldValue.serverTimestamp(),
      });
      // Text in between is skipped.
      await db.doc('couples/c1/messages/t$i').set({
        'senderId': 'bob',
        'type': 'text',
        'text': 'hi',
        'sentAt': FieldValue.serverTimestamp(),
      });
    }
    final first = await chat.fetchMedia('c1');
    expect(first, hasLength(ChatService.mediaPageSize));
    expect(first.first.id, 'm69');
    final rest = await chat.fetchMedia('c1', before: first.last.sentAt);
    expect(rest, hasLength(10));
    expect(rest.last.id, 'm0');
    expect({
      ...first.map((m) => m.id),
      ...rest.map((m) => m.id),
    }, hasLength(70));

    // "Clear chat" hides what came before it.
    final cleared = await chat.fetchMedia(
      'c1',
      clearedAt: start.add(const Duration(minutes: 59, seconds: 30)),
    );
    expect(cleared.map((m) => m.id), [for (var i = 69; i >= 60; i--) 'm$i']);
  });
}
