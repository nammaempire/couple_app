import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/premium/data/billing_gateway.dart';
import 'package:couple_app/features/premium/data/gift_service.dart';
import 'package:couple_app/features/premium/data/pending_purchase_store.dart';
import 'package:couple_app/features/premium/data/purchase_verifier.dart';
import 'package:couple_app/features/premium/models/gift.dart';
import 'package:couple_app/features/premium/models/premium_status.dart';
import 'package:couple_app/features/premium/models/products.dart';

/// The store (Google Play billing).
final billingGatewayProvider = Provider<BillingGateway>(
  (ref) => InAppPurchaseBillingGateway(),
);

/// The `verifyPurchase` callable.
final purchaseVerifierProvider = Provider<PurchaseVerifier>(
  (ref) => FunctionsPurchaseVerifier(),
);

/// Paid purchases the server hasn't confirmed yet.
final pendingPurchaseStoreProvider = Provider<PendingPurchaseStore>(
  (ref) => PrefsPendingPurchaseStore(),
);

/// The time, for "Premium until". Tests replace it.
final premiumClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The couple's Premium, active or not; null if never bought.
final premiumProvider = Provider.autoDispose<PremiumStatus?>(
  (ref) => ref.watch(coupleProvider.select((c) => c.value?.premium)),
);

/// Whether Premium is active now.
final isPremiumProvider = Provider.autoDispose<bool>((ref) {
  final premium = ref.watch(premiumProvider);
  return premium?.isActive(ref.watch(premiumClockProvider)()) ?? false;
});

/// Memory books paid for but not made yet.
final bookCreditsProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(coupleProvider.select((c) => c.value?.bookCredits ?? 0)),
);

/// The store's products with localized prices; empty when the store isn't
/// reachable.
final storeProductsProvider = FutureProvider.autoDispose
    .family<Map<String, StoreProduct>, String>((ref, key) async {
      final ids = key.split(',').toSet();
      final billing = ref.watch(billingGatewayProvider);
      try {
        if (!await billing.isAvailable()) return const {};
        final products = await billing.queryProducts(ids);
        return {for (final p in products) p.id: p};
      } catch (e) {
        debugPrint('Could not load products: $e');
        return const {};
      }
    });

/// Where the current purchase stands, for the screens.
enum PurchasePhase {
  idle,

  /// The store's sheet is up, or Google Play is processing the payment.
  buying,

  /// Paid; asking the server to grant it.
  verifying,

  /// Paid, but the server couldn't be reached. Kept and retried.
  waitingForServer,

  /// Granted.
  success,
  failed,
}

@immutable
class PurchaseState {
  const PurchaseState({
    this.phase = PurchasePhase.idle,
    this.productId,
    this.message,
    this.result,
    this.pending = 0,
  });

  final PurchasePhase phase;
  final String? productId;
  final String? message;
  final VerifyResult? result;

  /// Paid purchases still waiting for the server.
  final int pending;

  bool get busy =>
      phase == PurchasePhase.buying || phase == PurchasePhase.verifying;

  PurchaseState copyWith({
    PurchasePhase? phase,
    String? productId,
    String? message,
    VerifyResult? result,
    int? pending,
  }) => PurchaseState(
    phase: phase ?? this.phase,
    productId: productId ?? this.productId,
    message: message,
    result: result ?? this.result,
    pending: pending ?? this.pending,
  );
}

/// Runs every purchase from the store's sheet to a grant:
///
/// 1. [buy] opens the store's sheet.
/// 2. A paid purchase (`purchased` or `restored`) goes to the server's
///    `verifyPurchase`, with the gift message for gifts.
/// 3. Once granted, it is acknowledged and, for consumables, consumed.
/// 4. If the server can't be reached, the purchase is kept on the phone
///    ("Payment received — waiting for the server to confirm") and sent
///    again by [retryPending] (on resume). It is not acknowledged, and
///    nothing is ever granted here: Premium and credits only ever come
///    from the server's writes.
class PurchaseController extends Notifier<PurchaseState> {
  StreamSubscription<List<BillingPurchase>>? _sub;

  /// What each product being bought is for: the couple, and the message
  /// for a gift.
  final _intents = <String, ({String coupleId, String? giftMessage})>{};

  /// The couple purchases belong to when nothing else says (restores,
  /// purchases finished after a restart).
  String? _coupleId;

  /// True while the start-up restore runs: what it finds is verified (to
  /// refresh a subscription's expiry) without telling the screens.
  DateTime? _quietUntil;

