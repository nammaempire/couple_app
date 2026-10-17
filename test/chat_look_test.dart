import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/data/chat_look_service.dart';
import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/chat/providers/chat_look_providers.dart';
import 'package:couple_app/features/chat/screens/chat_appearance_screen.dart';
import 'package:couple_app/features/chat/widgets/chat_background_layer.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';
import 'package:couple_app/features/chat/widgets/chat_patterns.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

const me = 'u1';
const partner = 'u2';
const ocean = 0xFF3A86C8;
const plum = 0xFF8E4585;

/// Records saves instead of writing to Firebase.
class FakeChatLookService extends ChatLookService {
  final sharedSaves = <ChatLook>[];
  final personalSaves = <({ChatLookMode mode, ChatLook? look})>[];
  final deleted = <String>[];

  @override
  Future<void> saveShared({
    required String coupleId,
    required String uid,
    required ChatLook look,
  }) async => sharedSaves.add(look);

  @override
  Future<void> savePersonal({
    required String uid,
    required ChatLookMode mode,
    ChatLook? look,
  }) async => personalSaves.add((mode: mode, look: look));

  @override
  Future<({String url, String path})> uploadBackground({
    required File file,
    required String coupleId,
    required String uid,
    required bool personal,
  }) async => (url: 'https://example.com/bg.jpg', path: 'x/bg.jpg');

  @override
  Future<void> deleteUploaded(String? path) async {
    if (path != null) deleted.add(path);
  }
}

