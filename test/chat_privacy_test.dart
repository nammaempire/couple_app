import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/backend/backend.dart';
import 'package:couple_app/core/backend/memory_backend.dart';
import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/core/services/screen_privacy.dart';
import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_look_providers.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/chat/screens/chat_screen.dart';
import 'package:couple_app/features/chat/screens/chat_search_screen.dart';
import 'package:couple_app/features/chat/widgets/chat_privacy_scope.dart';
import 'package:couple_app/features/chat/widgets/clear_chat_sheet.dart';
import 'package:couple_app/features/chat/widgets/message_actions_sheet.dart';
import 'package:couple_app/features/chat/widgets/system_message_line.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

const me = 'asha';
const partner = 'ravi';
const coupleId = 'c1';

/// Records deletes instead of touching file storage.
class _FakeStorage implements StorageService {
  final deleted = <String>[];

  @override
  Future<void> deleteByUrl(String url) async => deleted.add(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDetector implements ScreenshotDetector {
  final _events = StreamController<void>.broadcast();
  bool started = false;

  void screenshot() => _events.add(null);

  @override
  Stream<void> get screenshots => _events.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => started = false;
}

class _FakeSecurity implements ScreenSecurity {
  final calls = <bool>[];

  bool get secure => calls.isNotEmpty && calls.last;

  @override
  Future<void> setSecure(bool secure) async => calls.add(secure);
}

final _clearedAt = DateTime(2026, 10, 1, 12);

CollectionReference<Map<String, dynamic>> _messages(Db db) =>
    db.collection('couples').doc(coupleId).collection('messages');

Future<void> _seedCouple(Db db, {bool blockScreenshots = false}) async {
  await db.collection('couples').doc(coupleId).set({
    'inviteCode': 'ABC123',
    'memberIds': [me, partner],
    'lastMessagePreview': 'hi',
    'blockScreenshots': blockScreenshots,
  });
  await db.collection('users').doc(me).set({
    'displayName': 'Asha',
    'coupleId': coupleId,
  });
}

Future<void> _addMessage(
  Db db, {
  required String text,
  required DateTime sentAt,
  String senderId = me,
  String type = 'text',
  String? imageUrl,
  String? mediaUrl,
  bool pinned = false,
}) {
  return _messages(db).add({
    'senderId': senderId,
    'type': type,
    'text': text,
    'imageUrl': imageUrl,
    'mediaUrl': mediaUrl,
    'sentAt': Timestamp.fromDate(sentAt),
    'seen': false,
    'reactions': <String, dynamic>{},
    'pinned': pinned,
  });
}

/// The conversation as stored, oldest first.
Future<List<Message>> _stored(Db db) async {
  final snap = await _messages(db).orderBy('sentAt').get();
  return snap.docs.map(Message.fromDoc).toList();
}

class _Harness {
  _Harness(this.db, this.storage, this.detector, this.security);

  final Db db;
  final _FakeStorage storage;
  final _FakeDetector detector;
  final _FakeSecurity security;
}

List<Override> _overrides(_Harness h, {DateTime? myClearedAt}) => [
  chatServiceProvider.overrideWithValue(
    ChatService(db: h.db, storage: h.storage),
  ),
  coupleServiceProvider.overrideWithValue(CoupleService(db: h.db)),
  currentUserProvider.overrideWithBuild(
    (ref, n) => AppUser(
      uid: me,
      displayName: 'Asha',
      coupleId: coupleId,
      chatClearedAt: myClearedAt,
    ),
  ),
  partnerNameProvider.overrideWithValue('Ravi'),
  effectiveChatLookProvider.overrideWithValue(ChatLook.standard),
  screenshotDetectorProvider.overrideWithValue(h.detector),
  screenSecurityProvider.overrideWithValue(h.security),
];

Future<_Harness> _pumpChat(
  WidgetTester tester, {
  DateTime? myClearedAt,
  bool isActive = true,
  bool blockScreenshots = false,
  Future<void> Function(Db db)? seed,
}) async {
  tester.view.physicalSize = const Size(360 * 3, 740 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final h = _Harness(
    Db(MemoryBackend()),
    _FakeStorage(),
    _FakeDetector(),
    _FakeSecurity(),
  );
  await _seedCouple(h.db, blockScreenshots: blockScreenshots);
  await seed?.call(h.db);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(h, myClearedAt: myClearedAt),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ChatScreen(isActive: isActive),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Future<void> _openMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('Message system types', () {
    test('parse, store text without media, and stay seen', () {
      const alert = Message(
        id: '',
        senderId: me,
        type: MessageType.screenshot,
        text: '📸 Asha took a screenshot of a photo',
        seen: true,
        screenshotOf: ScreenshotSubject.photo,
      );
      final map = alert.toMap();
      expect(map['type'], 'screenshot');
      expect(map['screenshotOf'], 'photo');
      expect(map['seen'], isTrue);
      for (final key in ['imageUrl', 'mediaUrl', 'replyTo', 'reactions']) {
        expect(map.containsKey(key), isFalse, reason: key);
      }

      final parsed = Message.fromMap('m1', {
        'senderId': me,
        'type': 'screenshotBlock',
        'text': '🔒 Asha turned on screenshot blocking',
        'blocked': true,
      });
      expect(parsed.isSystem, isTrue);
      expect(parsed.screenshotsBlocked, isTrue);
      expect(parsed.previewText, '🔒 Asha turned on screenshot blocking');

      expect(MessageType.chatCleared.isSystem, isTrue);
      expect(MessageType.call.isSystem, isFalse);
    });

    test('isClearedBy hides up to and including the clear time', () {
      Message at(DateTime? t) =>
          Message(id: 'm', senderId: me, type: MessageType.text, sentAt: t);
      expect(at(_clearedAt).isClearedBy(_clearedAt), isTrue);
      expect(
        at(
          _clearedAt.subtract(const Duration(days: 1)),
        ).isClearedBy(_clearedAt),
        isTrue,
      );
      expect(
        at(_clearedAt.add(const Duration(seconds: 1))).isClearedBy(_clearedAt),
        isFalse,
      );
      // Still waiting for its server time: always newer than a clear.
      expect(at(null).isClearedBy(_clearedAt), isFalse);
      expect(at(_clearedAt).isClearedBy(null), isFalse);
    });
  });

  group('ChatService', () {
    late Db db;
    late _FakeStorage storage;
    late ChatService chat;

    setUp(() async {
      db = Db(MemoryBackend());
      storage = _FakeStorage();
      chat = ChatService(db: db, storage: storage);
      await _seedCouple(db);
    });

    test('visiblePart drops cleared messages and stops paging there', () {
      final page = [
        Message(
          id: 'new',
          senderId: me,
          type: MessageType.text,
          sentAt: _clearedAt.add(const Duration(minutes: 1)),
        ),
        Message(
          id: 'old',
          senderId: me,
          type: MessageType.text,
          sentAt: _clearedAt.subtract(const Duration(minutes: 1)),
        ),
      ];
      final part = ChatService.visiblePart(page, _clearedAt);
      expect(part.visible.map((m) => m.id), ['new']);
      expect(part.reachedClear, isTrue);

      final all = ChatService.visiblePart(page, null);
      expect(all.visible, hasLength(2));
      expect(all.reachedClear, isFalse);
    });

    test('clearForMe stamps only my profile', () async {
      await chat.clearForMe(uid: me);
      final user = await db.collection('users').doc(me).get();
      expect(user.data()!['chatClearedAt'], isA<Timestamp>());
      final couple = await db.collection('couples').doc(coupleId).get();
      expect(couple.data()!.containsKey('chatClearedAt'), isFalse);
    });

    test('search, media and markSeen ignore cleared messages', () async {
      final before = _clearedAt.subtract(const Duration(hours: 1));
      final after = _clearedAt.add(const Duration(hours: 1));
      await _addMessage(db, text: 'old hello', sentAt: before);
      await _addMessage(db, text: 'new hello', sentAt: after);
      await _addMessage(
        db,
        text: '',
        type: 'image',
        imageUrl: 'https://x/old.jpg',
        sentAt: before,
      );
      await _addMessage(
        db,
        text: '',
        type: 'image',
        imageUrl: 'https://x/new.jpg',
        sentAt: after,
      );
      await _addMessage(
        db,
        text: 'their old',
        senderId: partner,
        sentAt: before,
      );
      await _addMessage(
        db,
        text: 'their new',
        senderId: partner,
        sentAt: after,
      );

      final recent = await chat.fetchRecent(coupleId, clearedAt: _clearedAt);
      expect(recent.map((m) => m.text), isNot(contains('old hello')));
      expect(recent.map((m) => m.text), contains('new hello'));

      final media = await chat.fetchMedia(coupleId, clearedAt: _clearedAt);
      expect(media.map((m) => m.imageUrl), ['https://x/new.jpg']);

      await chat.markSeen(
        coupleId: coupleId,
        partnerId: partner,
        clearedAt: _clearedAt,
      );
      final seen = {for (final m in await _stored(db)) m.text: m.seen};
      expect(seen['their new'], isTrue);
      expect(seen['their old'], isFalse);
    });

    test('clearForBoth stamps the couple, deletes in batches with media, '
        'and posts a system line', () async {
      final start = DateTime.now().subtract(const Duration(days: 2));
      for (var i = 0; i < 450; i++) {
        await _addMessage(
          db,
          text: 'm$i',
          senderId: i.isEven ? me : partner,
          sentAt: start.add(Duration(minutes: i)),
          type: i == 3 ? 'video' : (i == 4 ? 'voice' : 'text'),
          imageUrl: i == 3 ? 'https://x/thumb.jpg' : null,
          mediaUrl: i == 3
              ? 'https://x/video.mp4'
              : (i == 4 ? 'https://x/voice.m4a' : null),
        );
      }

      final progress = <int>[];
      await chat.clearForBoth(
        coupleId: coupleId,
        senderId: me,
        senderName: 'Asha',
        onProgress: progress.add,
      );

      expect(progress, [0, ChatService.clearBatchSize, 450]);
      expect(
        storage.deleted,
        unorderedEquals([
          'https://x/thumb.jpg',
          'https://x/video.mp4',
          'https://x/voice.m4a',
        ]),
      );

      final couple = (await db.collection('couples').doc(coupleId).get())
          .data()!;
      expect(couple['chatClearedAt'], isA<Timestamp>());
      expect(couple['chatClearedBy'], me);
      expect(couple['lastMessagePreview'], '🧹 Asha cleared the chat');

      final left = await _stored(db);
      expect(left, hasLength(1));
      expect(left.single.type, MessageType.chatCleared);
      expect(left.single.senderId, me);
      expect(left.single.text, '🧹 Asha cleared the chat');
      expect(left.single.seen, isTrue);
      expect(left.single.imageUrl, isNull);
    });

    test(
      'clearForBoth finishes the job when run again after a failure',
      () async {
        final start = DateTime.now().subtract(const Duration(days: 1));
        for (var i = 0; i < 410; i++) {
          await _addMessage(
            db,
            text: 'm$i',
            sentAt: start.add(Duration(seconds: i)),
          );
        }

        // Fails right after the first batch is committed.
        await expectLater(
          chat.clearForBoth(
            coupleId: coupleId,
            senderId: me,
            senderName: 'Asha',
            onProgress: (n) {
              if (n > 0) throw StateError('connection lost');
            },
          ),
          throwsStateError,
        );
        expect(await _stored(db), hasLength(10));

        await chat.clearForBoth(
          coupleId: coupleId,
          senderId: me,
          senderName: 'Asha',
        );
        final left = await _stored(db);
        expect(left.map((m) => m.type), [MessageType.chatCleared]);
      },
    );

    test('screenshot alerts and blocking post system lines', () async {
      await chat.sendScreenshotAlert(
        coupleId: coupleId,
        senderId: me,
        senderName: 'Asha',
        subject: ScreenshotSubject.photo,
      );
      await chat.setScreenshotBlocking(
        coupleId: coupleId,
        senderId: me,
        senderName: 'Asha',
        blocked: true,
      );

      final couple = (await db.collection('couples').doc(coupleId).get())
          .data()!;
      expect(couple['blockScreenshots'], isTrue);

      final raw = (await _messages(db).get()).docs.map((d) => d.data());
      final shot = raw.firstWhere((m) => m['type'] == 'screenshot');
      expect(shot['text'], '📸 Asha took a screenshot of a photo');
      expect(shot['screenshotOf'], 'photo');
      expect(shot['senderId'], me);
      expect(shot['seen'], isTrue);

      final block = raw.firstWhere((m) => m['type'] == 'screenshotBlock');
      expect(block['text'], '🔒 Asha turned on screenshot blocking');
      expect(block['blocked'], isTrue);
    });
  });

  group('ScreenPrivacyGuard', () {
    late _FakeDetector detector;
    late _FakeSecurity security;
    late DateTime now;
    late ScreenPrivacyGuard guard;
    late int reports;

    setUp(() {
      detector = _FakeDetector();
      security = _FakeSecurity();
      now = DateTime(2026, 10, 17, 9);
      guard = ScreenPrivacyGuard(
        detector: detector,
        security: security,
        now: () => now,
      );
      reports = 0;
    });

    test('reports one screenshot per 10 s window', () async {
      final holder = Object();
      guard.claim(holder, secure: false, onScreenshot: () => reports++);
      expect(detector.started, isTrue);

      detector.screenshot();
      detector.screenshot();
      await Future<void>.delayed(Duration.zero);
      expect(reports, 1);

      now = now.add(const Duration(seconds: 9));
      detector.screenshot();
      await Future<void>.delayed(Duration.zero);
      expect(reports, 1);

      now = now.add(const Duration(seconds: 2));
      detector.screenshot();
      await Future<void>.delayed(Duration.zero);
      expect(reports, 2);
    });

    test(
      'nothing is reported once released; secure mode follows claims',
      () async {
        final chatScreen = Object();
        final viewer = Object();
        var viewerReports = 0;
        guard.claim(chatScreen, secure: true, onScreenshot: () => reports++);
        expect(security.secure, isTrue);

        // The screen on top gets the report.
        guard.claim(viewer, secure: true, onScreenshot: () => viewerReports++);
        detector.screenshot();
        await Future<void>.delayed(Duration.zero);
        expect((reports, viewerReports), (0, 1));

        guard.release(viewer);
        guard.release(chatScreen);
        expect(security.secure, isFalse);
        expect(detector.started, isFalse);

        now = now.add(const Duration(minutes: 1));
        detector.screenshot();
        await Future<void>.delayed(Duration.zero);
        expect((reports, viewerReports), (0, 1));
      },
    );
  });

  group('System lines', () {
    Future<void> pumpLine(
      WidgetTester tester,
      Message message, {
      VoidCallback? onLongPress,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SystemMessageLine(
              message: message,
              myUid: me,
              partnerName: 'Ravi',
              onLongPress: onLongPress,
            ),
          ),
        ),
      );
    }

    String label(MessageType type, String sender, {Message? from}) =>
        SystemMessageLine.labelFor(
          from ?? Message(id: 'm', senderId: sender, type: type),
          myUid: me,
          partnerName: 'Ravi',
        );

    test('word each type for me and for my partner', () {
      expect(label(MessageType.chatCleared, me), '🧹 You cleared the chat');
      expect(
        label(MessageType.chatCleared, partner),
        '🧹 Ravi cleared the chat',
      );
      expect(label(MessageType.screenshot, me), '📸 You took a screenshot');
      expect(
        label(MessageType.screenshot, partner),
        '📸 Ravi took a screenshot of the chat',
      );
      expect(
        label(
          MessageType.screenshot,
          partner,
          from: const Message(
            id: 'm',
            senderId: partner,
            type: MessageType.screenshot,
            screenshotOf: ScreenshotSubject.photo,
          ),
        ),
        '📸 Ravi took a screenshot of a photo',
      );
      expect(
        label(
          MessageType.screenshotBlock,
          me,
          from: const Message(
            id: 'm',
            senderId: me,
            type: MessageType.screenshotBlock,
            screenshotsBlocked: true,
          ),
        ),
        '🔒 You turned on screenshot blocking',
      );
      expect(
        label(MessageType.screenshotBlock, partner),
        '🔒 Ravi turned off screenshot blocking',
      );
    });

    testWidgets('render as a centred line, not a bubble', (tester) async {
      await pumpLine(
        tester,
        const Message(id: 'm', senderId: partner, type: MessageType.screenshot),
      );
      final text = find.textContaining('Ravi took a screenshot of the chat');
      expect(text, findsOneWidget);
      expect(
        tester.getCenter(text).dx,
        moreOrLessEquals(
          tester.getCenter(find.byType(Scaffold)).dx,
          epsilon: 1,
        ),
      );
    });

    testWidgets('their actions are hidden; only my delete remains', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MessageActionsSheet(
              message: const Message(
                id: 'm',
                senderId: me,
                type: MessageType.chatCleared,
                text: '🧹 Asha cleared the chat',
              ),
              myUid: me,
              onReact: (_) {},
              onReply: () {},
              onCopy: () {},
              onTogglePin: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Pin'), findsNothing);
      expect(find.text('Copy text'), findsNothing);
      for (final reaction in CoupleReaction.values) {
        expect(find.text(reaction.emoji), findsNothing);
      }
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('Chat screen', () {
    testWidgets('clear for me hides older messages, pins included', (
      tester,
    ) async {
      await _pumpChat(
        tester,
        myClearedAt: _clearedAt,
        seed: (db) async {
          await _addMessage(
            db,
            text: 'before the clear',
            pinned: true,
            sentAt: _clearedAt.subtract(const Duration(minutes: 5)),
          );
          await _addMessage(
            db,
            text: 'after the clear',
            sentAt: _clearedAt.add(const Duration(minutes: 5)),
          );
        },
      );

      expect(find.text('after the clear'), findsOneWidget);
      expect(find.text('before the clear'), findsNothing);
      // The pinned bar would show the hidden pin's text.
      expect(find.textContaining('before the clear'), findsNothing);
    });

    testWidgets('system lines show centred with my and their wording', (
      tester,
    ) async {
      final t = DateTime.now().subtract(const Duration(minutes: 10));
      await _pumpChat(
        tester,
        seed: (db) async {
          await _addMessage(
            db,
            text: '📸 Ravi took a screenshot',
            senderId: partner,
            type: 'screenshot',
            sentAt: t,
          );
          await _addMessage(
            db,
            text: '🧹 Asha cleared the chat',
            type: 'chatCleared',
            sentAt: t.add(const Duration(minutes: 1)),
          );
        },
      );
      expect(
        find.textContaining('📸 Ravi took a screenshot of the chat'),
        findsOneWidget,
      );
      expect(find.textContaining('🧹 You cleared the chat'), findsOneWidget);
      expect(find.byType(SystemMessageLine), findsNWidgets(2));

      // Long-pressing the partner's line offers nothing.
      await tester.longPress(find.textContaining('Ravi took a screenshot'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageActionsSheet), findsNothing);

      // Mine offers delete only.
      await tester.longPress(find.textContaining('You cleared the chat'));
      await tester.pumpAndSettle();
      expect(find.byType(MessageActionsSheet), findsOneWidget);
      expect(find.text('Reply'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('a screenshot posts one alert while the chat is visible', (
      tester,
    ) async {
      final h = await _pumpChat(tester);
      expect(h.detector.started, isTrue);

      h.detector.screenshot();
      h.detector.screenshot();
      await tester.pumpAndSettle();

      final alerts = (await _stored(
        h.db,
      )).where((m) => m.type == MessageType.screenshot).toList();
      expect(alerts, hasLength(1));
      expect(alerts.single.senderId, me);
      expect(alerts.single.text, '📸 Asha took a screenshot');
      expect(find.textContaining('📸 You took a screenshot'), findsOneWidget);
    });

    testWidgets('nothing is posted when the chat tab is not on screen', (
      tester,
    ) async {
      final h = await _pumpChat(tester, isActive: false);
      expect(h.detector.started, isFalse);
      h.detector.screenshot();
      await tester.pumpAndSettle();
      expect(await _stored(h.db), isEmpty);
    });

    testWidgets('nothing is posted while another page covers the chat', (
      tester,
    ) async {
      final h = await _pumpChat(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Call')),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.detector.started, isFalse);

      h.detector.screenshot();
      await tester.pumpAndSettle();
      expect(await _stored(h.db), isEmpty);

      // Back on the chat: watching again.
      navigator.pop();
      await tester.pumpAndSettle();
      expect(h.detector.started, isTrue);
    });

    testWidgets('a photo opened from chat stays protected and says so', (
      tester,
    ) async {
      final h = await _pumpChat(tester, blockScreenshots: true);
      expect(h.security.secure, isTrue);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const ChatPrivacyScope(
            subject: ScreenshotSubject.photo,
            child: Scaffold(body: Text('Photo')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.security.secure, isTrue);

      h.detector.screenshot();
      await tester.pumpAndSettle();
      final alert = (await _stored(h.db)).single;
      expect(alert.screenshotOf, ScreenshotSubject.photo);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(h.security.secure, isTrue);
    });

    testWidgets('the block switch writes the couple and turns on secure mode', (
      tester,
    ) async {
      final h = await _pumpChat(tester);
      expect(h.security.secure, isFalse);

      await _openMenuItem(tester, 'Screenshots');
      expect(find.textContaining('Android 14'), findsOneWidget);
      await tester.tap(find.text('Block screenshots of our chat'));
      await tester.pumpAndSettle();

      final couple = (await h.db.collection('couples').doc(coupleId).get())
          .data()!;
      expect(couple['blockScreenshots'], isTrue);
      expect(h.security.secure, isTrue);
      expect((await _stored(h.db)).single.type, MessageType.screenshotBlock);

      // Turning it off restores normal behaviour.
      await tester.tap(find.text('Block screenshots of our chat'));
      await tester.pumpAndSettle();
      expect(h.security.secure, isFalse);
    });

    testWidgets('leaving the chat tab turns secure mode off', (tester) async {
      final h = await _pumpChat(tester, blockScreenshots: true);
      expect(h.security.secure, isTrue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(h),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ChatScreen(isActive: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.security.secure, isFalse);
    });

    testWidgets('the Clear chat sheet offers both choices and confirms', (
      tester,
    ) async {
      final h = await _pumpChat(
        tester,
        seed: (db) => _addMessage(
          db,
          text: 'hello',
          sentAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );

      await _openMenuItem(tester, 'Clear chat');
      expect(find.byType(ClearChatSheet), findsOneWidget);
      expect(find.text('Clear for me'), findsOneWidget);
      expect(find.text('Clear for both'), findsOneWidget);
      expect(find.textContaining('Ravi keeps their history'), findsOneWidget);

      // Clear for me: confirm, and only my profile changes.
      await tester.tap(find.text('Clear for me'));
      await tester.pumpAndSettle();
      expect(find.text('Clear chat for you?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Clear for me'));
      await tester.pumpAndSettle();
      final user = (await h.db.collection('users').doc(me).get()).data()!;
      expect(user['chatClearedAt'], isA<Timestamp>());
      expect(await _stored(h.db), hasLength(1));

      // Clear for both: the red button waits for the explicit tick.
      await _openMenuItem(tester, 'Clear chat');
      await tester.tap(find.text('Clear for both'));
      await tester.pumpAndSettle();
      final deleteButton = find.widgetWithText(FilledButton, 'Delete for both');
      expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);
      await tester.tap(find.text('I understand it is gone for good'));
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      final left = await _stored(h.db);
      expect(left.map((m) => m.type), [MessageType.chatCleared]);
      expect(find.textContaining('🧹 You cleared the chat'), findsOneWidget);
      expect(find.text('Clearing the chat…'), findsNothing);
    });
  });

  testWidgets('search ignores messages hidden by clear for me', (tester) async {
    final h = _Harness(
      Db(MemoryBackend()),
      _FakeStorage(),
      _FakeDetector(),
      _FakeSecurity(),
    );
    await _seedCouple(h.db);
    await _addMessage(
      h.db,
      text: 'pizza before',
      sentAt: _clearedAt.subtract(const Duration(hours: 1)),
    );
    await _addMessage(
      h.db,
      text: 'pizza after',
      sentAt: _clearedAt.add(const Duration(hours: 1)),
    );
    await _addMessage(
      h.db,
      text: '📸 pizza screenshot',
      type: 'screenshot',
      sentAt: _clearedAt.add(const Duration(hours: 2)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(h, myClearedAt: _clearedAt),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ChatSearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pizza');
    await tester.pumpAndSettle();

    expect(find.text('1 result'), findsOneWidget);
    expect(find.textContaining('before'), findsNothing);
  });
}
