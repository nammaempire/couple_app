import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/books/data/book_pdf_builder.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/premium/data/billing_gateway.dart';
import 'package:couple_app/features/premium/data/purchase_verifier.dart';
import 'package:couple_app/features/premium/models/gift.dart';
import 'package:couple_app/features/premium/models/products.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';
import 'package:couple_app/features/premium/screens/gift_composer_screen.dart';
import 'package:couple_app/features/premium/screens/gift_reveal_screen.dart';
import 'package:couple_app/features/premium/screens/premium_screen.dart';
import 'package:couple_app/features/premium/widgets/unopened_gift_card.dart';

import 'pairing_fakes.dart';
import 'premium_fakes.dart';

void main() {
  late BookFonts fonts;
  late PairingRig pairing;
  late PremiumRig rig;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    fonts = await BookFonts.load();
  });

  setUp(() async {
    pairing = PairingRig();
    rig = PremiumRig(pairing, fonts: fonts);
    await pairing.seedCouple();
  });

  /// Providers with Asha signed in.
  Future<ProviderContainer> container() async {
    final c = ProviderContainer(
      overrides: rig.overrides(pAsha),
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<Map<String, dynamic>> coupleData() async =>
      (await pairing.couple.get()).data()!;

  group('purchase flow', () {
    test('buy a book: verify, acknowledge, consume, success', () async {
      final c = await container();
      final controller = c.read(purchaseControllerProvider.notifier);
      await controller.buy(Products.bookSingle, coupleId: pCouple);
      expect(rig.billing.bought, [Products.bookSingle]);
      expect(c.read(purchaseControllerProvider).phase, PurchasePhase.buying);

      rig.verifier.result = const VerifyResult(
        status: 'granted',
        bookCredits: 1,
      );
      rig.billing.paid(Products.bookSingle, token: 'tok-1');
      await settle();

      final claim = rig.verifier.claims.single;
      expect(claim.toData(), {
        'coupleId': pCouple,
        'productId': Products.bookSingle,
        'purchaseToken': 'tok-1',
        'packageName': 'com.nammaempire.together',
      });
      expect(rig.billing.completed, [Products.bookSingle]);
      expect(rig.billing.consumed, [Products.bookSingle]);
      final state = c.read(purchaseControllerProvider);
      expect(state.phase, PurchasePhase.success);
      expect(state.result!.bookCredits, 1);
      // The client never writes credits or Premium itself.
      expect((await coupleData()).containsKey('bookCredits'), isFalse);
    });

    test('a subscription is acknowledged but never consumed', () async {
      final c = await container();
      await c
          .read(purchaseControllerProvider.notifier)
          .buy(Products.premiumYearly, coupleId: pCouple);
      rig.billing.paid(Products.premiumYearly);
      await settle();
      expect(rig.billing.completed, [Products.premiumYearly]);
      expect(rig.billing.consumed, isEmpty);
    });

    test(
      'server unavailable: kept pending, nothing granted or finished',
      () async {
        final c = await container();
        rig.verifier.error = VerifyException(VerifyFailure.unavailable);
        await c
            .read(purchaseControllerProvider.notifier)
            .buy(Products.premiumMonthly, coupleId: pCouple);
        rig.billing.paid(Products.premiumMonthly, token: 'tok-2');
        await settle();

        final state = c.read(purchaseControllerProvider);
        expect(state.phase, PurchasePhase.waitingForServer);
        expect(
          state.message,
          'Payment received — waiting for the server to confirm.',
        );
        expect(state.pending, 1);
        expect(rig.billing.completed, isEmpty);
        expect(rig.billing.consumed, isEmpty);
        expect((await rig.pending.load()).single.purchaseToken, 'tok-2');
        expect((await coupleData()).containsKey('premium'), isFalse);

        // Back in the app, the server is there now.
        rig.verifier.error = null;
        rig.billing.owned.add(
          const BillingPurchase(
            productId: Products.premiumMonthly,
            status: BillingPurchaseStatus.restored,
            token: 'tok-2',
          ),
        );
        await c.read(purchaseControllerProvider.notifier).retryPending();
        await settle();
        expect(await rig.pending.load(), isEmpty);
        expect(rig.billing.restores, 1);
        // The restore lets the store's copy be acknowledged too.
        expect(rig.billing.completed, [Products.premiumMonthly]);
        expect(c.read(purchaseControllerProvider).pending, 0);
      },
    );

    test('restore verifies what the store sends back', () async {
      final c = await container();
      rig.billing.owned.add(
        const BillingPurchase(
          productId: Products.premiumYearly,
          status: BillingPurchaseStatus.restored,
          token: 'tok-y',
        ),
      );
      await c.read(purchaseControllerProvider.notifier).restore(pCouple);
      await settle();
      expect(rig.verifier.claims.single.purchaseToken, 'tok-y');
      expect(rig.verifier.claims.single.coupleId, pCouple);
      expect(rig.billing.completed, [Products.premiumYearly]);
      expect(c.read(purchaseControllerProvider).phase, PurchasePhase.success);
    });

    test('start-up refresh re-verifies a subscription quietly', () async {
      final c = await container();
      rig.verifier.result = const VerifyResult(status: 'alreadyGranted');
      rig.billing.owned.add(
        const BillingPurchase(
          productId: Products.premiumYearly,
          status: BillingPurchaseStatus.restored,
          token: 'tok-y',
        ),
      );
      await c
          .read(purchaseControllerProvider.notifier)
          .start(pCouple, refresh: true);
      await settle();
      expect(rig.verifier.claims.single.productId, Products.premiumYearly);
      expect(c.read(purchaseControllerProvider).phase, PurchasePhase.idle);
    });

    test('a refused purchase is not finished and says so', () async {
      final c = await container();
      rig.verifier.error = VerifyException(VerifyFailure.rejected);
      await c
          .read(purchaseControllerProvider.notifier)
          .buy(Products.bookSingle, coupleId: pCouple);
      rig.billing.paid(Products.bookSingle);
      await settle();
      expect(c.read(purchaseControllerProvider).phase, PurchasePhase.failed);
      expect(rig.billing.completed, isEmpty);
      expect(await rig.pending.load(), isEmpty);
    });

    test('a gift carries its message, at most 300 characters', () async {
      final c = await container();
      final long = 'x' * 400;
      await c
          .read(purchaseControllerProvider.notifier)
          .buy(Products.giftPremium3m, coupleId: pCouple, giftMessage: long);
      rig.billing.paid(Products.giftPremium3m);
      await settle();
      final data = rig.verifier.claims.single.toData();
      expect((data['gift'] as Map)['message'], 'x' * 300);
      expect(rig.billing.consumed, [Products.giftPremium3m]);
    });

    test('callable errors and results map as the server sends them', () {
      expect(
        FunctionsPurchaseVerifier.failureForCode('NOT_FOUND'),
        VerifyFailure.unavailable,
      );
      expect(
        FunctionsPurchaseVerifier.failureForCode('internal'),
        VerifyFailure.unavailable,
      );
      expect(
        FunctionsPurchaseVerifier.failureForCode('permission-denied'),
        VerifyFailure.denied,
      );
      expect(
        FunctionsPurchaseVerifier.failureForCode('invalid-argument'),
        VerifyFailure.rejected,
      );
      final r = VerifyResult.parse({
        'status': 'alreadyGranted',
        'premiumUntil': '2027-11-04T00:00:00.000Z',
        'giftId': 'g1',
      });
      expect(r.isGranted, isTrue);
      expect(r.premiumUntil, DateTime.utc(2027, 11, 4).toLocal());
      expect(r.giftId, 'g1');
    });
  });

  group('Couple premium', () {
    test('active while until is in the future', () async {
      await pairing.couple.update({
        'premium': {
          'until': Timestamp.fromDate(
            pairing.now.add(const Duration(days: 30)),
          ),
          'subscriptionUntil': Timestamp.fromDate(
            pairing.now.add(const Duration(days: 30)),
          ),
          'plan': 'monthly',
          'source': 'play',
          'updatedAt': Timestamp.fromDate(pairing.now),
        },
        'bookCredits': 2,
      });
      final couple = Couple.fromDoc(await pairing.couple.get());
      expect(couple.isPremium(pairing.now), isTrue);
      expect(
        couple.isPremium(pairing.now.add(const Duration(days: 31))),
        isFalse,
      );
      expect(couple.bookCredits, 2);
      expect(couple.premium!.hasActiveSubscription(pairing.now), isTrue);
    });
  });

  group('screens', () {
    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      String uid = pAsha,
    }) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(uid),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PairingReady(uid: uid, child: child),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Premium: store prices, yearly as best value, buying', (
      tester,
    ) async {
      await pump(tester, const PremiumScreen());
      expect(find.text('₹999.00'), findsOneWidget);
      expect(find.text('₹149.00'), findsOneWidget);
      expect(find.text('Best value'), findsOneWidget);
      expect(find.text('Coming soon'), findsWidgets);
      expect(find.byKey(const Key('premium-until')), findsNothing);

      await tester.tap(find.byKey(const Key('premium-buy')));
      await tester.pump();
      expect(rig.billing.bought, [Products.premiumYearly]);

      rig.verifier.error = VerifyException(VerifyFailure.unavailable);
      rig.billing.paid(Products.premiumYearly);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Payment received — waiting for the server'),
        findsOneWidget,
      );
    });

    testWidgets('Premium: the active state shows until when', (tester) async {
      await pairing.couple.update({
        'premium': {
          'until': Timestamp.fromDate(DateTime(2027, 11, 4)),
          'subscriptionUntil': Timestamp.fromDate(DateTime(2027, 11, 4)),
          'plan': 'yearly',
          'source': 'play',
        },
      });
      await pump(tester, const PremiumScreen());
      expect(find.text('You have Premium'), findsOneWidget);
      expect(find.text('Premium until 4 Nov 2027'), findsOneWidget);
      expect(find.byKey(const Key('premium-buy')), findsNothing);
      expect(find.textContaining('renews in Google Play'), findsOneWidget);
    });

    testWidgets('Premium: restore', (tester) async {
      await pump(tester, const PremiumScreen());
      await tester.scrollUntilVisible(
        find.byKey(const Key('premium-restore')),
        300,
      );
      await tester.tap(find.byKey(const Key('premium-restore')));
      await tester.pumpAndSettle();
      expect(rig.billing.restores, 1);
    });

    testWidgets('gift composer: message goes with the purchase', (
      tester,
    ) async {
      await pump(tester, const GiftComposerScreen());
      expect(find.text('3 months of Premium'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gift-${Products.giftPremium3m}')));
      await tester.enterText(
        find.byKey(const Key('gift-message')),
        'For our long-distance months 💕',
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('gift-send')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gift-send')));
      await tester.pump();
      expect(rig.billing.bought, [Products.giftPremium3m]);

      rig.billing.paid(Products.giftPremium3m);
      await tester.pumpAndSettle();
      final claim = rig.verifier.claims.single;
      expect(claim.giftMessage, 'For our long-distance months 💕');
      expect(find.text('Your gift is on its way 💝'), findsOneWidget);
    });

    testWidgets('gift composer: only a book while subscribed', (tester) async {
      await pairing.couple.update({
        'premium': {
          'until': Timestamp.fromDate(
            pairing.now.add(const Duration(days: 20)),
          ),
          'subscriptionUntil': Timestamp.fromDate(
            pairing.now.add(const Duration(days: 20)),
          ),
          'plan': 'monthly',
        },
      });
      await pump(tester, const GiftComposerScreen());
      expect(
        find.text(
          'You already have Premium together — gift a Memory book instead.',
        ),
        findsOneWidget,
      );
      expect(find.text('3 months of Premium'), findsNothing);
      expect(find.text('A Memory book'), findsOneWidget);
    });

    Future<Gift> seedGift({String kind = 'premium', int? months = 3}) async {
      final ref = pairing.couple.collection('gifts').doc('g1');
      await ref.set({
        'fromUid': pRavi,
        'toUid': pAsha,
        'kind': kind,
        'months': months,
        'message': 'Happy anniversary, my love',
        'createdAt': Timestamp.fromDate(pairing.now),
        'openedAt': null,
      });
      return Gift.fromDoc(await ref.get());
    }

    testWidgets('gift reveal: opens once, writes openedAt', (tester) async {
      final gift = await seedGift();
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const UnopenedGiftCard(),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(GiftRevealScreen.route(gift)),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Ravi sent you a gift'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-gift-card')));
      await tester.pumpAndSettle();
      expect(find.text('A gift from Ravi'), findsOneWidget);
      expect(find.text('Tap to open'), findsOneWidget);
      expect(find.byKey(const Key('gift-headline')), findsNothing);

      await tester.tap(find.byKey(const Key('gift-box')));
      await tester.pumpAndSettle();
      expect(
        find.text('Ravi gifted you 3 months of Premium 💝'),
        findsOneWidget,
      );
      expect(find.text('“Happy anniversary, my love”'), findsOneWidget);
      final doc = await pairing.couple.collection('gifts').doc('g1').get();
      expect(doc.data()!['openedAt'], isA<Timestamp>());

      // Back home, the card has gone: it was a surprise once.
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-gift-card')), findsNothing);
    });

    testWidgets('gift reveal: a book offers "Make our book"', (tester) async {
      final gift = await seedGift(kind: 'book', months: null);
      await pump(tester, GiftRevealScreen(gift: gift));
      await tester.tap(find.byKey(const Key('gift-box')));
      await tester.pumpAndSettle();
      expect(find.text('Ravi gifted you a Memory book 💝'), findsOneWidget);
      expect(find.byKey(const Key('gift-make-book')), findsOneWidget);
    });
  });
}