Future<FakeChatLookService> pumpAppearance(
  WidgetTester tester, {
  SharedChatLook shared = const SharedChatLook(look: ChatLook.standard),
  PersonalChatLook personal = const PersonalChatLook(),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(360 * 3, 740 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final service = FakeChatLookService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatLookServiceProvider.overrideWithValue(service),
        sharedChatLookProvider.overrideWith((ref) => Stream.value(shared)),
        personalChatLookProvider.overrideWith((ref) => Stream.value(personal)),
        currentUserProvider.overrideWithBuild(
          (ref, n) =>
              const AppUser(uid: me, displayName: 'Asha', coupleId: 'c1'),
        ),
        partnerNameProvider.overrideWithValue('Ravi'),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChatAppearanceScreen(),
                  ),
                ),
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
  return service;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Scrolls the settings list until [finder] is built and on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('ChatBackground / ChatLook maps', () {
    test('a photo look survives toMap → fromMap', () {
      const look = ChatLook(
        colorValue: ocean,
        background: ChatBackground(
          kind: ChatBackgroundKind.photo,
          photoUrl: 'https://example.com/a.jpg',
          storagePath: 'couples/c1/backgrounds/a.jpg',
          dim: .4,
          blur: 6,
        ),
      );
      expect(ChatLook.fromMap(look.toMap()), look);
    });

    test('a pattern look survives, and only writes its own fields', () {
      const look = ChatLook(
        background: ChatBackground(
          kind: ChatBackgroundKind.pattern,
          patternId: 'hearts',
          photoUrl: 'https://stale.example/x.jpg',
        ),
      );
      final map = look.toMap();
      final bg = map['background'] as Map<String, dynamic>;
      expect(map['color'], isNull);
      expect(bg['patternId'], 'hearts');
      expect(bg['photoUrl'], isNull);
      expect(bg['storagePath'], isNull);
      final back = ChatLook.fromMap(map);
      expect(back.background.kind, ChatBackgroundKind.pattern);
      expect(back.background.patternId, 'hearts');
    });

    test('bad maps fall back to the standard look', () {
      expect(ChatLook.fromMap(null), ChatLook.standard);
      expect(ChatLook.fromMap('nope'), ChatLook.standard);
      expect(
        ChatLook.fromMap({'color': 'red', 'background': 3}).isStandard,
        isTrue,
      );
      expect(
        ChatBackground.fromMap({'kind': 'sparkles'}).kind,
        ChatBackgroundKind.none,
      );
      expect(ChatBackgroundKind.fromId(null), ChatBackgroundKind.none);
    });

    test('half-written backgrounds become none', () {
      expect(ChatBackground.fromMap({'kind': 'photo'}), ChatBackground.none);
      expect(
        ChatBackground.fromMap({'kind': 'photo', 'photoUrl': 'file:///a.jpg'}),
        ChatBackground.none,
      );
      expect(ChatBackground.fromMap({'kind': 'pattern'}), ChatBackground.none);
      expect(
        ChatBackground.fromMap({'kind': 'pattern', 'patternId': 7}),
        ChatBackground.none,
      );
    });

    test('dim and blur are clamped both ways', () {
      final read = ChatBackground.fromMap({
        'kind': 'photo',
        'photoUrl': 'https://example.com/a.jpg',
        'dim': 5,
        'blur': -3,
      });
      expect(read.dim, ChatBackground.maxDim);
      expect(read.blur, 0);
      expect(
        ChatBackground.fromMap({
          'kind': 'none',
          'dim': double.nan,
          'blur': 99,
        }).blur,
        ChatBackground.maxBlur,
      );
      const wild = ChatBackground(dim: 2, blur: 40);
      expect(wild.toMap()['dim'], ChatBackground.maxDim);
      expect(wild.toMap()['blur'], ChatBackground.maxBlur);
    });
  });

  group('PersonalChatLook', () {
    const shared = ChatLook(colorValue: ocean);
    const mine = ChatLook(colorValue: plum);

    test('effective follows the mode', () {
      expect(const PersonalChatLook().effective(shared), shared);
      expect(
        const PersonalChatLook(
          mode: ChatLookMode.shared,
          look: mine,
        ).effective(shared),
        shared,
      );
      expect(
        const PersonalChatLook(
          mode: ChatLookMode.personal,
          look: mine,
        ).effective(shared),
        mine,
      );
      expect(
        const PersonalChatLook(mode: ChatLookMode.personal).effective(shared),
        ChatLook.standard,
      );
    });

    test('fromProfile reads mode and look', () {
      expect(PersonalChatLook.fromProfile(null).mode, ChatLookMode.shared);
      final p = PersonalChatLook.fromProfile({
        'chatLookMode': 'personal',
        'chatLook': mine.toMap(),
      });
      expect(p.mode, ChatLookMode.personal);
      expect(p.look, mine);
      expect(
        PersonalChatLook.fromProfile({'chatLookMode': 'weird'}).mode,
        ChatLookMode.shared,
      );
    });
  });

  group('patterns', () {
    test('ids are unique, labelled and enough of them', () {
      final ids = ChatPatterns.all.map((p) => p.id).toList();
      expect(ids.length, greaterThanOrEqualTo(8));
      expect(ids.toSet().length, ids.length);
      expect(ChatPatterns.all.every((p) => p.label.isNotEmpty), isTrue);
      expect(ChatPatterns.byId('nope'), isNull);
      expect(
        ChatPatterns.shows(
          const ChatBackground(
            kind: ChatBackgroundKind.pattern,
            patternId: 'from-the-future',
          ),
        ),
        isFalse,
      );
      expect(ChatPatterns.shows(ChatBackground.none), isFalse);
    });

    test('every pattern paints in light and dark at several sizes', () {
      for (final brightness in Brightness.values) {
        final scheme = ColorScheme.fromSeed(
          seedColor: AppTheme.seed,
          brightness: brightness,
        );
        for (final pattern in [
          ...ChatPatterns.all.map((p) => p.id),
          'unknown',
        ]) {
          final painter = ChatPatternPainter(
            patternId: pattern,
            scheme: scheme,
            background: scheme.surface,
          );
          for (final size in const [
            Size(1, 1),
            Size(72, 90),
            Size(411, 891),
            Size(1280, 800),
          ]) {
            final recorder = ui.PictureRecorder();
            painter.paint(Canvas(recorder), size);
            recorder.endRecording().dispose();
          }
          expect(painter.shouldRepaint(painter), isFalse);
        }
      }
    });
  });

  group('ChatPalette', () {
    test('the standard look keeps the app colours', () {
      for (final base in [AppTheme.light(), AppTheme.dark()]) {
        final theme = ChatPalette.applyTo(base, ChatLook.standard);
        final palette = theme.extension<ChatPalette>()!;
        expect(theme.colorScheme, base.colorScheme);
        expect(theme.scaffoldBackgroundColor, base.scaffoldBackgroundColor);
        expect(
          palette.theirsBubble,
          base.brightness == Brightness.dark
              ? AppTheme.bubbleTheirsDark
              : AppTheme.bubbleTheirsLight,
        );
        expect(palette.hasBackground, isFalse);
      }
    });

    test('a chosen colour reseeds the scheme', () {
      final theme = ChatPalette.applyTo(
        AppTheme.dark(),
        const ChatLook(
          colorValue: ocean,
          background: ChatBackground(
            kind: ChatBackgroundKind.pattern,
            patternId: 'dots',
          ),
        ),
      );
      final palette = theme.extension<ChatPalette>()!;
      expect(theme.brightness, Brightness.dark);
      expect(
        theme.colorScheme.primary,
        isNot(AppTheme.dark().colorScheme.primary),
      );
      expect(palette.theirsBubble, theme.colorScheme.surfaceContainerHigh);
      expect(palette.hasBackground, isTrue);
    });
  });

  group('ChatBackgroundLayer', () {
    const kinds = <String, ChatBackground>{
      'none': ChatBackground.none,
      'unknown pattern': ChatBackground(
        kind: ChatBackgroundKind.pattern,
        patternId: 'nope',
      ),
      'pattern': ChatBackground(
        kind: ChatBackgroundKind.pattern,
        patternId: 'doodles',
      ),
      'photo': ChatBackground(
        kind: ChatBackgroundKind.photo,
        photoUrl: 'https://example.com/a.jpg',
        dim: .5,
        blur: 8,
      ),
    };

    for (final MapEntry(key: name, value: bg) in kinds.entries) {
      testWidgets('renders $name', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Center(
              child: SizedBox(
                width: 300,
                height: 500,
                child: ChatBackgroundLayer(background: bg),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byType(ChatBackgroundLayer), findsOneWidget);
        expect(
          tester.getSize(find.byType(ChatBackgroundLayer)),
          const Size(300, 500),
        );
        if (name == 'pattern') {
          expect(
            find.descendant(
              of: find.byType(ChatBackgroundLayer),
              matching: find.byType(CustomPaint),
            ),
            findsOneWidget,
          );
        }
      });
    }
  });

  group('ChatAppearanceScreen', () {
    testWidgets('colour + pattern saves the shared look', (tester) async {
      final service = await pumpAppearance(tester);
      expect(find.text('Both of us'), findsOneWidget);
      expect(find.text('You both see this theme.'), findsOneWidget);

      // Nothing to save yet.
      final saveButton = find.widgetWithText(TextButton, 'Save');
      expect(tester.widget<TextButton>(saveButton).onPressed, isNull);

      await tapKey(tester, 'swatch-Ocean');
      await tapKey(tester, 'bg-hearts');
      await save(tester);

      expect(service.sharedSaves, [
        const ChatLook(
          colorValue: ocean,
          background: ChatBackground(
            kind: ChatBackgroundKind.pattern,
            patternId: 'hearts',
          ),
        ),
      ]);
      expect(service.personalSaves, isEmpty);
      expect(find.byType(ChatAppearanceScreen), findsNothing);
      expect(find.text('Chat theme updated'), findsOneWidget);
    });

    testWidgets('Just me starts from the shared look and saves personal', (
      tester,
    ) async {
      const sunset = ChatBackground(
        kind: ChatBackgroundKind.pattern,
        patternId: 'sunset',
      );
      final service = await pumpAppearance(
        tester,
        shared: SharedChatLook(
          look: const ChatLook(colorValue: ocean, background: sunset),
          updatedBy: partner,
          updatedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );
      expect(find.text('Ravi changed this 2 days ago'), findsOneWidget);

      await tester.tap(find.text('Just me'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Only you see this'), findsOneWidget);

      await tapKey(tester, 'swatch-Plum');
      await save(tester);

      expect(service.sharedSaves, isEmpty);
      expect(service.personalSaves, hasLength(1));
      expect(service.personalSaves.single.mode, ChatLookMode.personal);
      expect(
        service.personalSaves.single.look,
        const ChatLook(colorValue: plum, background: sunset),
      );
    });

    testWidgets('back to Both of us keeps the personal look', (tester) async {
      final service = await pumpAppearance(
        tester,
        personal: const PersonalChatLook(
          mode: ChatLookMode.personal,
          look: ChatLook(colorValue: plum),
        ),
      );
      await tester.tap(find.text('Both of us'));
      await tester.pumpAndSettle();
      await save(tester);

      expect(service.sharedSaves, isEmpty);
      expect(service.personalSaves.single.mode, ChatLookMode.shared);
      expect(service.personalSaves.single.look, isNull);
    });

    testWidgets('replacing an uploaded photo deletes the old one', (
      tester,
    ) async {
      final service = await pumpAppearance(
        tester,
        shared: const SharedChatLook(
          look: ChatLook(
            background: ChatBackground(
              kind: ChatBackgroundKind.photo,
              photoUrl: 'https://example.com/old.jpg',
              storagePath: 'couples/c1/backgrounds/old.jpg',
            ),
          ),
        ),
      );
      // Photo controls show for a photo background.
      await scrollTo(tester, find.text('Dim'));
      expect(find.text('Dim'), findsOneWidget);
      expect(find.text('Blur'), findsOneWidget);

      await tapKey(tester, 'bg-dots');
      expect(find.text('Dim'), findsNothing);
      await save(tester);

      expect(service.sharedSaves.single.background.patternId, 'dots');
      expect(service.deleted, ['couples/c1/backgrounds/old.jpg']);
    });

    testWidgets('reset and dark mode fit at 360×740', (tester) async {
      final service = await pumpAppearance(
        tester,
        brightness: Brightness.dark,
        shared: const SharedChatLook(
          look: ChatLook(
            colorValue: ocean,
            background: ChatBackground(
              kind: ChatBackgroundKind.pattern,
              patternId: 'confetti',
            ),
          ),
        ),
      );
      final reset = find.text('Reset to default');
      await scrollTo(tester, reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      await save(tester);

      expect(service.sharedSaves, [ChatLook.standard]);
      expect(tester.takeException(), isNull);
    });
  });
}
