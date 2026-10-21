import 'package:cloud_functions/cloud_functions.dart';

import 'package:couple_app/features/premium/models/products.dart';

/// Why the server didn't grant a purchase.
enum VerifyFailure {
  /// The function isn't deployed or reachable (no Blaze yet, offline,
  /// busy). Keep the purchase and try again later.
  unavailable,

  /// Not signed in, or not a member of this couple.
  denied,

  /// Google Play doesn't confirm it, or it isn't in a state to grant.
  rejected,

  other,
}

class VerifyException implements Exception {
  VerifyException(this.failure, [this.message]);

  final VerifyFailure failure;
  final String? message;

  @override
  String toString() => 'VerifyException(${failure.name}: $message)';
}

/// What the server granted.
class VerifyResult {
  const VerifyResult({
    required this.status,
    this.premiumUntil,
    this.bookCredits,
    this.giftId,
  });

  /// `granted` or `alreadyGranted`.
  final String status;
  final DateTime? premiumUntil;
  final int? bookCredits;
  final String? giftId;

  bool get isGranted => status == 'granted' || status == 'alreadyGranted';

  static VerifyResult parse(Object? data) {
    if (data is! Map) return const VerifyResult(status: 'granted');
    final until = data['premiumUntil'];
    final credits = data['bookCredits'];
    final gift = data['giftId'];
    final status = data['status'];
    return VerifyResult(
      status: status is String ? status : 'granted',
      premiumUntil: until is String
          ? DateTime.tryParse(until)?.toLocal()
          : null,
      bookCredits: credits is num ? credits.toInt() : null,
      giftId: gift is String ? gift : null,
    );
  }
}

/// A purchase for the server to check with Google Play and grant.
class PurchaseClaim {
  const PurchaseClaim({
    required this.coupleId,
    required this.productId,
    required this.purchaseToken,
    this.giftMessage,
  });

  final String coupleId;
  final String productId;
  final String purchaseToken;

  /// For gifts: the buyer's message to their partner.
  final String? giftMessage;

  Map<String, Object?> toData() => {
    'coupleId': coupleId,
    'productId': productId,
    'purchaseToken': purchaseToken,
    'packageName': Products.packageName,
    if (Products.isGift(productId)) 'gift': {'message': giftMessage ?? ''},
  };

  Map<String, Object?> toJson() => {
    'coupleId': coupleId,
    'productId': productId,
    'purchaseToken': purchaseToken,
    'giftMessage': giftMessage,
  };

  static PurchaseClaim? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final c = raw['coupleId'], p = raw['productId'], t = raw['purchaseToken'];
    if (c is! String || p is! String || t is! String) return null;
    final m = raw['giftMessage'];
    return PurchaseClaim(
      coupleId: c,
      productId: p,
      purchaseToken: t,
      giftMessage: m is String ? m : null,
    );
  }
}

/// The server half of a purchase. Behind an interface so tests can fake it.
abstract class PurchaseVerifier {
  Future<VerifyResult> verify(PurchaseClaim claim);
}

/// [PurchaseVerifier] through the `verifyPurchase` callable in
/// asia-south1.
class FunctionsPurchaseVerifier implements PurchaseVerifier {
  FunctionsPurchaseVerifier([FirebaseFunctions? functions])
    : _given = functions;

  final FirebaseFunctions? _given;
  late final FirebaseFunctions _functions =
      _given ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  @override
  Future<VerifyResult> verify(PurchaseClaim claim) async {
    try {
      final result = await _functions
          .httpsCallable('verifyPurchase')
          .call<Object?>(claim.toData());
      return VerifyResult.parse(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw VerifyException(failureForCode(e.code), e.message);
    } catch (e) {
      throw VerifyException(VerifyFailure.unavailable, '$e');
    }
  }

  static VerifyFailure failureForCode(String code) {
    switch (code.toLowerCase().replaceAll('_', '-')) {
      case 'not-found':
      case 'unavailable':
      case 'internal':
      case 'unimplemented':
      case 'deadline-exceeded':
      case 'resource-exhausted':
      case 'unknown':
        return VerifyFailure.unavailable;
      case 'unauthenticated':
      case 'permission-denied':
        return VerifyFailure.denied;
      case 'invalid-argument':
      case 'failed-precondition':
        return VerifyFailure.rejected;
      default:
        return VerifyFailure.other;
    }
  }
}
