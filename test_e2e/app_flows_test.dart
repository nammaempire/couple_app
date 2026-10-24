// The app's real services against the real Us server and its rules.
// See support/harness.dart for how to start the server.
@Timeout(Duration(minutes: 5))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/data/phone_number_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/data/pair_request_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/models/pair_request.dart';
import 'package:couple_app/features/calls/data/call_service.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/home/data/daily_question_service.dart';
import 'package:couple_app/features/home/data/mood_service.dart';
import 'package:couple_app/features/home/data/nudge_service.dart';
import 'package:couple_app/features/home/models/love_tap.dart';
import 'package:couple_app/features/home/models/mood.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/together/data/event_service.dart';
import 'package:couple_app/features/together/data/love_note_service.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/plans/data/bucket_list_service.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/plans/data/expense_service.dart';
import 'package:couple_app/features/plans/data/place_service.dart';
import 'package:couple_app/features/plans/data/wishlist_service.dart';
import 'package:couple_app/features/plans/models/bucket_item.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/expense.dart';
import 'package:couple_app/features/plans/models/place.dart';
import 'package:couple_app/features/plans/models/wishlist_item.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/models/listening_session.dart';
import 'package:couple_app/features/music/models/song.dart';
import 'package:couple_app/features/music/models/song_link.dart';
import 'package:couple_app/features/play/board/tic_tac_toe_logic.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/know_me/know_me_logic.dart';
import 'package:couple_app/features/play/know_me/know_me_service.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/avatar/data/avatar_service.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/books/data/book_service.dart';
import 'package:couple_app/features/chat/data/chat_look_service.dart';
import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/couple/data/end_pairing_gateway.dart';
import 'package:couple_app/features/couple/data/separation_service.dart';
import 'package:couple_app/features/couple/models/separation.dart';
import 'package:couple_app/features/premium/data/gift_service.dart';
import 'package:couple_app/features/security/data/device_trust_service.dart';
import 'package:couple_app/features/security/models/device_check.dart';
import 'package:couple_app/features/security/models/known_device.dart';
import 'package:couple_app/features/security/models/security_event.dart';
import 'package:couple_app/features/vault/data/device_keystore.dart';
import 'package:couple_app/features/vault/data/vault_crypto.dart';
import 'package:couple_app/features/vault/data/vault_service.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';

import 'support/harness.dart';