  bool get _quiet {
    final until = _quietUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  PurchaseState build() {
    ref.onDispose(() => _sub?.cancel());
    return const PurchaseState();
  }

  BillingGateway get _billing => ref.read(billingGatewayProvider);
  PurchaseVerifier get _verifier => ref.read(purchaseVerifierProvider);
  PendingPurchaseStore get _store => ref.read(pendingPurchaseStoreProvider);

  /// Starts listening to the store for [coupleId], sends any waiting
  /// purchases to the server again, and (with [refresh]) quietly restores
  /// past purchases so an active subscription is verified again, which
  /// refreshes its expiry if a server notification was missed.
  Future<void> start(String coupleId, {bool refresh = false}) async {
    _coupleId = coupleId;
    _sub ??= _billing.purchases.listen((list) {
      for (final p in list) {
        unawaited(_onPurchase(p));
      }
    }, onError: (Object e) => debugPrint('Purchase stream error: $e'));
    await retryPending();
    if (!refresh) return;
    try {
      if (!await _billing.isAvailable()) return;
      // Restored purchases arrive on the stream shortly after; they go
      // through quietly for a little while.
      _quietUntil = DateTime.now().add(const Duration(seconds: 20));
      await _billing.restore();
    } catch (e) {
      debugPrint('Start-up restore failed: $e');
    }
  }

  /// Opens the store to buy [productId] for [coupleId].
  Future<void> buy(
    String productId, {
    required String coupleId,
    String? giftMessage,
  }) async {
    if (state.busy) return;
    if (_sub == null) await start(coupleId);
    final message = giftMessage?.trim();
    _intents[productId] = (
      coupleId: coupleId,
      giftMessage: message == null || message.isEmpty
          ? null
          : message.characters.take(Products.maxGiftMessage).toString(),
    );
    _quietUntil = null;
    state = state.copyWith(phase: PurchasePhase.buying, productId: productId);
    try {
      final opened = await _billing.buy(productId);
      if (!opened && ref.mounted && state.phase == PurchasePhase.buying) {
        state = state.copyWith(
          phase: PurchasePhase.failed,
          message: 'The store isn\'t available right now. Try again later.',
        );
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: PurchasePhase.failed,
        message: 'Couldn\'t open the store. Try again.',
      );
    }
  }

  /// Asks the store for past purchases; they are verified as they arrive.
  Future<void> restore(String coupleId) async {
    if (_sub == null) await start(coupleId);
    _coupleId = coupleId;
    _quietUntil = null;
    state = state.copyWith(phase: PurchasePhase.verifying);
    try {
      await _billing.restore();
      await retryPending();
      if (ref.mounted && state.phase == PurchasePhase.verifying) {
        state = state.copyWith(
          phase: PurchasePhase.idle,
          message: 'Purchases restored.',
        );
      }
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: PurchasePhase.failed,
        message: 'Couldn\'t reach the store. Try again.',
      );
    }
  }

  /// Back to idle after a result was shown.
  void dismiss() {
    if (!state.busy) {
      state = PurchaseState(pending: state.pending);
    }
  }

  Future<void> _onPurchase(BillingPurchase p) async {
    switch (p.status) {
      case BillingPurchaseStatus.pending:
        state = state.copyWith(
          phase: PurchasePhase.buying,
          productId: p.productId,
          message: 'Waiting for Google Play to confirm the payment…',
        );
      case BillingPurchaseStatus.canceled:
        _intents.remove(p.productId);
        state = state.copyWith(phase: PurchasePhase.idle);
      case BillingPurchaseStatus.error:
        _intents.remove(p.productId);
        state = state.copyWith(
          phase: PurchasePhase.failed,
          message: 'The payment didn\'t go through. You haven\'t been charged.',
        );
        await _finishQuietly(p);
      case BillingPurchaseStatus.purchased:
      case BillingPurchaseStatus.restored:
        await _verifyPaid(p);
    }
  }

