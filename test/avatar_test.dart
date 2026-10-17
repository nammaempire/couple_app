import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/data/avatar_service.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/painting/avatar_painter.dart';
import 'package:couple_app/features/avatar/providers/avatar_providers.dart';
import 'package:couple_app/features/avatar/screens/avatar_builder_screen.dart';
import 'package:couple_app/features/avatar/widgets/avatar_option_tile.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';
import 'package:couple_app/features/avatar/widgets/profile_avatar.dart';
import 'package:couple_app/features/calls/widgets/partner_initial_avatar.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/home/providers/home_providers.dart';
import 'package:couple_app/features/us/screens/us_screen.dart';

/// Records saves instead of writing to Firestore.
class _FakeAvatarService extends AvatarService {
  final saves = <({String uid, AvatarConfig avatar, bool asPhoto})>[];

  @override
  Future<void> save({
    required String uid,
    required AvatarConfig avatar,
    required bool asProfilePicture,
  }) async {
    saves.add((uid: uid, avatar: avatar, asPhoto: asProfilePicture));
  }

  @override
  Future<void> setAsProfilePicture({
    required String uid,
    required bool value,
  }) async {}
}

class _FakeAuthService implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoupleService implements CoupleService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Every option of every part, each applied to the default avatar.
List<AvatarConfig> _everyOption() {
  const base = AvatarConfig();
  return [
    for (final o in AvatarConfig.skins) base.copyWith(skin: o.id),
    for (final o in AvatarConfig.faces) base.copyWith(face: o.id),
    for (final o in AvatarConfig.hairs) base.copyWith(hair: o.id),
    for (final o in AvatarConfig.hairColors) base.copyWith(hairColor: o.id),
    for (final o in AvatarConfig.eyeStyles) base.copyWith(eyes: o.id),
    for (final o in AvatarConfig.eyeColors) base.copyWith(eyeColor: o.id),
    for (final o in AvatarConfig.browStyles) base.copyWith(brows: o.id),
    for (final o in AvatarConfig.facialHairs) base.copyWith(facialHair: o.id),
    for (final o in AvatarConfig.glassesStyles) base.copyWith(glasses: o.id),
    for (final o in AvatarConfig.accessories) base.copyWith(accessory: o.id),
    for (final o in AvatarConfig.faceAccessories)
      base.copyWith(faceAccessory: o.id),
    // A bindi with every head accessory, and head coverings on every face
    // shape and over long hair.
    for (final o in AvatarConfig.accessories)
      base.copyWith(faceAccessory: 'bindi', accessory: o.id),
    for (final face in AvatarConfig.faces)
      for (final cover in const ['turban', 'headscarf'])
        base.copyWith(
          face: face.id,
          accessory: cover,
          hair: 'long',
          glasses: 'round',
          facialHair: 'beard',
        ),
    for (final o in AvatarConfig.outfits) base.copyWith(outfit: o.id),
    for (final o in AvatarConfig.outfitColors) base.copyWith(outfitColor: o.id),
    for (final o in AvatarConfig.backgrounds) base.copyWith(background: o.id),
  ];
}

