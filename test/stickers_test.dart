import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/providers/avatar_providers.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/chat/widgets/message_bubble.dart';
import 'package:couple_app/features/chat/widgets/reply_quote.dart';
import 'package:couple_app/features/stickers/data/sticker_catalog.dart';
import 'package:couple_app/features/stickers/data/sticker_quotes.dart';
import 'package:couple_app/features/stickers/models/sticker_category.dart';
import 'package:couple_app/features/stickers/providers/sticker_providers.dart';
import 'package:couple_app/features/stickers/widgets/couple_sticker_view.dart';
import 'package:couple_app/features/stickers/widgets/sticker_picker_sheet.dart';

const me = 'asha';
const partner = 'ravi';
const myLook = AvatarConfig(hair: 'long', outfitColor: 'lilac');
const theirLook = AvatarConfig(hair: 'quiff', outfitColor: 'teal');

/// Records stickers instead of writing them.
class _FakeChatService implements ChatService {
  final sent = <Map<String, Object?>>[];
  bool fail = false;

  @override
  Future<void> sendSticker({
    required String coupleId,
    required String senderId,
    required String stickerId,
    required String category,
    required String quote,
    ReplyPreview? replyTo,
  }) async {
    if (fail) throw Exception('offline');
    sent.add({
      'coupleId': coupleId,
      'senderId': senderId,
      'stickerId': stickerId,
      'category': category,
      'quote': quote,
      'replyTo': replyTo?.messageId,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<Override> _overrides({
  required ChatService chat,
  AvatarConfig? mine = myLook,
  AvatarConfig? theirs = theirLook,
}) => [
  chatServiceProvider.overrideWithValue(chat),
  currentUserProvider.overrideWithBuild(
    (ref, n) => const AppUser(uid: me, displayName: 'Asha', coupleId: 'c1'),
  ),
  myAvatarProvider.overrideWithValue(mine),
  partnerAvatarProvider.overrideWithValue(theirs),
];

void _phoneSize(WidgetTester tester, {Size size = const Size(360, 740)}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('catalog', () {
    test('has enough scenes, with unique ids', () {
      final ids = StickerCatalog.scenes.map((s) => s.id).toList();
      expect(ids.length, greaterThanOrEqualTo(28));
      expect(ids.toSet().length, ids.length);
    });

    test('every category has scenes with a default quote from it', () {
      for (final category in StickerCategory.values) {
        final scenes = StickerCatalog.forCategory(category);
        expect(scenes.length, greaterThanOrEqualTo(3), reason: category.id);
        for (final scene in scenes) {
          final quote = StickerQuotes.byId(scene.defaultQuoteId);
          expect(quote, isNotNull, reason: scene.id);
          expect(quote!.category, category, reason: scene.id);
          expect(scene.gradient, hasLength(2), reason: scene.id);
        }
      }
    });

    test('every category has 15+ unique quotes of 90 chars or less', () {
      final ids = StickerQuotes.all.map((q) => q.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final category in StickerCategory.values) {
        final texts = StickerQuotes.forCategory(
          category,
        ).map((q) => q.text).toList();
        expect(texts.length, greaterThanOrEqualTo(15), reason: category.id);
        expect(texts.toSet().length, texts.length, reason: category.id);
        for (final text in texts) {
          expect(text.trim(), isNotEmpty);
          expect(
            text.length,
            lessThanOrEqualTo(ChatService.maxStickerQuoteLength),
            reason: text,
          );
        }
      }
    });

    test('long quotes are cut by whole characters, never mid-emoji', () {
      expect(ChatService.clampStickerQuote('  hi  '), 'hi');
      final exactly = '❤️' * ChatService.maxStickerQuoteLength;
      expect(ChatService.clampStickerQuote(exactly), exactly);

      // 89 letters then family emoji: the 90th character is a whole emoji
      // made of several code units, and the 91st is cut.
      final family = '👨‍👩‍👧';
      final long = '${'a' * 89}$family$family';
      final cut = ChatService.clampStickerQuote(long);
      expect(cut, '${'a' * 89}$family');
      expect(cut.characters.length, ChatService.maxStickerQuoteLength);

      // A flag split by code units would leave half a flag behind.
      final flags = '🇮🇳' * 100;
      final flagCut = ChatService.clampStickerQuote(flags);
      expect(flagCut, '🇮🇳' * ChatService.maxStickerQuoteLength);

      // Trailing space left by the cut is trimmed.
      expect(ChatService.clampStickerQuote('${'b' * 89} 😀 more'), 'b' * 89);
    });

    test('category ids round-trip and unknown ones are null', () {
      for (final category in StickerCategory.values) {
        expect(StickerCategory.fromId(category.id), category);
      }
      expect(StickerCategory.fromId('missYou'), StickerCategory.missYou);
      expect(StickerCategory.fromId('nope'), isNull);
    });

    test('unknown scenes fall back to their category, then the first', () {
      expect(StickerCatalog.resolve('miss-apart', 'missYou').id, 'miss-apart');
      expect(
        StickerCatalog.resolve('from-the-future', 'sorry').category,
        StickerCategory.sorry,
      );
      expect(
        StickerCatalog.resolve(null, null).id,
        StickerCatalog.scenes.first.id,
      );
    });
  });

  group('sticker messages', () {
    const sticker = Message(
      id: 'm1',
      senderId: me,
      type: MessageType.sticker,
      text: 'Same moon, different windows.',
      stickerId: 'miss-moon',
      stickerCategory: 'missYou',
    );

    test('store type, quote as text, and {id, category}', () {
      final map = sticker.toMap();
      expect(map['type'], 'sticker');
      expect(map['text'], 'Same moon, different windows.');
      expect(map['sticker'], {'id': 'miss-moon', 'category': 'missYou'});
      expect(
        const Message(
          id: '',
          senderId: me,
          type: MessageType.text,
        ).toMap().containsKey('sticker'),
        isFalse,
      );

      final back = Message.fromMap('m1', map);
      expect(back.type, MessageType.sticker);
      expect(back.text, sticker.text);
      expect(back.stickerId, 'miss-moon');
      expect(back.stickerCategory, 'missYou');
    });

    test('preview text', () {
      expect(sticker.previewText, '💞 Same moon, different windows.');
      expect(
        const Message(
          id: '',
          senderId: me,
          type: MessageType.sticker,
        ).previewText,
        'Sticker',
      );
    });

    test('replies keep the sticker so the quote can show it', () {
      final reply = ReplyPreview.of(sticker);
      expect(reply.text, '💞 Same moon, different windows.');
      final back = ReplyPreview.fromMap(reply.toMap())!;
      expect(back.type, MessageType.sticker);
      expect(back.stickerId, 'miss-moon');
      expect(back.stickerCategory, 'missYou');
      expect(
        ReplyPreview.of(
          const Message(id: 'x', senderId: me, type: MessageType.text),
        ).toMap().containsKey('sticker'),
        isFalse,
      );
    });

    test('reply quotes drop the sticker marker only beside a thumbnail', () {
      const reply = ReplyPreview(
        messageId: 'm0',
        senderId: me,
        type: MessageType.sticker,
        text: '💞 Good night, love.',
        stickerId: 'night-moon',
      );
      expect(
        ReplyQuote.previewFor(reply, withThumb: true),
        'Good night, love.',
      );
      expect(
        ReplyQuote.previewFor(reply, withThumb: false),
        '💞 Good night, love.',
      );
      expect(
        ReplyQuote.previewFor(
          const ReplyPreview(
            messageId: 'm0',
            senderId: me,
            type: MessageType.sticker,
            text: '💞 ',
          ),
          withThumb: true,
        ),
        'Sticker',
      );
      // Stored data is untouched.
      expect(reply.toMap()['text'], '💞 Good night, love.');
    });

    test(
      'unknown types still read as text; junk sticker fields are ignored',
      () {
        expect(MessageType.fromId('sticker'), MessageType.sticker);
        final future = Message.fromMap('m2', {
          'senderId': partner,
          'type': 'hologram',
          'text': 'hello from the future',
          'sticker': 42,
        });
        expect(future.type, MessageType.text);
        expect(future.previewText, 'hello from the future');
        expect(future.stickerId, isNull);
      },
    );

    test('the sender is always on the left', () {
      final container = ProviderContainer(
        overrides: _overrides(chat: _FakeChatService()),
      );
      addTearDown(container.dispose);
      final mine = container.read(stickerAvatarsProvider(me));
      expect(mine.sender, myLook);
      expect(mine.partner, theirLook);
      final theirs = container.read(stickerAvatarsProvider(partner));
      expect(theirs.sender, theirLook);
      expect(theirs.partner, myLook);
    });
  });

  group('CoupleStickerView', () {
    for (final brightness in Brightness.values) {
      testWidgets('draws every scene ($brightness)', (tester) async {
        for (final avatars in [
          (null, null),
          (const AvatarConfig(), const AvatarConfig()),
          (myLook, null),
        ]) {
          for (final scene in StickerCatalog.scenes) {
            await tester.pumpWidget(
              MaterialApp(
                theme: brightness == Brightness.light
                    ? AppTheme.light()
                    : AppTheme.dark(),
                home: Center(
                  child: CoupleStickerView(
                    scene: scene,
                    sender: avatars.$1,
                    partner: avatars.$2,
                    quote: StickerCatalog.defaultQuote(scene).text,
                    width: 220,
                  ),
                ),
              ),
            );
            expect(tester.takeException(), isNull, reason: scene.id);
          }
        }
      });
    }

    testWidgets('long quotes and large text stay inside the card', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: CoupleStickerView(
                scene: StickerCatalog.scenes.first,
                sender: null,
                partner: null,
                quote: 'x' * 90,
                width: 280,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('MessageBubble', () {
    testWidgets('shows a sticker card without a bubble, still interactive', (
      tester,
    ) async {
      _phoneSize(tester);
      var longPressed = false;
      var replied = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(chat: _FakeChatService()),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: ListView(
                children: [
                  MessageBubble(
                    message: Message(
                      id: 'm1',
                      senderId: partner,
                      type: MessageType.sticker,
                      text: 'Counting the sleeps until I can hug you again.',
                      stickerId: 'miss-apart',
                      stickerCategory: 'missYou',
                      sentAt: DateTime(2026, 10, 16, 9, 30),
                      reactions: const {me: '❤️'},
                      replyTo: const ReplyPreview(
                        messageId: 'm0',
                        senderId: me,
                        type: MessageType.sticker,
                        text: '💞 Good night, love.',
                        stickerId: 'night-moon',
                        stickerCategory: 'goodNight',
                      ),
                    ),
                    isMine: false,
                    myUid: me,
                    partnerName: 'Ravi',
                    onLongPress: () => longPressed = true,
                    onSwipeReply: () => replied = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // The main card plus the reply quote's thumbnail.
      expect(find.byType(CoupleStickerView), findsNWidgets(2));
      final card = tester.widget<CoupleStickerView>(
        find.byType(CoupleStickerView).last,
      );
      expect(card.sender, theirLook, reason: 'Ravi sent it: Ravi on the left');
      expect(card.partner, myLook);
      expect(find.textContaining('9:30'), findsOneWidget);
      expect(find.text('❤️'), findsOneWidget);
      // The quoted sticker shows its thumbnail and its line, without the
      // stored "💞 " marker repeating it.
      expect(find.text('Good night, love.'), findsOneWidget);
      expect(find.textContaining('💞'), findsNothing);

      await tester.longPress(find.byType(CoupleStickerView).last);
      expect(longPressed, isTrue);

      await tester.drag(
        find.byType(CoupleStickerView).last,
        const Offset(120, 0),
      );
      await tester.pumpAndSettle();
      expect(replied, isTrue);
    });
  });

  group('StickerPickerSheet', () {
    Future<_FakeChatService> openPicker(
      WidgetTester tester, {
      AvatarConfig? mine = myLook,
      List<bool?>? results,
      Size size = const Size(360, 740),
    }) async {
      _phoneSize(tester, size: size);
      final chat = _FakeChatService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(chat: chat, mine: mine),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      final sent = await showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        showDragHandle: true,
                        builder: (_) => const StickerPickerSheet(
                          replyTo: ReplyPreview(
                            messageId: 'r1',
                            senderId: partner,
                            type: MessageType.text,
                            text: 'miss you',
                          ),
                        ),
                      );
                      results?.add(sent);
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return chat;
    }

    String previewQuote(WidgetTester tester) =>
        tester.widget<CoupleStickerView>(find.byType(CoupleStickerView)).quote;

    testWidgets('pick category, scene and quote, then send', (tester) async {
      final results = <bool?>[];
      final chat = await openPicker(tester, results: results);

      expect(find.text('Couple stickers'), findsOneWidget);
      expect(find.byKey(const ValueKey('sticker-make-avatar')), findsNothing);
      for (final category in StickerCategory.values) {
        expect(
          find.byKey(ValueKey('sticker-category-${category.id}')),
          findsOneWidget,
        );
      }

      final missYou = find.byKey(const ValueKey('sticker-category-missYou'));
      await tester.ensureVisible(missYou);
      await tester.pumpAndSettle();
      await tester.tap(missYou);
      await tester.pumpAndSettle();
      final scene = StickerCatalog.forCategory(StickerCategory.missYou).first;
      final tile = find.byKey(ValueKey('sticker-scene-${scene.id}'));
      expect(tile, findsOneWidget);
      final tileView = tester.widget<CoupleStickerView>(
        find.descendant(of: tile, matching: find.byType(CoupleStickerView)),
      );
      expect(tileView.sender, myLook);
      expect(tileView.partner, theirLook);

      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(previewQuote(tester), StickerCatalog.defaultQuote(scene).text);

      // Cycle forward and back.
      final quotes = StickerQuotes.forCategory(StickerCategory.missYou);
      final start = quotes.indexWhere(
        (q) => q.id == StickerCatalog.defaultQuote(scene).id,
      );
      await tester.tap(find.byKey(const ValueKey('sticker-next-quote')));
      await tester.pumpAndSettle();
      expect(previewQuote(tester), quotes[(start + 1) % quotes.length].text);
      await tester.tap(find.byKey(const ValueKey('sticker-prev-quote')));
      await tester.pumpAndSettle();
      expect(previewQuote(tester), quotes[start].text);

      await tester.tap(find.byKey(const ValueKey('sticker-shuffle')));
      await tester.pumpAndSettle();
      expect(previewQuote(tester), isNot(quotes[start].text));

      // Tap a specific line.
      final chosen = quotes[4];
      final option = find.byKey(ValueKey('sticker-quote-${chosen.id}'));
      await tester.scrollUntilVisible(
        option,
        200,
        scrollable: find
            .descendant(
              of: find.byType(StickerPickerSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(previewQuote(tester), chosen.text);

      await tester.tap(find.byKey(const ValueKey('sticker-send')));
      await tester.pumpAndSettle();
      expect(chat.sent, [
        {
          'coupleId': 'c1',
          'senderId': me,
          'stickerId': scene.id,
          'category': 'missYou',
          'quote': chosen.text,
          'replyTo': 'r1',
        },
      ]);
      expect(results, [true]);
      expect(find.text('Couple stickers'), findsNothing);
    });

    testWidgets('sends my own line', (tester) async {
      final chat = await openPicker(tester);
      await tester.tap(find.byKey(const ValueKey('sticker-scene-love-hug')));
      await tester.pumpAndSettle();
      // With the keyboard up, the sheet still fits.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      await tester.enterText(
        find.byKey(const ValueKey('sticker-own-line')),
        'Biryani date on Friday?',
      );
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(previewQuote(tester), 'Biryani date on Friday?');
      await tester.tap(find.byKey(const ValueKey('sticker-send')));
      await tester.pumpAndSettle();
      expect(chat.sent.single['quote'], 'Biryani date on Friday?');
      expect(chat.sent.single['stickerId'], 'love-hug');
    });

    for (final (size, keyboard) in [
      (const Size(360, 640), 300.0),
      (const Size(640, 360), 180.0),
    ]) {
      testWidgets('writing my own line fits above a ${keyboard.round()}px '
          'keyboard at ${size.width.round()}x${size.height.round()}', (
        tester,
      ) async {
        final chat = await openPicker(tester, size: size);
        await tester.tap(find.byKey(const ValueKey('sticker-scene-love-hug')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final field = find.byKey(const ValueKey('sticker-own-line'));
        // The field sits by Send, not inside the scrolling list.
        expect(field.hitTestable(), findsOneWidget);

        await tester.tap(field);
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(field.hitTestable(), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sticker-send')).hitTestable(),
          findsOneWidget,
        );
        // Everything sits above the keyboard.
        final keyboardTop = size.height - keyboard;
        expect(tester.getRect(field).bottom, lessThanOrEqualTo(keyboardTop));
        expect(
          tester.getRect(find.byKey(const ValueKey('sticker-send'))).bottom,
          lessThanOrEqualTo(keyboardTop),
        );
        // The quote list makes way; the preview stays.
        expect(find.byType(CoupleStickerView), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sticker-quote-love-01')),
          findsNothing,
        );

        await tester.enterText(field, 'Chai at 5? 😊☕');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(previewQuote(tester), 'Chai at 5? 😊☕');
        await tester.tap(find.byKey(const ValueKey('sticker-send')));
        await tester.pumpAndSettle();
        expect(chat.sent.single['quote'], 'Chai at 5? 😊☕');
        tester.view.resetViewInsets();
      });
    }

    testWidgets('a failed send keeps the sheet open', (tester) async {
      final chat = await openPicker(tester)
        ..fail = true;
      await tester.tap(find.byKey(const ValueKey('sticker-scene-love-kiss')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sticker-send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sticker-send')), findsOneWidget);
      expect(chat.sent, isEmpty);
    });

    testWidgets('invites me to make an avatar when I have none', (
      tester,
    ) async {
      await openPicker(tester, mine: null);
      expect(
        find.text('Make your avatar so stickers look like you'),
        findsOneWidget,
      );
      // Placeholders still render every scene in the grid.
      for (final category in StickerCategory.values) {
        final chip = find.byKey(ValueKey('sticker-category-${category.id}'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
        expect(find.byType(CoupleStickerView), findsWidgets);
      }
    });
  });
}