  Future<void> _verifyPaid(BillingPurchase p) async {
    if (_quiet && p.status == BillingPurchaseStatus.restored) {
      return _verifyQuietly(p);
    }
    final intent = _intents[p.productId];
    PurchaseClaim? stored;
    for (final c in await _store.load()) {
      if (c.purchaseToken == p.token) stored = c;
    }
    final coupleId = intent?.coupleId ?? stored?.coupleId ?? _coupleId;
    if (coupleId == null || p.token.isEmpty) return;
    final claim = PurchaseClaim(
      coupleId: coupleId,
      productId: p.productId,
      purchaseToken: p.token,
      giftMessage: intent?.giftMessage ?? stored?.giftMessage,
    );

    state = state.copyWith(
      phase: PurchasePhase.verifying,
      productId: p.productId,
    );
    try {
      final result = await _verifier.verify(claim);
      if (!result.isGranted) throw VerifyException(VerifyFailure.rejected);
      // Granted on the server: now the store may consider it done.
      await _finish(p);
      await _store.remove(claim.purchaseToken);
      _intents.remove(p.productId);
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: PurchasePhase.success,
        productId: p.productId,
        result: result,
        pending: (await _store.load()).length,
      );
    } on VerifyException catch (e) {
      if (!ref.mounted) return;
      if (e.failure == VerifyFailure.unavailable) {
        await _store.save(claim);
        state = state.copyWith(
          phase: PurchasePhase.waitingForServer,
          productId: p.productId,
          message: 'Payment received — waiting for the server to confirm.',
          pending: (await _store.load()).length,
        );
      } else {
        state = state.copyWith(
          phase: PurchasePhase.failed,
          productId: p.productId,
          message:
              'We couldn\'t confirm this purchase. If you were charged, '
              'Google Play refunds it automatically within a few days.',
        );
      }
    }
  }

  /// A purchase found by the start-up restore: verified and finished, with
  /// nothing shown either way. Only subscriptions and unfinished
  /// consumables come back from a restore.
  Future<void> _verifyQuietly(BillingPurchase p) async {
    final coupleId = _coupleId;
    if (coupleId == null || p.token.isEmpty) return;
    PurchaseClaim? stored;
    for (final c in await _store.load()) {
      if (c.purchaseToken == p.token) stored = c;
    }
    try {
      final result = await _verifier.verify(
        PurchaseClaim(
          coupleId: stored?.coupleId ?? coupleId,
          productId: p.productId,
          purchaseToken: p.token,
          giftMessage: stored?.giftMessage,
        ),
      );
      if (result.isGranted) {
        await _finish(p);
        await _store.remove(p.token);
      }
    } catch (e) {
      debugPrint('Quiet verify of ${p.productId} failed: $e');
    }
  }

  /// Acknowledges [p] and consumes it if it is a consumable.
  Future<void> _finish(BillingPurchase p) async {
    try {
      await _billing.complete(p);
      if (Products.isConsumable(p.productId)) await _billing.consume(p);
    } catch (e) {
      // The server has it; the store sends it again on the next restore.
      debugPrint('Finishing purchase failed: $e');
    }
  }

  Future<void> _finishQuietly(BillingPurchase p) async {
    try {
      await _billing.complete(p);
    } catch (_) {}
  }

  /// Sends purchases waiting for the server again. Once one is granted, the
  /// store is asked to restore, so it is acknowledged and consumed too.
  Future<void> retryPending() async {
    final claims = await _store.load();
    if (claims.isEmpty) {
      if (ref.mounted && state.pending != 0) {
        state = state.copyWith(pending: 0);
      }
      return;
    }
    var granted = false;
    VerifyResult? last;
    for (final claim in claims) {
      try {
        final result = await _verifier.verify(claim);
        if (result.isGranted) {
          await _store.remove(claim.purchaseToken);
          granted = true;
          last = result;
        }
      } on VerifyException catch (e) {
        if (e.failure != VerifyFailure.unavailable) {
          // The server refused it for good; stop asking.
          await _store.remove(claim.purchaseToken);
        }
      }
    }
    final left = (await _store.load()).length;
    if (!ref.mounted) return;
    if (granted) {
      state = state.copyWith(
        phase: PurchasePhase.success,
        result: last,
        pending: left,
      );
      try {
        await _billing.restore();
      } catch (_) {}
    } else {
      state = state.copyWith(
        pending: left,
        phase: left > 0 ? PurchasePhase.waitingForServer : state.phase,
        message: left > 0
            ? 'Payment received — waiting for the server to confirm.'
            : state.message,
      );
    }
  }
}

final purchaseControllerProvider =
    NotifierProvider<PurchaseController, PurchaseState>(PurchaseController.new);

final giftServiceProvider = Provider<GiftService>((ref) => GiftService());

/// Every gift in the couple, newest first.
final giftsProvider = StreamProvider.autoDispose<List<Gift>>(
  (ref) => ref
      .watch(giftServiceProvider)
      .watchGifts(ref.watch(currentCoupleIdProvider)),
);

/// Gifts to this user they haven't opened yet, newest first.
final unopenedGiftsProvider = Provider.autoDispose<List<Gift>>((ref) {
  final uid = ref.watch(currentUidProvider);
  final gifts = ref.watch(giftsProvider).value ?? const <Gift>[];
  return [
    for (final g in gifts)
      if (g.toUid == uid && !g.isOpened) g,
  ];
});
