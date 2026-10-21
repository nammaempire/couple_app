import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/core/services/screen_privacy.dart';
import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/vault/data/device_keystore.dart';
import 'package:couple_app/features/vault/models/vault_event.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/screens/vault_screen.dart';
import 'package:couple_app/features/vault/widgets/vault_code_pad.dart';
import 'package:couple_app/features/vault/widgets/vault_items.dart';
import 'package:couple_app/features/vault/widgets/vault_us_row.dart';

import 'vault_fakes.dart';

class _FakeAuth implements AuthService {
  int adultConfirmations = 0;

  @override
  Future<void> confirmAdult() async => adultConfirmations++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSecurity implements ScreenSecurity {
  final calls = <bool>[];

  bool get secure => calls.isNotEmpty && calls.last;

  @override
  Future<void> setSecure(bool secure) async => calls.add(secure);
}

class _FakeDetector implements ScreenshotDetector {
  @override
  Stream<void> get screenshots => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

/// A plain screen with a button that opens the vault, so tests can leave it.
class _Opener extends StatelessWidget {
  const _Opener({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      children: [
        ?child,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.of(c).push(VaultScreen.route()),
            child: const Text('open vault'),
          ),
        ),
      ],
    ),
  );
}

void main() {
  late VaultTestRig rig;
  late VaultTestPhone ashaPhone;
  late VaultTestPhone raviPhone;
  late _FakeAuth auth;
  late _FakeSecurity security;

  setUp(() {
    rig = VaultTestRig();
    ashaPhone = VaultTestPhone(uid: asha, name: 'Pixel 8', seed: 1);
    raviPhone = VaultTestPhone(uid: ravi, name: 'Galaxy S23', seed: 2);
    auth = _FakeAuth();
    security = _FakeSecurity();
    // No "use your fingerprint?" question unless a test asks for it.
    rig.biometrics.available = false;
  });

  Future<void> pump(
    WidgetTester tester, {
    AppUser? me,
    AppUser? partner,
    VaultTestPhone? phone,
    Widget? child,
  }) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ...vaultPeopleOverrides(
            me: me ?? vaultUser(asha),
            partner: partner ?? vaultUser(ravi),
          ),
          ...rig.overrides(phone ?? ashaPhone),
          authServiceProvider.overrideWithValue(auth),
          screenSecurityProvider.overrideWithValue(security),
          screenshotDetectorProvider.overrideWithValue(_FakeDetector()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: _Opener(child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openVault(WidgetTester tester) async {
    await tester.tap(find.text('open vault'));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String code) async {
    for (final d in code.split('')) {
      await tester.tap(
        find.descendant(
          of: find.byType(VaultNumberPad),
          matching: find.text(d),
        ),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  group('Us row', () {
    testWidgets('reads "Private", and opens setup for a new vault', (
      tester,
    ) async {
      await pump(tester, child: const VaultUsRow());
      expect(find.text('🔒'), findsOneWidget);
      expect(find.text('Private'), findsOneWidget);
      expect(find.text('Only for the two of you'), findsOneWidget);
      expect(find.byKey(const Key('vault-alert-dot')), findsNothing);

      await tester.tap(find.text('Private'));
      await tester.pumpAndSettle();
      expect(find.text('A private space,\njust for you two'), findsOneWidget);
    });

    testWidgets('shows a dot for the partner\'s alerts only', (tester) async {
      await rig.service.addEvent(
        cid: vaultCouple,
        type: VaultEventType.codeChanged,
        uid: asha,
        deviceName: 'Pixel 8',
      );
      await pump(tester, child: const VaultUsRow());
      expect(find.byKey(const Key('vault-alert-dot')), findsNothing);
      await rig.service.addEvent(
        cid: vaultCouple,
        type: VaultEventType.wrongCode,
        uid: ravi,
        deviceName: 'Galaxy S23',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vault-alert-dot')), findsOneWidget);
    });
  });

  group('age gate', () {
    testWidgets('a partner under 18 makes the vault unavailable', (
      tester,
    ) async {
      final now = DateTime.now();
      await pump(
        tester,
        partner: vaultUser(ravi, birthday: DateTime(now.year - 17, 1, 1)),
      );
      await openVault(tester);
      expect(find.text('Private isn\'t available'), findsOneWidget);
      expect(find.byType(VaultNumberPad), findsNothing);
      // Even a stored confirmation doesn't override a birthday.
      expect(find.textContaining('18 or older'), findsOneWidget);
    });

    testWidgets('no birthday: confirm you are 18+', (tester) async {
      await pump(tester, me: vaultUser(asha, noBirthday: true));
      await openVault(tester);
      expect(find.text('Just for grown-ups'), findsOneWidget);
      await tester.tap(find.text('I\'m 18 or older'));
      await tester.pumpAndSettle();
      expect(auth.adultConfirmations, 1);
    });

    testWidgets('a confirmation counts when there is no birthday', (
      tester,
    ) async {
      await pump(
        tester,
        me: vaultUser(
          asha,
          noBirthday: true,
          adultConfirmedAt: DateTime(2026, 10, 1),
        ),
        partner: vaultUser(ravi, noBirthday: true),
      );
      await openVault(tester);
      expect(find.text('Waiting for Ravi'), findsOneWidget);
    });
  });

  testWidgets('setup: explain, code twice, decoy twice, done', (tester) async {
    rig.biometrics.available = true;
    await pump(tester);
    await openVault(tester);
    expect(find.text('Not even we can see it'), findsOneWidget);
    expect(
      find.text('If both phones are lost, it\'s gone for good'),
      findsOneWidget,
    );
    expect(security.secure, isTrue);

    await tester.tap(find.text('Choose a code'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your code'), findsOneWidget);
    await enter(tester, realCode);
    expect(find.text('Once more'), findsOneWidget);
    await enter(tester, '999999');
    expect(find.byKey(const Key('vault-setup-hint')), findsOneWidget);
    expect(find.text('Choose your code'), findsOneWidget);
    await enter(tester, realCode);
    await enter(tester, realCode);

    expect(find.text('Now a decoy code'), findsOneWidget);
    await enter(tester, realCode);
    expect(
      find.text('The decoy code must be different from your code.'),
      findsOneWidget,
    );
    await enter(tester, decoyCode);
    await enter(tester, decoyCode);

    expect(find.text('Open with your\nfingerprint or face?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Your vault is ready'), findsOneWidget);
    expect(find.text('Tell Ravi the code in person'), findsOneWidget);

    await tester.tap(find.text('Open the vault'));
    await tester.pumpAndSettle();
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(await rig.service.getMeta(vaultCouple), isNotNull);
  });

  group('lock screen', () {
    testWidgets('wrong code stays locked; the right one opens', (tester) async {
      await rig.seedVault(ashaPhone);
      await pump(tester);
      await openVault(tester);
      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.byType(VaultNumberPad), findsOneWidget);
      // No system keyboard.
      expect(find.byType(TextField), findsNothing);

      await enter(tester, '000000');
      expect(find.text('Enter your code'), findsOneWidget);
      expect(find.text('Photos'), findsNothing);

      await enter(tester, realCode);
      expect(find.text('Photos'), findsOneWidget);
    });

    testWidgets('five wrong codes show the cooldown', (tester) async {
      await rig.seedVault(ashaPhone);
      await pump(tester);
      await openVault(tester);
      for (var i = 0; i < 5; i++) {
        await enter(tester, '000000');
      }
      expect(find.text('Too many tries. Try again in 0:30'), findsOneWidget);
      rig.clock.advance(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Enter your code'), findsOneWidget);
    });

    testWidgets('"Forgot code?" explains the partner reset', (tester) async {
      await rig.seedVault(ashaPhone);
      await pump(tester);
      await openVault(tester);
      await tester.tap(find.text('Forgot code?'));
      await tester.pumpAndSettle();
      expect(find.text('Forgot the code?'), findsOneWidget);
      expect(find.textContaining('Change code'), findsOneWidget);
    });

    testWidgets('the fingerprint key shows once it is on', (tester) async {
      await rig.seedVault(ashaPhone);
      ashaPhone.keystore.states[asha] = const VaultLocalState(
        biometric: true,
        biometricAsked: true,
      );
      rig.biometrics.result = false;
      await pump(tester);
      await openVault(tester);
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      rig.biometrics.result = true;
      await tester.tap(find.byIcon(Icons.fingerprint));
      await tester.pumpAndSettle();
      expect(find.text('Photos'), findsOneWidget);
    });
  });

  group('open vault', () {
    Future<void> seedAndOpen(WidgetTester tester) async {
      final seeded = await rig.seedVault(ashaPhone);
      await rig.seedMessage(
        crypto: ashaPhone.crypto,
        shelfKey: seeded.keys.vmk,
        shelf: 'a',
        senderId: ravi,
        text: 'Miss you already',
      );
      await rig.seedMessage(
        crypto: ashaPhone.crypto,
        shelfKey: seeded.keys.vmk,
        shelf: 'a',
        senderId: ravi,
        text: 'only once',
        policy: VaultPolicy.once,
      );
      await rig.seedPhoto(
        crypto: ashaPhone.crypto,
        shelfKey: seeded.keys.vmk,
        shelf: 'a',
        senderId: asha,
        policy: VaultPolicy.day,
      );
      // On the decoy shelf: never shown here.
      await rig.seedMessage(
        crypto: ashaPhone.crypto,
        shelfKey: seeded.keys.dk,
        shelf: 'b',
        senderId: asha,
        text: 'decoy text',
      );
      await pump(tester);
      await openVault(tester);
      await enter(tester, realCode);
    }

    testWidgets('photos grid, chat bubbles and sending', (tester) async {
      await seedAndOpen(tester);
      expect(find.byType(VaultPhotoTile), findsOneWidget);
      expect(find.text('⏳'), findsOneWidget);

      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.text('Miss you already'), findsOneWidget);
      expect(find.text('decoy text'), findsNothing);
      // A view-once message stays covered until opened.
      expect(find.text('only once'), findsNothing);
      expect(find.text('👁  Tap to read once'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Same here');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Same here'), findsOneWidget);
      final mine = (await rig.service.getItems(
        vaultCouple,
      )).where((i) => i.senderId == asha && i.kind == VaultItemKind.message);
      final sent = mine.where((i) => i.shelf == 'a');
      expect(sent, hasLength(1));
      expect(sent.single.ct, isNot(contains('Same here')));
    });

    testWidgets('reading once deletes the message', (tester) async {
      await seedAndOpen(tester);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('👁  Tap to read once'));
      await tester.pumpAndSettle();
      expect(find.text('👁  Viewing once'), findsOneWidget);
      expect(find.text('only once'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('only once'), findsNothing);
      expect(find.text('👁  Tap to read once'), findsNothing);
      final texts = await rig.service.getItems(vaultCouple);
      expect(texts.where((i) => i.policy == VaultPolicy.once), isEmpty);
    });

    testWidgets('adding a photo: pick, choose how long, upload', (
      tester,
    ) async {
      await seedAndOpen(tester);
      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from gallery'));
      await tester.pumpAndSettle();
      expect(find.text('How long should it last?'), findsOneWidget);
      await tester.tap(find.text('View once'));
      await tester.pump();
      await tester.tap(find.text('Add to Private'));
      await tester.pumpAndSettle();
      final photos = (await rig.service.getItems(
        vaultCouple,
      )).where((i) => i.kind == VaultItemKind.photo).toList();
      expect(photos, hasLength(2));
      expect(photos.where((p) => p.policy == VaultPolicy.once), hasLength(1));
      expect(rig.photos.sources.single.name, 'gallery');
    });

    testWidgets('the menu has the codes, devices and the danger zone', (
      tester,
    ) async {
      await seedAndOpen(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Change code'), findsOneWidget);
      expect(find.text('Change decoy code'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
      await tester.tap(find.text('Delete vault for both'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'Delete for both');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('vault-wipe-confirm')),
        'delete',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(await rig.service.getMeta(vaultCouple), isNull);
      expect(find.text('open vault'), findsOneWidget);
    });

    testWidgets('locks after two idle minutes and when left', (tester) async {
      await seedAndOpen(tester);
      expect(find.text('Photos'), findsOneWidget);
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(find.text('Enter your code'), findsOneWidget);

      await enter(tester, realCode);
      expect(find.text('Photos'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(security.secure, isFalse);
      await openVault(tester);
      expect(find.text('Enter your code'), findsOneWidget);
    });
  });

  testWidgets('an open vault asks to approve the partner\'s phone', (
    tester,
  ) async {
    await rig.seedVault(ashaPhone);
    final raviId = await rig.addPhone(raviPhone);
    await pump(tester);
    await openVault(tester);
    await enter(tester, realCode);
    expect(find.text('Approve Ravi\'s phone (Galaxy S23)?'), findsOneWidget);
    final shown = tester.widget<Text>(
      find.byKey(const Key('vault-approve-fingerprint')),
    );
    expect(shown.data, matches(RegExp(r'^\d{4} \d{4} \d{4} \d{4}$')));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    final meta = (await rig.service.getMeta(vaultCouple))!;
    expect(meta.devices[raviId.deviceId]!.approved, isTrue);
    expect(meta.keys.containsKey(raviId.deviceId), isTrue);
    expect(find.text('Approve Ravi\'s phone (Galaxy S23)?'), findsNothing);
  });

  testWidgets('a new phone registers and waits for approval', (tester) async {
    await rig.seedVault(ashaPhone);
    await pump(
      tester,
      me: vaultUser(ravi),
      partner: vaultUser(asha),
      phone: raviPhone,
    );
    await openVault(tester);
    await tester.pumpAndSettle();
    expect(find.text('Waiting for Asha to approve this phone'), findsOneWidget);
    expect(find.text('SAFETY CODE'), findsOneWidget);
    final meta = (await rig.service.getMeta(vaultCouple))!;
    expect(meta.pending.single.uid, ravi);
  });
}
