import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'package:couple_app/features/premium/models/products.dart';

/// Where a store purchase stands.
enum BillingPurchaseStatus { pending, purchased, restored, error, canceled }

/// A purchase as the store reports it.
class BillingPurchase {
  const BillingPurchase({
    required this.productId,
    required this.status,
    this.purchaseId,
    this.token = '',
    this.error,
    this.native,
  });

  final String productId;
  final BillingPurchaseStatus status;
  final String? purchaseId;

  /// What the server verifies with Google Play
  /// (`verificationData.serverVerificationData`).
  final String token;
  final String? error;

  /// The plugin's own object, needed to complete or consume it.
  final Object? native;

  bool get isPaid =>
      status == BillingPurchaseStatus.purchased ||
      status == BillingPurchaseStatus.restored;
}

/// The store: products, buying, the purchase stream, restoring, and
/// finishing a purchase. Behind an interface so tests can fake it.
abstract class BillingGateway {
  /// Every purchase update, including ones from earlier sessions.
  Stream<List<BillingPurchase>> get purchases;

  Future<bool> isAvailable();

  /// The products the store knows, with localized prices. Unknown ids are
  /// left out.
  Future<List<StoreProduct>> queryProducts(Set<String> ids);

  /// Opens the store's buy sheet. Results arrive on [purchases]. Returns
  /// false if the sheet couldn't be shown.
  Future<bool> buy(String productId);

  /// Asks the store to send past purchases again (as restored).
  Future<void> restore();

  /// Acknowledges the purchase, so the store doesn't refund it.
  Future<void> complete(BillingPurchase purchase);

  /// Uses up a consumable so it can be bought again.
  Future<void> consume(BillingPurchase purchase);
}

/// [BillingGateway] through the official `in_app_purchase` plugin.
///
/// Consumables are bought with `autoConsume: false` and consumed only
/// after the server has granted them, so nothing is used up that the
/// couple didn't get.
class InAppPurchaseBillingGateway implements BillingGateway {
  InAppPurchaseBillingGateway([InAppPurchase? iap]) : _given = iap;

  final InAppPurchase? _given;
  late final InAppPurchase _iap = _given ?? InAppPurchase.instance;

  /// The plugin's details for each product, needed to buy it.
  final _details = <String, ProductDetails>{};

  @override
  late final Stream<List<BillingPurchase>> purchases = _iap.purchaseStream.map(
    (list) => [for (final p in list) _wrap(p)],
  );

  static BillingPurchase _wrap(PurchaseDetails p) => BillingPurchase(
    productId: p.productID,
    purchaseId: p.purchaseID,
    token: p.verificationData.serverVerificationData,
    error: p.error?.message,
    native: p,
    status: switch (p.status) {
      PurchaseStatus.pending => BillingPurchaseStatus.pending,
      PurchaseStatus.purchased => BillingPurchaseStatus.purchased,
      PurchaseStatus.restored => BillingPurchaseStatus.restored,
      PurchaseStatus.error => BillingPurchaseStatus.error,
      PurchaseStatus.canceled => BillingPurchaseStatus.canceled,
    },
  );

  @override
  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } catch (e) {
      debugPrint('Billing unavailable: $e');
      return false;
    }
  }

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async {
    final response = await _iap.queryProductDetails(ids);
    final products = <StoreProduct>[];
    for (final d in response.productDetails) {
      // A subscription comes back once per offer; keep the first (the
      // base plan).
      if (_details.containsKey(d.id) && products.any((p) => p.id == d.id)) {
        continue;
      }
      _details[d.id] = d;
      products.add(
        StoreProduct(
          id: d.id,
          title: d.title,
          price: d.price,
          rawPrice: d.rawPrice,
          currencyCode: d.currencyCode,
        ),
      );
    }
    return products;
  }

  @override
  Future<bool> buy(String productId) async {
    var details = _details[productId];
    if (details == null) {
      await queryProducts({productId});
      details = _details[productId];
    }
    if (details == null) return false;
    final param = PurchaseParam(productDetails: details);
    if (Products.isConsumable(productId)) {
      return _iap.buyConsumable(purchaseParam: param, autoConsume: false);
    }
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(BillingPurchase purchase) async {
    final native = purchase.native;
    if (native is PurchaseDetails && native.pendingCompletePurchase) {
      await _iap.completePurchase(native);
    }
  }

  @override
  Future<void> consume(BillingPurchase purchase) async {
    final native = purchase.native;
    if (native is! PurchaseDetails ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final android = _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    await android.consumePurchase(native);
  }
}