void main() {
  late Phone alice;
  late Phone bob;
  late String coupleId;

  setUpAll(() async {
    alice = Phone(
      uid: 'alice_$runId',
      name: 'Alice',
      phoneNumber: '+9198765${runId.hashCode.abs() % 100000}'.padRight(13, '1'),
      email: 'alice_$runId@example.com',
    );
    bob = Phone(
      uid: 'bob_$runId',
      name: 'Bob',
      phoneNumber: '+9181234${runId.hashCode.abs() % 100000}'.padRight(13, '2'),
      email: 'bob_$runId@example.com',
    );
  });

  tearDownAll(() async {
    await alice.close();
    await bob.close();
  });

  Future<AppUser> profile(Phone p, [String? uid]) async {
    final snap = await p.db.collection('users').doc(uid ?? p.uid).get();
    return AppUser.fromDoc(snap);
  }

  Future<Couple> couple(Phone p) async =>
      Couple.fromDoc(await p.db.collection('couples').doc(coupleId).get());

  group('sign-up and pairing', () {
    test('first sign-in creates the profile; onboarding saves it', () async {
      for (final p in [alice, bob]) {
        final auth = AuthService(auth: p.auth, db: p.db);
        expect(await auth.ensureProfile(), p.uid);
        // A second call leaves it alone.
        await auth.ensureProfile();
        await auth.saveProfile(
          displayName: p.name,
          nickname: '${p.name}y',
          birthday: DateTime(1995, 3, 14),
        );
        await auth.saveNotificationPrefs(const NotificationPrefs());
        await auth.markPrivacyReviewed();
        await auth.confirmAdult();
        final me = await profile(p);
        expect(me.displayName, p.name);
        expect(me.profileComplete, isTrue);
        expect(me.coupleId, isNull);
      }
    });

    test('verified phone number is saved and indexed', () async {
      for (final p in [alice, bob]) {
        await PhoneNumberService(db: p.db)
            .saveVerifiedPhone(uid: p.uid, e164: p.phoneNumber!);
      }
      expect(
        await PhoneNumberService(db: alice.db).lookup(bob.phoneNumber!),
        bob.uid,
      );
      // Someone else's number can't be claimed.
      await expectDenied(
        () => PhoneNumberService(db: alice.db)
            .saveVerifiedPhone(uid: alice.uid, e164: bob.phoneNumber!),
      );
    });

    test('pair by number: request, then accept joins the couple', () async {
      final me = await profile(alice);
      final requests = PairRequestService(db: alice.db);
      final out = await requests.requestByNumber(
        me: me,
        toPhone: bob.phoneNumber!,
      );
      expect(out, isA<PairByNumberSent>());

      final aliceNow = await profile(alice);
      expect(aliceNow.coupleId, isNotNull);

      // Bob sees it live and declines it (then Alice asks again below).
      final bobRequests = PairRequestService(db: bob.db);
      final incoming = await firstWhere(
        bobRequests.watchIncoming(bob.uid),
        (l) => l.isNotEmpty,
      );
      expect(incoming.single.fromUid, alice.uid);
      await bobRequests.decline(incoming.single);

      // Alice cancels her waiting couple; pairing by code follows.
      final waiting = Couple.fromDoc(
        await alice.db.collection('couples').doc(aliceNow.coupleId).get(),
      );
      await CoupleService(db: alice.db)
          .cancelWaitingCouple(uid: alice.uid, couple: waiting);
      expect((await profile(alice)).coupleId, isNull);
    });

    test('create a couple, look up the invite, join by code', () async {
      final service = CoupleService(db: alice.db);
      final created = await service.createCouple(
        alice.uid,
        inviterName: 'Alice',
        coupleName: 'A & B',
        startDate: DateTime(2024, 2, 14),
      );
      coupleId = created.id;
      await service.ensureInvite(
        couple: created,
        uid: alice.uid,
        inviterName: 'Alice',
      );

      // Alice can't join her own invite.
      final bobCouples = CoupleService(db: bob.db);
      await expectLater(
        CoupleService(db: alice.db)
            .lookupInvite(uid: alice.uid, code: created.inviteCode),
        throwsA(isA<PairingException>()),
      );
      final invite =
          await bobCouples.lookupInvite(uid: bob.uid, code: created.inviteCode);
      expect(invite.coupleId, coupleId);
      await bobCouples.acceptInvite(uid: bob.uid, invite: invite);

      final c = await couple(bob);
      expect(c.memberIds, [alice.uid, bob.uid]);
      expect((await profile(bob)).coupleId, coupleId);
      // Partners can read each other's profile now.
      expect((await profile(alice, bob.uid)).displayName, 'Bob');
    });

    test('pair by number with an existing pending request', () async {
      // A third person asks Bob; Bob is already paired so accepting fails
      // with "already paired" (said only to him).
      final carol = Phone(
        uid: 'carol_$runId',
        name: 'Carol',
        phoneNumber: '+9170000${runId.hashCode.abs() % 100000}'.padRight(13, '3'),
      );
      addTearDown(carol.close);
      await AuthService(auth: carol.auth, db: carol.db).ensureProfile();
      final carolRequests = PairRequestService(db: carol.db);
      final out = await carolRequests.requestByNumber(
        me: await profile(carol),
        toPhone: bob.phoneNumber!,
      );
      expect(out, isA<PairByNumberSent>());
      final req = PairRequest.fromDoc(
        await bob.db
            .collection('pairRequests')
            .doc((out as PairByNumberSent).requestId)
            .get(),
      );
      await expectLater(
        PairRequestService(db: bob.db).accept(
          uid: bob.uid,
          request: req,
          myCouple: await couple(bob),
        ),
        throwsA(isA<PairingException>()),
      );
      await carolRequests.cancel(req);
      await carolRequests.dismiss(req);
    });

    test('couple details: name, dates, nickname, currency', () async {
      final s = CoupleService(db: bob.db);
      await s.setCoupleName(coupleId: coupleId, name: 'Us two');
      await s.setStartDate(coupleId: coupleId, date: DateTime(2023, 6, 1));
      await s.setNextMeetup(coupleId: coupleId, date: DateTime(2026, 12, 24));
      await s.setCurrency(coupleId: coupleId, currency: 'INR');
      await s.setPartnerNickname(
        coupleId: coupleId,
        uid: bob.uid,
        nickname: 'Ally',
      );
      await s.setPartnerNickname(
        coupleId: coupleId,
        uid: alice.uid,
        nickname: 'Bobby',
      );
      await s.setPartnerNickname(coupleId: coupleId, uid: alice.uid, nickname: null);
      final c = await couple(alice);
      expect(c.coupleName, 'Us two');
      expect(c.nicknames, {bob.uid: 'Ally'});
    });
  });

  group('chat', () {
    late ChatService aliceChat;
    late ChatService bobChat;

    setUpAll(() {
      aliceChat = ChatService(
        db: alice.db,
        storage: StorageService(files: alice.files),
      );
      bobChat = ChatService(db: bob.db, storage: StorageService(files: bob.files));
    });

    Future<List<Message>> messages(Phone p) async {
      final snap = await p.db
          .collection('couples')
          .doc(coupleId)
          .collection('messages')
          .orderBy('sentAt', descending: true)
          .get();
      return snap.docs.map(Message.fromDoc).toList();
    }

    test('bob sees alice\'s message live', () async {
      final live = bobChat.watchMessagePage(coupleId);
      final seen = firstWhere(
        live,
        (p) => p.messages.any((m) => m.text == 'Hi Bob!'),
      );
      // Let the subscription settle, then send.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await aliceChat.sendText(
        coupleId: coupleId,
        senderId: alice.uid,
        text: 'Hi Bob!',
      );
      final page = await seen;
      expect(page.messages.first.senderId, alice.uid);
      expect((await couple(bob)).toString(), isNotEmpty);
    });

    test('text, sticker, reply, seen, reaction, pin, delete', () async {
      final first = (await messages(bob)).first;
      await bobChat.sendText(
        coupleId: coupleId,
        senderId: bob.uid,
        text: 'Hey!',
        replyTo: ReplyPreview(
          messageId: first.id,
          senderId: first.senderId,
          type: first.type,
          text: first.text,
        ),
      );
      await bobChat.sendSticker(
        coupleId: coupleId,
        senderId: bob.uid,
        stickerId: 'hug',
        category: 'love',
        quote: 'Always yours',
      );
      await aliceChat.markSeen(coupleId: coupleId, partnerId: bob.uid);
      await bobChat.markSeen(coupleId: coupleId, partnerId: alice.uid);

      var list = await messages(alice);
      final hey = list.firstWhere((m) => m.text == 'Hey!');
      expect(hey.seen, isTrue);
      expect(hey.replyTo?.messageId, first.id);

      await aliceChat.toggleReaction(
        coupleId: coupleId,
        message: hey,
        uid: alice.uid,
        emoji: '❤️',
      );
      await aliceChat.setPinned(coupleId: coupleId, message: hey, pinned: true);
      list = await messages(bob);
      final reacted = list.firstWhere((m) => m.id == hey.id);
      expect(reacted.reactions, {alice.uid: '❤️'});
      expect(reacted.pinned, isTrue);
      final pinned = await firstWhere(
        bobChat.watchPinned(coupleId),
        (l) => l.isNotEmpty,
      );
      expect(pinned.single.id, hey.id);

      // Toggle off and unpin.
      await aliceChat.toggleReaction(
        coupleId: coupleId,
        message: reacted,
        uid: alice.uid,
        emoji: '❤️',
      );
      await aliceChat.setPinned(
        coupleId: coupleId,
        message: reacted,
        pinned: false,
      );

      // Alice can't delete Bob's message; Bob can.
      await expectDenied(
        () => aliceChat.deleteMessage(coupleId: coupleId, message: hey),
      );
      await bobChat.deleteMessage(coupleId: coupleId, message: hey);
      expect((await messages(alice)).any((m) => m.id == hey.id), isFalse);

      final recent = await aliceChat.fetchRecent(coupleId);
      expect(recent.map((m) => m.text), contains('Always yours'));
    });

    test('image message uploads through StorageService', () async {
      final file = await tempFile('pic.png', onePixelPng);
      await aliceChat.sendImage(
        coupleId: coupleId,
        senderId: alice.uid,
        file: file,
      );
      final media = await bobChat.fetchMedia(coupleId);
      expect(media, hasLength(1));
      final url = media.single.imageUrl!;
      // Bob can read the file through the server.
      final bytes = await bob.files.refFromURL(url).getData();
      expect(bytes, Uint8List.fromList(onePixelPng));
      // Voice message (audio/mp4) through the same service.
      final voice = await tempFile('note.m4a', List.filled(64, 7));
      await bobChat.sendVoice(
        coupleId: coupleId,
        senderId: bob.uid,
        file: voice,
        duration: const Duration(seconds: 3),
      );
      // A text file can't go where photos go.
      await expectDenied(
        () => alice.files
            .ref('couples/$coupleId/photos/x.txt')
            .putData(
              Uint8List.fromList([1, 2, 3]),
              const FileMetadata(contentType: 'text/plain'),
            ),
      );
    });

    test('screenshots: alert and blocking switch', () async {
      await aliceChat.sendScreenshotAlert(
        coupleId: coupleId,
        senderId: alice.uid,
        senderName: 'Alice',
      );
      await bobChat.setScreenshotBlocking(
        coupleId: coupleId,
        senderId: bob.uid,
        senderName: 'Bob',
        blocked: true,
      );
      expect((await couple(alice)).blockScreenshots, isTrue);
    });

    test('clear for me, then clear for both', () async {
      await aliceChat.clearForMe(uid: alice.uid);
      expect((await profile(alice)).chatClearedAt, isNotNull);

      var deleted = 0;
      await bobChat.clearForBoth(
        coupleId: coupleId,
        senderId: bob.uid,
        senderName: 'Bob',
        onProgress: (n) => deleted = n,
      );
      expect(deleted, greaterThan(3));
      final left = await messages(alice);
      expect(left.map((m) => m.type), [MessageType.chatCleared]);
    });
  });

  group('calls and home', () {
    test('call signalling: ring, accept, end; decline; missed', () async {
      final aliceCalls = CallService(db: alice.db);
      final bobCalls = CallService(db: bob.db);
      final ringing = firstWhere(
        bobCalls.watchCall(coupleId),
        (c) => c?.status == CallStatus.ringing,
      );
      await aliceCalls.startCall(
        coupleId: coupleId,
        callerId: alice.uid,
        calleeId: bob.uid,
        type: CallType.video,
      );
      expect((await ringing)!.callerId, alice.uid);
      expect(await bobCalls.acceptCall(coupleId), isTrue);
      expect(await bobCalls.acceptCall(coupleId), isFalse);
      await aliceCalls.endCall(coupleId);

      await bobCalls.startCall(
        coupleId: coupleId,
        callerId: bob.uid,
        calleeId: alice.uid,
        type: CallType.voice,
      );
      await aliceCalls.declineCall(coupleId);
      await bobCalls.startCall(
        coupleId: coupleId,
        callerId: bob.uid,
        calleeId: alice.uid,
        type: CallType.voice,
      );
      await bobCalls.markMissed(coupleId);
      final last = await firstWhere(bobCalls.watchCall(coupleId), (_) => true);
      expect(last!.status, CallStatus.missed);
      // Overwriting `current` is an update, which either member may make;
      // a new call document must name its writer as the caller.
      await expectDenied(
        () => alice.db
            .collection('couples')
            .doc(coupleId)
            .collection('call')
            .doc('other')
            .set({'callerId': bob.uid, 'status': 'ringing'}),
      );
      await ChatService(db: bob.db, storage: StorageService(files: bob.files))
          .logCall(
            coupleId: coupleId,
            callerId: bob.uid,
            video: false,
            outcome: CallOutcome.missed,
          );
    });

    test('moods: each writes only their own', () async {
      await MoodService(db: alice.db).setMood(
        coupleId: coupleId,
        uid: alice.uid,
        mood: Mood.loved,
        note: ' missing you ',
      );
      await MoodService(db: bob.db).setMood(
        coupleId: coupleId,
        uid: bob.uid,
        mood: Mood.happy,
      );
      await expectDenied(
        () => MoodService(db: alice.db).setMood(
          coupleId: coupleId,
          uid: bob.uid,
          mood: Mood.tired,
        ),
      );
      final moods = await firstWhere(
        MoodService(db: bob.db).watchMoods(coupleId),
        (m) => m.length == 2,
      );
      expect(moods[alice.uid]!.mood, Mood.loved);
      expect(moods[alice.uid]!.note, 'missing you');
    });

    test('daily question: both answer, it unlocks', () async {
      await DailyQuestionService(db: alice.db)
          .answer(coupleId: coupleId, uid: alice.uid, text: 'Pizza');
      await DailyQuestionService(db: bob.db)
          .answer(coupleId: coupleId, uid: bob.uid, text: 'Dosa');
      final today = await firstWhere(
        DailyQuestionService(db: alice.db).watchToday(coupleId),
        (e) => e.isUnlocked,
      );
      expect(today.answers.keys, unorderedEquals([alice.uid, bob.uid]));
      final history = await firstWhere(
        DailyQuestionService(db: bob.db).watchHistory(coupleId),
        (h) => h.isNotEmpty,
      );
      expect(history.first.dateKey, today.dateKey);
    });

    test('nudges / love taps', () async {
      final latest = firstWhere(
        NudgeService(db: bob.db).watchLatest(coupleId),
        (n) => n?.senderId == alice.uid,
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await NudgeService(db: alice.db)
          .send(coupleId: coupleId, senderId: alice.uid, kind: LoveTap.hug);
      expect((await latest)!.kind, LoveTap.hug);
      await expectDenied(
        () => NudgeService(db: alice.db)
            .send(coupleId: coupleId, senderId: bob.uid),
      );
    });
  });

  group('memories, calendar, love notes', () {
    test('memory with a photo: create, edit, favourite, delete', () async {
      final service = MemoryService(db: alice.db, files: alice.files);
      final photo = await tempFile('beach.png', onePixelPng);
      await service.create(
        coupleId: coupleId,
        createdBy: alice.uid,
        title: 'Beach day',
        caption: 'Sunburnt',
        date: DateTime(2025, 5, 1),
        place: 'Goa',
        album: '',
        newMedia: [PendingMedia(file: photo, isVideo: false)],
      );
      final list = await firstWhere(
        MemoryService(db: bob.db, files: bob.files).watchMemories(coupleId),
        (l) => l.isNotEmpty,
      );
      final memory = list.single;
      expect(memory.media, hasLength(1));
      expect(
        await bob.files.refFromURL(memory.media.single.url).getData(),
        Uint8List.fromList(onePixelPng),
      );

      // Bob edits it (adds a photo, keeps the first); it stays Alice's.
      final bobService = MemoryService(db: bob.db, files: bob.files);
      final second = await tempFile('sunset.jpg', onePixelPng);
      await bobService.update(
        coupleId: coupleId,
        memory: memory,
        title: 'Beach day!',
        caption: 'Sunburnt',
        date: DateTime(2025, 5, 1),
        place: null,
        album: 'Trips',
        keptMedia: memory.media,
        newMedia: [PendingMedia(file: second, isVideo: false)],
      );
      await bobService.setFavorite(
        coupleId: coupleId,
        memoryId: memory.id,
        favorite: true,
      );
      final edited = await firstWhere(
        service.watchMemory(coupleId, memory.id),
        (m) => m != null && m.media.length == 2 && m.favorite,
      );
      expect(edited!.createdBy, alice.uid);
      await expectDenied(
        () => bobService.delete(coupleId: coupleId, memory: edited),
      );
      // A memory that stays, for the book below.
      await service.create(
        coupleId: coupleId,
        createdBy: alice.uid,
        title: 'First date',
        caption: '',
        date: DateTime(2023, 6, 1),
        place: null,
        album: '',
        newMedia: const [],
      );
      await service.delete(coupleId: coupleId, memory: edited);
    });

    test('calendar: shared and private events', () async {
      final aliceEvents = EventService(db: alice.db);
      await aliceEvents.save(
        coupleId: coupleId,
        event: CalendarEvent(
          id: '',
          title: 'Dinner',
          type: EventType.dateNight,
          start: DateTime(2026, 11, 14, 20),
          createdBy: alice.uid,
          allDay: false,
          location: 'Toit',
          budget: 2500,
          reminder: ReminderOption.hour,
        ),
      );
      await aliceEvents.save(
        coupleId: coupleId,
        event: CalendarEvent(
          id: '',
          title: 'Surprise planning',
          type: EventType.custom,
          start: DateTime(2026, 11, 10),
          createdBy: alice.uid,
          isPrivate: true,
        ),
      );
      final bobSees = await firstWhere(
        EventService(db: bob.db).watchEvents(coupleId, bob.uid),
        (l) => l.isNotEmpty,
      );
      expect(bobSees.map((e) => e.title), ['Dinner']);
      final aliceSees = await firstWhere(
        aliceEvents.watchEvents(coupleId, alice.uid),
        (l) => l.length == 2,
      );
      // Bob edits the shared one.
      final dinner = bobSees.single;
      await EventService(db: bob.db).save(
        coupleId: coupleId,
        event: CalendarEvent(
          id: dinner.id,
          title: 'Dinner at Toit',
          type: dinner.type,
          start: dinner.start,
          createdBy: dinner.createdBy,
          allDay: false,
          budget: 3000.5,
        ),
      );
      final private = aliceSees.firstWhere((e) => e.isPrivate);
      await expectDenied(
        () => EventService(db: bob.db)
            .delete(coupleId: coupleId, eventId: private.id),
      );
      await aliceEvents.delete(coupleId: coupleId, eventId: private.id);
    });

    test('love notes: letter now, sealed later, voice letter', () async {
      final aliceNotes = LoveNoteService(db: alice.db, files: alice.files);
      final bobNotes = LoveNoteService(db: bob.db, files: bob.files);
      await aliceNotes.send(
        coupleId: coupleId,
        senderId: alice.uid,
        recipientId: bob.uid,
        kind: NoteKind.letter,
        title: 'For you',
        body: 'You make me happy',
        deliverAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await aliceNotes.send(
        coupleId: coupleId,
        senderId: alice.uid,
        recipientId: bob.uid,
        kind: NoteKind.openWhen,
        openWhen: OpenWhen.badDay,
        title: 'Later',
        body: 'Not yet',
        deliverAt: DateTime.now().add(const Duration(days: 3)),
      );
      final voice = await tempFile('letter.m4a', List.filled(128, 3));
      await aliceNotes.send(
        coupleId: coupleId,
        senderId: alice.uid,
        recipientId: bob.uid,
        kind: NoteKind.letter,
        title: 'Listen',
        body: '',
        deliverAt: DateTime.now().subtract(const Duration(seconds: 5)),
        voiceFile: voice,
        voiceDuration: const Duration(seconds: 4),
      );

      final notes = await firstWhere(
        bobNotes.watchNotes(coupleId),
        (l) => l.length == 3,
      );
      final now = notes.firstWhere((n) => n.title == 'For you');
      final later = notes.firstWhere((n) => n.title == 'Later');
      final listen = notes.firstWhere((n) => n.title == 'Listen');

      final content = await bobNotes.open(coupleId: coupleId, note: now);
      expect(content.body, 'You make me happy');
      await bobNotes.markOpened(coupleId: coupleId, note: now);
      await expectLater(
        bobNotes.open(coupleId: coupleId, note: later),
        throwsA(isA<NoteSealedException>()),
      );
      // Too early to mark opened, and the sender reads her own words.
      await expectDenied(() => bobNotes.markOpened(coupleId: coupleId, note: later));
      expect(
        (await aliceNotes.open(coupleId: coupleId, note: later)).body,
        'Not yet',
      );

      // The voice file: only the sender may read it directly; the
      // recipient plays it through the link in the sealed content.
      final voiceUrl =
          (await bobNotes.open(coupleId: coupleId, note: listen)).voiceUrl!;
      final path = bob.files.refFromURL(voiceUrl).fullPath;
      expect(listen.hasVoice, isTrue);
      await expectDenied(() => bob.files.ref(path).getDownloadURL());
      expect(await alice.files.ref(path).getDownloadURL(), isNotEmpty);
      // The player streams the signed link itself, as with Firebase's
      // token URLs.
      final played = await http.get(Uri.parse(voiceUrl));
      expect(played.statusCode, 200);
      expect(played.bodyBytes, List.filled(128, 3));

      await expectDenied(() => bobNotes.unsend(coupleId: coupleId, note: later));
      await aliceNotes.unsend(coupleId: coupleId, note: listen);
    });
  });

  group('plans', () {
    test('date plans: idea, schedule, done, back to ideas', () async {
      final s = DatePlanService(db: alice.db);
      await s.save(
        coupleId,
        DatePlan(
          id: '',
          title: 'Picnic',
          createdBy: alice.uid,
          notes: 'Cubbon park',
          vibe: DateVibe.outdoors,
          estimatedCostMinor: 50000,
        ),
      );
      final plan = (await firstWhere(
        DatePlanService(db: bob.db).watchPlans(coupleId),
        (l) => l.isNotEmpty,
      )).single;
      final b = DatePlanService(db: bob.db);
      await b.schedule(coupleId, plan.id, DateTime(2026, 11, 1, 11));
      await b.markDone(coupleId, plan.id, rating: 5, reflection: 'Lovely');
      await b.moveToIdeas(coupleId, plan.id);
      await b.save(
        coupleId,
        DatePlan(
          id: plan.id,
          title: 'Picnic 2',
          createdBy: plan.createdBy,
          status: DatePlanStatus.planned,
          scheduledAt: DateTime(2026, 12, 1),
        ),
      );
      await expectDenied(
        () => b.save(
          coupleId,
          DatePlan(id: plan.id, title: 'Mine now', createdBy: bob.uid),
        ),
      );
      await b.delete(coupleId, plan.id);
    });

    test('bucket list: add, tick off, edit', () async {
      final s = BucketListService(db: bob.db);
      await s.save(
        coupleId,
        BucketItem(
          id: '',
          title: 'See the northern lights',
          createdBy: bob.uid,
          category: BucketCategory.travel,
          targetYear: 2028,
        ),
      );
      final item = (await firstWhere(
        BucketListService(db: alice.db).watchItems(coupleId),
        (l) => l.isNotEmpty,
      )).single;
      final a = BucketListService(db: alice.db);
      await a.setDone(
        coupleId: coupleId,
        itemId: item.id,
        done: true,
        uid: alice.uid,
      );
      await a.save(
        coupleId,
        BucketItem(
          id: item.id,
          title: 'Northern lights in Tromsø',
          createdBy: item.createdBy,
          category: BucketCategory.travel,
          notes: 'Winter',
        ),
      );
      await a.setDone(
        coupleId: coupleId,
        itemId: item.id,
        done: false,
        uid: alice.uid,
      );
    });

    test('wishlist and secret claims', () async {
      final a = WishlistService(db: alice.db);
      await a.save(
        coupleId,
        WishlistItem(
          id: '',
          title: 'Kindle',
          createdBy: alice.uid,
          url: 'https://example.com/kindle',
          priceMinor: 1299900,
          priority: WishlistPriority.love,
          occasion: WishlistOccasion.birthday,
        ),
      );
      final b = WishlistService(db: bob.db);
      final wish = (await firstWhere(
        b.watchItems(coupleId),
        (l) => l.isNotEmpty,
      )).single;
      await expectDenied(
        () => b.save(
          coupleId,
          WishlistItem(id: wish.id, title: 'x', createdBy: wish.createdBy),
        ),
      );
      await b.claim(coupleId: coupleId, item: wish, myUid: bob.uid);
      // A retry of my own claim is fine.
      await b.claim(coupleId: coupleId, item: wish, myUid: bob.uid);
      await b.markPurchased(coupleId: coupleId, itemId: wish.id, purchased: true);
      final mine = await firstWhere(
        b.watchMyClaims(coupleId, bob.uid),
        (m) => m.isNotEmpty,
      );
      expect(mine[wish.id]!.purchased, isTrue);
      // Alice never sees the claim on her own wish.
      final aliceClaims = await firstWhere(
        a.watchMyClaims(coupleId, alice.uid),
        (_) => true,
      );
      expect(aliceClaims, isEmpty);
      await expectDenied(
        () => alice.db
            .collection('couples')
            .doc(coupleId)
            .collection('wishlistClaims')
            .doc(wish.id)
            .get(),
      );
      await a.save(
        coupleId,
        WishlistItem(
          id: wish.id,
          title: 'Kindle Paperwhite',
          createdBy: alice.uid,
          url: '',
          priority: WishlistPriority.like,
        ),
      );
      await a.setReceived(coupleId: coupleId, itemId: wish.id, received: true);
      await b.unclaim(coupleId: coupleId, itemId: wish.id);
    });

    test('places: want to go, been, favourite', () async {
      final s = PlaceService(db: alice.db);
      await s.save(
        coupleId,
        Place(
          id: '',
          name: 'Third Wave Coffee',
          createdBy: alice.uid,
          area: 'Indiranagar',
          mapsUrl: 'https://maps.google.com/?q=third+wave',
          category: PlaceCategory.cafe,
        ),
      );
      final place = (await firstWhere(
        PlaceService(db: bob.db).watchPlaces(coupleId),
        (l) => l.isNotEmpty,
      )).single;
      final b = PlaceService(db: bob.db);
      await b.markBeen(
        coupleId,
        place.id,
        visitedAt: DateTime(2026, 10, 1),
        rating: 4,
        notes: 'Good cold brew',
      );
      await b.setFavourite(coupleId, place.id, true);
      await b.markWantToGo(coupleId, place.id);
      await b.delete(coupleId, place.id);
    });

    test('expenses: equal, custom split, settlement', () async {
      final s = ExpenseService(db: alice.db);
      await s.save(
        coupleId,
        Expense(
          id: '',
          title: 'Groceries',
          amountMinor: 245000,
          paidBy: alice.uid,
          spentOn: DateTime(2026, 10, 20),
          createdBy: alice.uid,
          category: ExpenseCategory.groceries,
        ),
      );
      await s.save(
        coupleId,
        Expense(
          id: '',
          title: 'Trip',
          amountMinor: 1000000,
          paidBy: bob.uid,
          spentOn: DateTime(2026, 10, 21),
          createdBy: alice.uid,
          split: ExpenseSplit.custom,
          shares: {alice.uid: 600000, bob.uid: 400000},
          category: ExpenseCategory.travel,
        ),
      );
      await ExpenseService(db: bob.db).save(
        coupleId,
        Expense(
          id: '',
          title: 'Settle up',
          amountMinor: 77500,
          paidBy: bob.uid,
          spentOn: DateTime(2026, 10, 22),
          createdBy: bob.uid,
          kind: ExpenseKind.settlement,
          split: ExpenseSplit.full,
        ),
      );
      final list = await firstWhere(
        ExpenseService(db: bob.db).watchExpenses(coupleId),
        (l) => l.length == 3,
      );
      final trip = list.firstWhere((e) => e.title == 'Trip');
      expect(trip.shares, {alice.uid: 600000, bob.uid: 400000});
      // Bob corrects Alice's entry; only Alice may delete it.
      await ExpenseService(db: bob.db).save(
        coupleId,
        Expense(
          id: trip.id,
          title: 'Trip to Coorg',
          amountMinor: trip.amountMinor,
          paidBy: trip.paidBy,
          spentOn: trip.spentOn,
          createdBy: trip.createdBy,
          split: trip.split,
          shares: trip.shares,
          category: trip.category,
        ),
      );
      await expectDenied(() => ExpenseService(db: bob.db).delete(coupleId, trip.id));
      await s.delete(coupleId, trip.id);
    });
  });

  group('music and play', () {
    test('songs and listening together', () async {
      final a = MusicService(db: alice.db);
      final id = await a.save(
        coupleId,
        Song(
          id: '',
          url: 'https://open.spotify.com/track/abc123',
          source: SongSource.spotify,
          addedBy: alice.uid,
          kind: SongKind.track,
          mediaId: 'abc123',
          title: 'Perfect',
          artist: 'Ed Sheeran',
          moment: SongMoment.ourSong,
        ),
      );
      final id2 = await a.save(
        coupleId,
        Song(
          id: '',
          url: 'https://www.youtube.com/watch?v=xyz',
          source: SongSource.youtube,
          addedBy: alice.uid,
          kind: SongKind.video,
          mediaId: 'xyz',
          title: 'Kesariya',
          moment: SongMoment.romantic,
        ),
      );
      final b = MusicService(db: bob.db);
      await b.setLoved(coupleId, id, uid: bob.uid, loved: true);
      final songs = await firstWhere(
        b.watchSongs(coupleId),
        (l) => l.length == 2,
      );
      final song = songs.firstWhere((s) => s.id == id);
      expect(song.lovedBy, unorderedEquals([alice.uid, bob.uid]));
      await b.save(
        coupleId,
        Song(
          id: song.id,
          url: song.url,
          source: song.source,
          addedBy: song.addedBy,
          kind: song.kind,
          mediaId: song.mediaId,
          title: song.title,
          artist: song.artist,
          note: 'Our first dance',
          moment: song.moment,
        ),
      );

      await b.calibrateClock(coupleId, bob.uid);
      expect(b.clock.isCalibrated, isTrue);
      await b.startSession(
        coupleId: coupleId,
        song: song,
        uid: bob.uid,
        queue: [id2],
      );
      final session = await firstWhere(
        a.watchSession(coupleId),
        (s) => s != null,
      );
      expect(session!.songId, song.id);
      await a.heartbeat(coupleId, alice.uid);
      await a.setStatus(
        coupleId: coupleId,
        uid: alice.uid,
        status: ListeningStatus.paused,
        positionMs: 12000,
      );
      await b.setStatus(
        coupleId: coupleId,
        uid: bob.uid,
        status: ListeningStatus.countdown,
      );
      await a.next(coupleId: coupleId, uid: alice.uid, currentSongId: song.id);
      final nextUp = await firstWhere(
        b.watchSession(coupleId),
        (s) => s?.songId == id2,
      );
      expect(nextUp!.hostUid, bob.uid);
      await a.next(coupleId: coupleId, uid: alice.uid, currentSongId: id2);
      await a.leave(coupleId, alice.uid);
      final ended = await firstWhere(
        b.watchSession(coupleId),
        (s) => s?.status == ListeningStatus.ended,
      );
      expect(ended!.listeners.containsKey(alice.uid), isFalse);
      final played = (await firstWhere(
        b.watchSongs(coupleId),
        (l) => l.every((s) => s.playCount == 1),
      ));
      expect(played, hasLength(2));
      await b.delete(coupleId, id2);
    });

    test('tic-tac-toe: invite, accept, play to a win', () async {
      final a = GameService(db: alice.db);
      final b = GameService(db: bob.db);
      final gameId = await a.invite(
        coupleId: coupleId,
        type: GameType.ticTacToe,
        me: alice.uid,
        invitee: bob.uid,
        state: TicTacToeLogic.newState(),
      );
      final invited = await firstWhere(
        b.watchGame(coupleId, gameId),
        (g) => g != null,
      );
      await b.accept(
        coupleId: coupleId,
        gameId: gameId,
        me: bob.uid,
        firstTurn: TicTacToeLogic.firstTurn(invited!),
      );
      // Bob (first) takes 0, 1, 2; Alice takes 3, 4.
      final moves = [(bob, 0), (alice, 3), (bob, 1), (alice, 4), (bob, 2)];
      for (final (p, cell) in moves) {
        await GameService(db: p.db).takeTurn(
          coupleId: coupleId,
          gameId: gameId,
          me: p.uid,
          apply: (g) => TicTacToeLogic.applyMove(g, p.uid, cell),
        );
      }
      final done = await firstWhere(
        a.watchGame(coupleId, gameId),
        (g) => g?.status == GameStatus.finished,
      );
      expect(done!.winner, bob.uid);
      // Finished games are frozen.
      await expectLater(
        a.cancel(coupleId: coupleId, gameId: gameId),
        throwsA(isA<GameMoveException>()),
      );
    });

    test('know me: secret answers, guesses, reveal', () async {
      final a = GameService(db: alice.db);
      final b = GameService(db: bob.db);
      final gameId = await a.invite(
        coupleId: coupleId,
        type: GameType.knowMe,
        me: alice.uid,
        invitee: bob.uid,
        state: KnowMeLogic.newState(subject: alice.uid),
      );
      final invited = await firstWhere(
        b.watchGame(coupleId, gameId),
        (g) => g != null,
      );
      await b.accept(
        coupleId: coupleId,
        gameId: gameId,
        me: bob.uid,
        firstTurn: KnowMeLogic.firstTurn(invited!),
      );
      const answers = [0, 1, 2, 3, 0, 1, 2];
      await KnowMeService(db: alice.db).submitAnswers(
        coupleId: coupleId,
        gameId: gameId,
        me: alice.uid,
        answers: answers,
      );
      // Bob can't peek before locking in.
      await expectLater(
        KnowMeService(db: bob.db)
            .readAnswers(coupleId: coupleId, gameId: gameId),
        throwsA(isA<DbException>()),
      );
      const guesses = [0, 1, 2, 0, 0, 0, 2];
      await b.takeTurn(
        coupleId: coupleId,
        gameId: gameId,
        me: bob.uid,
        apply: (g) => KnowMeLogic.lockGuesses(g, bob.uid, guesses),
      );
      final revealed = await KnowMeService(db: bob.db)
          .readAnswers(coupleId: coupleId, gameId: gameId);
      expect(revealed, answers);
      await b.takeTurn(
        coupleId: coupleId,
        gameId: gameId,
        me: bob.uid,
        apply: (g) => KnowMeLogic.reveal(g, bob.uid, revealed),
      );
      final done = await firstWhere(
        a.watchGame(coupleId, gameId),
        (g) => g?.status == GameStatus.finished,
      );
      expect(KnowMeLogic.scoreOf(done!), 5);
    });

    test('cancel an invite', () async {
      final a = GameService(db: alice.db);
      final gameId = await a.invite(
        coupleId: coupleId,
        type: GameType.connectFour,
        me: alice.uid,
        invitee: bob.uid,
      );
      await GameService(db: bob.db).cancel(coupleId: coupleId, gameId: gameId);
      final games = await firstWhere(
        a.watchGames(coupleId),
        (l) => l.length == 3,
      );
      expect(
        games.firstWhere((g) => g.id == gameId).status,
        GameStatus.cancelled,
      );
    });
  });

  group('premium, look, security', () {
    test('gift from the server: the recipient opens it', () async {
      // Gifts and credits are written only by the server after a Play
      // purchase; seed them the way verifyPurchase writes them.
      final giftId = 'gift_$runId';
      await sql(
        'INSERT INTO couple_gifts (couple_id, id, data) VALUES '
        '(${sqlString(coupleId)}, ${sqlString(giftId)}, '
        '${sqlString('{"fromUid":"${alice.uid}","toUid":"${bob.uid}","kind":"book","months":null,"message":"For us","createdAt":{"\$ts":"2026-10-24T07:00:00.000Z"},"openedAt":null}')}::jsonb)',
      );
      final gifts = await firstWhere(
        GiftService(db: bob.db).watchGifts(coupleId),
        (l) => l.isNotEmpty,
      );
      await expectDenied(
        () => GiftService(db: alice.db)
            .markOpened(coupleId: coupleId, gift: gifts.single),
      );
      await GiftService(db: bob.db)
          .markOpened(coupleId: coupleId, gift: gifts.single);
      final opened = await firstWhere(
        GiftService(db: alice.db).watchGifts(coupleId),
        (l) => l.single.isOpened,
      );
      expect(opened.single.openedAt, isNotNull);
    });

    test('memory book: upload the PDF, spend a credit, read, rename', () async {
      await sql(
        "UPDATE couples SET data = data || '{\"bookCredits\": 1}'::jsonb "
        'WHERE id = ${sqlString(coupleId)}',
      );
      final books = BookService(
        db: alice.db,
        files: StorageBookFileStore(alice.files),
      );
      final bookId = books.newBookId(coupleId);
      final pdf = Uint8List.fromList('%PDF-1.4\n%%EOF\n'.codeUnits);
      await books.uploadPdf(coupleId: coupleId, bookId: bookId, bytes: pdf);
      await books.saveBook(
        coupleId: coupleId,
        bookId: bookId,
        uid: alice.uid,
        title: 'Our  first   year',
        fromDate: DateTime(2023, 6, 1),
        toDate: DateTime(2024, 6, 1),
        pageCount: 12,
        creditsBefore: 1,
      );
      expect((await couple(alice)).bookCredits, 0);
      // No credit left: a second book is refused by the rules.
      await expectDenied(
        () => books.saveBook(
          coupleId: coupleId,
          bookId: books.newBookId(coupleId),
          uid: alice.uid,
          title: 'Another',
          fromDate: DateTime(2023, 6, 1),
          toDate: DateTime(2024, 6, 1),
          pageCount: 3,
          creditsBefore: 1,
        ),
      );
      final bobBooks = BookService(
        db: bob.db,
        files: StorageBookFileStore(bob.files),
      );
      final list = await firstWhere(
        bobBooks.watchBooks(coupleId),
        (l) => l.isNotEmpty,
      );
      expect(list.single.title, 'Our first year');
      expect(await bobBooks.readPdf(list.single), pdf);
      await expectDenied(
        () => bobBooks.rename(coupleId: coupleId, bookId: bookId, title: 'x'),
      );
      await books.rename(coupleId: coupleId, bookId: bookId, title: 'Year one');
      await bobBooks.delete(coupleId: coupleId, book: list.single);
    });

    test('chat look: shared, personal, background upload', () async {
      final look = ChatLookService(db: alice.db, files: alice.files);
      await look.saveShared(
        coupleId: coupleId,
        uid: alice.uid,
        look: const ChatLook(
          colorValue: 0xFFFF7EA6,
          background: ChatBackground(
            kind: ChatBackgroundKind.pattern,
            patternId: 'hearts',
          ),
        ),
      );
      final shared = await firstWhere(
        ChatLookService(db: bob.db, files: bob.files).watchShared(coupleId),
        (l) => l.look.colorValue == 0xFFFF7EA6,
      );
      expect(shared.look.background.patternId, 'hearts');

      final file = await tempFile('bg.jpg', onePixelPng);
      final up = await look.uploadBackground(
        file: file,
        coupleId: coupleId,
        uid: alice.uid,
        personal: true,
      );
      // Only Alice may read her personal background.
      await expectDenied(() => bob.files.ref(up.path).getDownloadURL());
      await look.savePersonal(
        uid: alice.uid,
        mode: ChatLookMode.personal,
        look: ChatLook(
          background: ChatBackground(
            kind: ChatBackgroundKind.photo,
            photoUrl: up.url,
            storagePath: up.path,
            dim: 0.4,
            blur: 3,
          ),
        ),
      );
      final personal = await firstWhere(
        look.watchPersonal(alice.uid),
        (p) => p.mode == ChatLookMode.personal,
      );
      expect(personal.look!.background.dim, 0.4);
      final sharedBg = await look.uploadBackground(
        file: file,
        coupleId: coupleId,
        uid: alice.uid,
        personal: false,
      );
      expect(await bob.files.ref(sharedBg.path).getData(), onePixelPng);
      await look.deleteUploaded(sharedBg.path);
    });

    test('avatar on the profile', () async {
      await AvatarService(db: bob.db).save(
        uid: bob.uid,
        avatar: const AvatarConfig(hair: 'curly', glasses: 'round'),
        asProfilePicture: true,
      );
      await AvatarService(db: bob.db)
          .setAsProfilePicture(uid: bob.uid, value: false);
      final me = await profile(alice, bob.uid);
      expect(me.avatar?.hair, 'curly');
    });

    test('sign-in protection: devices, partner check, notices', () async {
      final aliceTrust = DeviceTrustService(db: alice.db);
      final bobTrust = DeviceTrustService(db: bob.db);
      await aliceTrust.addDevice(
        uid: alice.uid,
        deviceId: 'dev-1',
        name: 'Pixel 9',
        via: DeviceVia.first,
      );
      await aliceTrust.touchDevice(uid: alice.uid, deviceId: 'dev-1');
      expect((await aliceTrust.loadDevices(alice.uid)).single.id, 'dev-1');
      // The partner may see the list, not change it.
      expect(
        (await firstWhere(bobTrust.watchDevices(alice.uid), (l) => l.isNotEmpty))
            .single
            .name,
        'Pixel 9',
      );
      await expectDenied(
        () => bobTrust.removeDevice(uid: alice.uid, deviceId: 'dev-1'),
      );

      final partner = await aliceTrust.loadPartner(alice.uid);
      expect(partner!.uid, bob.uid);

      // A new phone asks Bob; Bob says no, which leaves Alice a notice.
      final code = aliceTrust.newCode();
      final checkId = await aliceTrust.createCheck(
        cid: coupleId,
        uid: alice.uid,
        deviceId: 'dev-2',
        deviceName: 'Galaxy S24',
        code: code,
      );
      final pending = await firstWhere(
        bobTrust.watchPendingChecks(coupleId, alice.uid),
        (l) => l.isNotEmpty,
      );
      expect(pending.single.id, checkId);
      await expectDenied(
        () => aliceTrust.decideCheck(
          cid: coupleId,
          check: pending.single,
          decidedBy: alice.uid,
          approved: true,
        ),
      );
      await bobTrust.decideCheck(
        cid: coupleId,
        check: pending.single,
        decidedBy: bob.uid,
        approved: false,
      );
      final found = await aliceTrust.findCheck(
        cid: coupleId,
        uid: alice.uid,
        deviceId: 'dev-2',
      );
      expect(found!.status, DeviceCheckStatus.rejected);
      final events = await firstWhere(
        aliceTrust.watchEvents(alice.uid),
        (l) => l.isNotEmpty,
      );
      expect(events.single.type, SecurityEventType.newPhoneRejected);

      // Waiting notice, block, clean-up.
      await aliceTrust.addEvent(
        uid: alice.uid,
        id: SecurityEvent.waitId('dev-3'),
        type: SecurityEventType.newPhoneWaiting,
        deviceName: 'Old phone',
      );
      final wait = await firstWhere(
        aliceTrust.watchWaitStart(alice.uid, 'dev-3'),
        (w) => w.exists,
      );
      expect(wait.at, isNotNull);
      await aliceTrust.blockNewPhones(
        alice.uid,
        DateTime.now().add(const Duration(days: 7)),
      );
      expect(
        await firstWhere(aliceTrust.watchBlockUntil(alice.uid), (d) => d != null),
        isNotNull,
      );
      for (final e in await firstWhere(
        aliceTrust.watchEvents(alice.uid),
        (l) => l.length == 2,
      )) {
        await aliceTrust.deleteEvent(alice.uid, e.id);
      }
      await aliceTrust.deleteCheck(coupleId, checkId);
      await aliceTrust.removeDevice(uid: alice.uid, deviceId: 'dev-1');
    });
  });

  group('vault', () {
    test('set up, add a phone, messages and photos, wipe a shelf', () async {
      final crypto = VaultCrypto.forTests(seed: 11);
      final aliceVault = VaultService(
        db: alice.db,
        blobs: FilesVaultBlobStore(alice.files),
      );
      final bobVault = VaultService(
        db: bob.db,
        blobs: FilesVaultBlobStore(bob.files),
      );
      Future<DeviceIdentity> identity(VaultCrypto c) async => DeviceIdentity(
        deviceId: c.newDeviceId(),
        keyPair: await c.newDeviceKeyPair(),
      );

      final aliceId = await identity(crypto);
      final keys = crypto.newVaultKeys();
      await aliceVault.createVault(
        cid: coupleId,
        uid: alice.uid,
        device: VaultDevice(
          id: aliceId.deviceId,
          uid: alice.uid,
          publicKey: aliceId.publicKeyB64,
          name: 'Pixel 9',
          approved: true,
        ),
        keys: await crypto.wrapKeys(keys, aliceId.publicKeyB64),
        verifier: await crypto.createVerifier(
          vmk: keys.vmk,
          realCode: '246810',
          decoyCode: '135790',
          realShelf: 'a',
        ),
      );
      await expectLater(
        bobVault.createVault(
          cid: coupleId,
          uid: bob.uid,
          device: VaultDevice(
            id: 'x',
            uid: bob.uid,
            publicKey: aliceId.publicKeyB64,
            name: 'x',
            approved: true,
          ),
          keys: await crypto.wrapKeys(keys, aliceId.publicKeyB64),
          verifier: 'v',
        ),
        throwsA(isA<VaultExistsException>()),
      );

      // Bob's phone registers; Alice approves it.
      final bobCrypto = VaultCrypto.forTests(seed: 12);
      final bobId = await identity(bobCrypto);
      await bobVault.registerDevice(
        cid: coupleId,
        device: VaultDevice(
          id: bobId.deviceId,
          uid: bob.uid,
          publicKey: bobId.publicKeyB64,
          name: 'iPhone',
          approved: false,
        ),
      );
      await aliceVault.approveDevice(
        cid: coupleId,
        uid: alice.uid,
        deviceId: bobId.deviceId,
        keys: await crypto.wrapKeys(keys, bobId.publicKeyB64),
        approverDeviceName: 'Pixel 9',
      );
      final meta = (await bobVault.getMeta(coupleId))!;
      expect(meta.devices[bobId.deviceId]!.approved, isTrue);
      final bobKeys = await bobCrypto.unwrapKeys(
        meta.keys[bobId.deviceId]!,
        bobId.keyPair,
      );
      expect(bobKeys.vmk, keys.vmk);
      await aliceVault.setVerifier(
        cid: coupleId,
        uid: alice.uid,
        verifier: meta.verifier,
        deviceName: 'Pixel 9',
      );

      // A message (view once) and a photo (24 hours).
      final msgId = aliceVault.newItemId(coupleId);
      await aliceVault.addMessage(
        cid: coupleId,
        itemId: msgId,
        senderId: alice.uid,
        shelf: 'a',
        ct: await crypto.encryptContent(
          keys.vmk,
          msgId,
          const VaultMessageContent('just us').toJson(),
        ),
        policy: VaultPolicy.once,
      );
      final photoId = aliceVault.newItemId(coupleId);
      final photoPath = aliceVault.newFilePath(coupleId);
      final thumbPath = aliceVault.newFilePath(coupleId);
      final jpeg = Uint8List.fromList(onePixelPng);
      await aliceVault.addPhoto(
        cid: coupleId,
        itemId: photoId,
        senderId: alice.uid,
        shelf: 'a',
        ct: await crypto.encryptContent(
          keys.vmk,
          photoId,
          VaultPhotoContent(
            width: 1,
            height: 1,
            photoPath: photoPath,
            thumbPath: thumbPath,
            bytes: jpeg.length,
          ).toJson(),
        ),
        policy: VaultPolicy.day,
        photoPath: photoPath,
        photo: await crypto.encryptBlob(keys.vmk, photoId, 'photo', jpeg),
        thumbPath: thumbPath,
        thumb: await crypto.encryptBlob(keys.vmk, photoId, 'thumb', jpeg),
      );

      final items = await firstWhere(
        bobVault.watchItems(coupleId),
        (l) => l.length == 2,
      );
      final photo = items.firstWhere((i) => i.id == photoId);
      final encrypted = await bobVault.download(photo.photoPath!);
      expect(
        await bobCrypto.decryptBlob(bobKeys.vmk, photoId, 'photo', encrypted),
        jpeg,
      );
      await bobVault.markViewed(cid: coupleId, itemId: msgId, uid: bob.uid);
      // Bob saw the view-once message: his clean-up deletes it.
      final cleaned = await bobVault.cleanUp(
        cid: coupleId,
        uid: bob.uid,
        now: DateTime.now(),
      );
      expect(cleaned, 1);

      final events = await firstWhere(
        aliceVault.watchEvents(coupleId),
        (l) => l.length >= 3,
      );
      await aliceVault.dismissEvent(coupleId, events.first.id);
      await bobVault.wipeShelf(
        cid: coupleId,
        shelf: 'a',
        uid: bob.uid,
        deviceName: 'iPhone',
      );
      expect(await aliceVault.getItems(coupleId), isEmpty);
      await expectDenied(() => alice.files.ref(photoPath).getDownloadURL(),
          code: 'not-found');
    });
  });

  group('ending the pairing', () {
    late SeparationService aliceSep;
    late SeparationService bobSep;
    setUpAll(() {
      aliceSep = SeparationService(db: alice.db);
      bobSep = SeparationService(db: bob.db);
    });

    Future<Separation?> current() async => (await couple(alice)).separation;

    test('ask, decline, agree, call off', () async {
      await aliceSep.request(coupleId: coupleId, uid: alice.uid, current: null);
      var sep = (await current())!;
      expect(sep.status, SeparationStatus.requested);
      // The vault closes while a pairing is ending.
      final closed = VaultService(db: bob.db, blobs: MemoryVaultBlobStore());
      await expectDenied(() => closed.getMeta(coupleId));
      // Known difference: Firestore refuses this listing as a whole; the
      // server leaves unreadable documents out (store.ts query()), so it
      // comes back empty. The vault events are still there.
      final events = await bob.db
          .collection('couples')
          .doc(coupleId)
          .collection('vaultEvents')
          .get();
      expect(events.docs, isEmpty);
      await expectLater(
        aliceSep.agree(coupleId: coupleId, uid: alice.uid, current: sep),
        throwsA(isA<SeparationException>()),
      );
      await bobSep.decline(coupleId: coupleId, uid: bob.uid, current: sep);
      sep = (await current())!;
      expect(sep.status, SeparationStatus.declined);
      await bobSep.agree(coupleId: coupleId, uid: bob.uid, current: sep);
      sep = (await current())!;
      expect(sep.status, SeparationStatus.agreed);
      expect(
        sep.effectiveAt.difference(DateTime.now()).inDays,
        inInclusiveRange(6, 7),
      );
      // Bob can't call it off; Alice can.
      await expectDenied(
        () => bob.db
            .collection('couples')
            .doc(coupleId)
            .update({'separation': FieldValue.delete()}),
      );
      await aliceSep.cancel(coupleId: coupleId, uid: alice.uid, current: sep);
      expect(await current(), isNull);
      // Not due: finalizing is refused with the date.
      await bobSep.setMutePartner(uid: bob.uid, muted: true);
      await expectLater(
        FunctionsEndPairingGateway(bob.functions).finalizeSeparation(coupleId),
        throwsA(
          isA<EndPairingException>().having(
            (e) => e.failure,
            'failure',
            EndPairingFailure.notReady,
          ),
        ),
      );
    });

    test('leave now: both are unpaired and everything is gone', () async {
      // A message from before, so there is something to delete.
      await ChatService(db: alice.db, storage: StorageService(files: alice.files))
          .sendText(coupleId: coupleId, senderId: alice.uid, text: 'bye');
      final result =
          await FunctionsEndPairingGateway(bob.functions).leaveNow(coupleId);
      expect(result.isDone, isTrue);
      expect(result.how, 'leftNow');

      for (final p in [alice, bob]) {
        final me = await profile(p);
        expect(me.coupleId, isNull, reason: p.name);
        expect(me.pairingEndedHow, 'leftNow');
        expect(me.pairingEndedAt, isNotNull);
        await SeparationService(db: p.db).clearPairingEnded(p.uid);
        expect((await profile(p)).pairingEndedHow, isNull);
      }
      expect((await profile(bob)).mutePartner, isFalse);
      // The couple is gone; reading it is now refused like any missing couple.
      await expectDenied(
        () => alice.db.collection('couples').doc(coupleId).get(),
      );
      // Partners can no longer read each other's profile.
      await expectDenied(
        () => alice.db.collection('users').doc(bob.uid).get(),
      );
      // A second call finds it already ended.
      final again =
          await FunctionsEndPairingGateway(alice.functions).leaveNow(coupleId);
      expect(again.isDone, isTrue);
    });
  });
}