void main() {
  group('AvatarConfig', () {
    test('round-trips through a map', () {
      const config = AvatarConfig(
        skin: 'skin6',
        face: 'heart',
        hair: 'braids',
        hairColor: 'auburn',
        eyes: 'lashes',
        eyeColor: 'green',
        brows: 'arched',
        facialHair: 'goatee',
        glasses: 'sun',
        accessory: 'flower',
        faceAccessory: 'bindi',
        outfit: 'saree',
        outfitColor: 'lilac',
        background: 'mint',
      );
      expect(AvatarConfig.fromMap(config.toMap()), config);
    });

    test('no map means no avatar', () {
      expect(AvatarConfig.fromMap(null), isNull);
      expect(AvatarConfig.fromMap('nope'), isNull);
    });

    test('unknown or missing ids fall back to the field defaults', () {
      const defaults = AvatarConfig();
      final config = AvatarConfig.fromMap({
        'skin': 'skin99',
        'face': 'triangle',
        'hair': 'mohawk',
        'hairColor': 42,
        'eyeColor': 'violet',
        'faceAccessory': 'nose-ring',
        'outfit': 'spacesuit',
        'outfitColor': 'gold',
        'background': 'space',
      })!;
      // An unknown future skin tone must not become the lightest one.
      expect(config.skin, 'skin3');
      expect(config.skin, isNot(AvatarConfig.skins.first.id));
      expect(config.face, 'oval');
      expect(config.hair, 'short');
      expect(config.hairColor, 'black');
      expect(config.eyeColor, defaults.eyeColor);
      expect(config.faceAccessory, 'none');
      expect(config.outfit, defaults.outfit);
      expect(config.outfitColor, defaults.outfitColor);
      expect(config.background, defaults.background);
      // Missing fields too.
      expect(config.glasses, defaults.glasses);
      expect(config.brows, defaults.brows);
      expect(AvatarConfig.fromMap(<String, dynamic>{}), defaults);
    });

    test('colour lookups for unknown ids use the defaults', () {
      const odd = AvatarConfig(skin: 'skin99', hairColor: 'nope');
      expect(odd.skinColor, const AvatarConfig().skinColor);
      expect(odd.hairTint, const AvatarConfig().hairTint);
    });

    test('a bindi combines with head accessories; old bindis still load', () {
      final legacy = AvatarConfig.fromMap({'accessory': 'bindi'})!;
      expect(legacy.accessory, 'bindi');
      expect(legacy.faceAccessory, 'none');
      expect(legacy.hasBindi, isTrue);
      final moved = legacy.withBindiOnFace;
      expect(moved.accessory, 'none');
      expect(moved.faceAccessory, 'bindi');
      expect(moved.hasBindi, isTrue);

      const both = AvatarConfig(faceAccessory: 'bindi', accessory: 'earrings');
      expect(AvatarConfig.fromMap(both.toMap()), both);
      expect(both.withBindiOnFace, both);
      expect(both.hasBindi, isTrue);
      expect(const AvatarConfig(accessory: 'earrings').hasBindi, isFalse);
      expect(
        AvatarConfig.headAccessories.map((o) => o.id),
        containsAll(['turban', 'headscarf']),
      );
      expect(
        AvatarConfig.headAccessories.map((o) => o.id),
        isNot(contains('bindi')),
      );
    });

    test('random() always picks valid options', () {
      for (var seed = 0; seed < 300; seed++) {
        final config = AvatarConfig.random(Random(seed));
        expect(AvatarConfig.fromMap(config.toMap()), config, reason: '$seed');
      }
    });
  });

  group('AvatarPainter', () {
    test('paints every option with every expression at several sizes', () {
      final configs = _everyOption();
      for (final config in configs) {
        for (final expression in AvatarExpression.values) {
          for (final size in const [32.0, 48.0, 200.0]) {
            final recorder = ui.PictureRecorder();
            AvatarPainter(
              config: config,
              expression: expression,
            ).paint(Canvas(recorder), Size.square(size));
            recorder.endRecording().dispose();
          }
        }
      }
    });

    test('paints head-only, mirrored and without background', () {
      for (final config in _everyOption()) {
        for (final expression in AvatarExpression.values) {
          final recorder = ui.PictureRecorder();
          AvatarPainter(
            config: config,
            expression: expression,
            showShoulders: false,
            showBackground: false,
            mirror: true,
          ).paint(Canvas(recorder), const Size.square(96));
          recorder.endRecording().dispose();
        }
      }
    });

    test('repaints only when something changes', () {
      AvatarPainter painter(AvatarConfig c, [bool mirror = false]) =>
          AvatarPainter(
            config: c,
            expression: AvatarExpression.happy,
            mirror: mirror,
          );
      const a = AvatarConfig();
      expect(painter(a).shouldRepaint(painter(a)), isFalse);
      expect(
        painter(a).shouldRepaint(painter(a.copyWith(hair: 'bun'))),
        isTrue,
      );
      expect(painter(a).shouldRepaint(painter(a, true)), isTrue);
    });

    testWidgets('AvatarView keeps its square size', (tester) async {
      await tester.pumpWidget(
        const Center(child: AvatarView(config: AvatarConfig(), size: 48)),
      );
      expect(tester.getSize(find.byType(AvatarView)), const Size(48, 48));
    });
  });

  group('ProfileAvatar', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

    testWidgets('shows the initial when there is no profile', (tester) async {
      await pump(tester, const ProfileAvatar(user: null, fallbackName: 'ravi'));
      expect(find.text('R'), findsOneWidget);
      expect(find.byType(AvatarView), findsNothing);
    });

    testWidgets('shows the initial for a profile without photo or avatar', (
      tester,
    ) async {
      await pump(
        tester,
        const ProfileAvatar(
          user: AppUser(uid: 'u', displayName: 'Asha'),
        ),
      );
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('shows the avatar when there is no photo', (tester) async {
      await pump(
        tester,
        const ProfileAvatar(
          user: AppUser(uid: 'u', displayName: 'Asha', avatar: AvatarConfig()),
          size: 64,
        ),
      );
      expect(find.byType(AvatarView), findsOneWidget);
      expect(find.text('A'), findsNothing);
      expect(tester.getSize(find.byType(AvatarView)), const Size(64, 64));
    });

    testWidgets('respects turning the avatar off', (tester) async {
      await pump(
        tester,
        const ProfileAvatar(
          user: AppUser(
            uid: 'u',
            displayName: 'Asha',
            avatar: AvatarConfig(),
            avatarAsPhoto: false,
          ),
        ),
      );
      expect(find.byType(AvatarView), findsNothing);
      expect(find.text('A'), findsOneWidget);
    });
  });

  group('PartnerInitialAvatar', () {
    Future<StreamController<AppUser?>> pump(WidgetTester tester) async {
      final partner = StreamController<AppUser?>();
      addTearDown(partner.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [partnerProvider.overrideWith((ref) => partner.stream)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: Center(
                child: PartnerInitialAvatar(
                  name: 'Ravi',
                  size: 120,
                  fontSize: 48,
                ),
              ),
            ),
          ),
        ),
      );
      return partner;
    }

    Future<void> emit(
      WidgetTester tester,
      StreamController<AppUser?> partner,
      AppUser user,
    ) async {
      partner.add(user);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows the initial while the profile loads', (tester) async {
      final partner = await pump(tester);
      expect(find.text('R'), findsOneWidget);
      expect(find.byType(AvatarView), findsNothing);

      // Then their avatar, once it's known they show it.
      await emit(
        tester,
        partner,
        const AppUser(
          uid: 'ravi',
          displayName: 'Ravi',
          avatar: AvatarConfig(),
          avatarAsPhoto: true,
        ),
      );
      expect(find.byType(AvatarView), findsOneWidget);
      expect(find.text('R'), findsNothing);
    });

    testWidgets('respects a partner who keeps their photo', (tester) async {
      final partner = await pump(tester);
      await emit(
        tester,
        partner,
        const AppUser(
          uid: 'ravi',
          displayName: 'Ravi',
          photoUrl: 'https://example.com/ravi.jpg',
          avatar: AvatarConfig(),
        ),
      );
      expect(find.byType(AvatarView), findsNothing);
      expect(find.text('R'), findsOneWidget);

      await emit(
        tester,
        partner,
        const AppUser(
          uid: 'ravi',
          displayName: 'Ravi',
          avatar: AvatarConfig(),
          avatarAsPhoto: false,
        ),
      );
      expect(find.byType(AvatarView), findsNothing);
    });

    testWidgets('shows the avatar when there is no photo', (tester) async {
      final partner = await pump(tester);
      await emit(
        tester,
        partner,
        const AppUser(uid: 'ravi', displayName: 'Ravi', avatar: AvatarConfig()),
      );
      expect(find.byType(AvatarView), findsOneWidget);
    });
  });

  group('Us screen avatar switch', () {
    Future<void> pump(WidgetTester tester, AppUser me) async {
      tester.view.physicalSize = const Size(360, 1600) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // A fresh scope for each profile.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithBuild((ref, notifier) => me),
            authServiceProvider.overrideWithValue(_FakeAuthService()),
            coupleServiceProvider.overrideWithValue(_FakeCoupleService()),
            coupleProvider.overrideWith(
              (ref) => Stream.value(
                const Couple(
                  id: 'c1',
                  inviteCode: 'X',
                  memberIds: ['me', 'ravi'],
                ),
              ),
            ),
            partnerNameProvider.overrideWithValue('Ravi'),
            questionHistoryProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const UsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says what the avatar replaces', (tester) async {
      await pump(
        tester,
        const AppUser(
          uid: 'me',
          displayName: 'Asha',
          coupleId: 'c1',
          avatar: AvatarConfig(),
        ),
      );
      expect(find.text('Use avatar as profile picture'), findsOneWidget);
      expect(find.text('Shown wherever your picture appears'), findsOneWidget);
      expect(find.text('Instead of your photo'), findsNothing);

      await pump(
        tester,
        const AppUser(
          uid: 'me',
          displayName: 'Asha',
          coupleId: 'c1',
          photoUrl: 'https://example.com/me.jpg',
          avatar: AvatarConfig(),
        ),
      );
      expect(find.text('Instead of your photo'), findsOneWidget);
    });
  });

  group('AvatarBuilderScreen', () {
    late _FakeAvatarService service;

    setUp(() => service = _FakeAvatarService());

    Future<void> showTab(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> open(
      WidgetTester tester, {
      AppUser me = const AppUser(uid: 'me', displayName: 'Asha'),
      ThemeMode themeMode = ThemeMode.light,
    }) async {
      tester.view.physicalSize = const Size(360, 740) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithBuild((ref, notifier) => me),
            avatarServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AvatarBuilderScreen(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('picks a hair style and colour, then saves them', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Your avatar'), findsOneWidget);

      await showTab(tester, 'Hair');
      await tester.tap(
        find.byKey(const ValueKey('avatar-swatch-hairColor-auburn')),
      );
      await tester.pump();

      final curly = find.byKey(const ValueKey('avatar-option-hair-curly'));
      await tester.scrollUntilVisible(
        curly,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(curly);
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(service.saves, hasLength(1));
      final saved = service.saves.single;
      expect(saved.uid, 'me');
      expect(saved.avatar.hair, 'curly');
      expect(saved.avatar.hairColor, 'auburn');
      // A first avatar with no photo becomes the profile picture.
      expect(saved.asPhoto, isTrue);
      expect(find.text('Avatar saved'), findsOneWidget);
      expect(find.byType(AvatarBuilderScreen), findsNothing);
    });

    testWidgets('starts from my avatar; off as picture when I have a photo', (
      tester,
    ) async {
      await open(
        tester,
        me: const AppUser(
          uid: 'me',
          displayName: 'Asha',
          photoUrl: 'https://example.com/me.jpg',
          avatar: AvatarConfig(hair: 'bun', outfit: 'kurta'),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = service.saves.single;
      expect(saved.avatar.hair, 'bun');
      expect(saved.avatar.outfit, 'kurta');
      expect(saved.asPhoto, isFalse);
    });

    testWidgets('undo and surprise me change the preview', (tester) async {
      await open(tester);
      AvatarConfig preview() =>
          tester.widget<AvatarView>(find.byType(AvatarView).first).config;
      final start = preview();

      await showTab(tester, 'Glasses');
      await tester.tap(find.byKey(const ValueKey('avatar-option-glasses-sun')));
      await tester.pump();
      expect(preview().glasses, 'sun');

      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(preview(), start);

      await tester.tap(find.byTooltip('Surprise me'));
      await tester.pump();
      // Every tab switch and tap so far has rendered without overflow.
      expect(tester.takeException(), isNull);
    });

    testWidgets('asks before discarding unsaved changes', (tester) async {
      await open(tester, themeMode: ThemeMode.dark);
      await showTab(tester, 'Background');
      await tester.tap(
        find.byKey(const ValueKey('avatar-swatch-background-mint')),
      );
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarBuilderScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarBuilderScreen), findsNothing);
      expect(service.saves, isEmpty);
    });

    testWidgets('a bindi goes with earrings; head coverings are offered', (
      tester,
    ) async {
      // An older avatar with the bindi stored as its head accessory.
      await open(
        tester,
        me: const AppUser(
          uid: 'me',
          displayName: 'Asha',
          avatar: AvatarConfig(accessory: 'bindi'),
          avatarAsPhoto: true,
        ),
      );
      await showTab(tester, 'Extras');
      expect(find.text('Face'), findsWidgets);
      expect(find.text('Head & ears'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('avatar-option-accessory-bindi')),
        findsNothing,
      );

      AvatarOptionTile tile(String key) =>
          tester.widget<AvatarOptionTile>(find.byKey(ValueKey(key)));
      expect(tile('avatar-option-faceAccessory-bindi').selected, isTrue);
      expect(tile('avatar-option-accessory-none').selected, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('avatar-option-accessory-earrings')),
      );
      await tester.pump();
      for (final cover in const ['turban', 'headscarf']) {
        final option = find.byKey(ValueKey('avatar-option-accessory-$cover'));
        await tester.scrollUntilVisible(
          option,
          100,
          scrollable: find.byType(Scrollable).last,
        );
        expect(option, findsOneWidget);
      }
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = service.saves.single.avatar;
      expect(saved.faceAccessory, 'bindi');
      expect(saved.accessory, 'earrings');
    });

    testWidgets('every tab fits at 360 × 740', (tester) async {
      await open(tester);
      for (final tab in const [
        'Skin',
        'Face',
        'Hair',
        'Eyes',
        'Brows',
        'Facial hair',
        'Glasses',
        'Extras',
        'Outfit',
        'Background',
      ]) {
        await showTab(tester, tab);
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  });
}
