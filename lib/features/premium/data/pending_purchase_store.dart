import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couple_app/features/premium/data/purchase_verifier.dart';

/// Purchases that are paid for but not yet confirmed by the server, kept
/// on this phone so they can be sent again (and so the screen can say
/// "waiting for the server").
abstract class PendingPurchaseStore {
  Future<List<PurchaseClaim>> load();
  Future<void> save(PurchaseClaim claim);
  Future<void> remove(String purchaseToken);
}

/// In memory: tests, and a fallback when the phone's storage fails.
class MemoryPendingPurchaseStore implements PendingPurchaseStore {
  final _claims = <String, PurchaseClaim>{};

  @override
  Future<List<PurchaseClaim>> load() async => _claims.values.toList();

  @override
  Future<void> save(PurchaseClaim claim) async =>
      _claims[claim.purchaseToken] = claim;

  @override
  Future<void> remove(String purchaseToken) async =>
      _claims.remove(purchaseToken);
}

/// In the app's shared preferences, as a JSON list.
class PrefsPendingPurchaseStore implements PendingPurchaseStore {
  static const _key = 'pendingPurchases.v1';

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('Pending purchases unavailable: $e');
      return null;
    }
  }

  @override
  Future<List<PurchaseClaim>> load() async {
    final raw = (await _prefs())?.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final item in list) ?PurchaseClaim.fromJson(item)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<PurchaseClaim> claims) async {
    await (await _prefs())?.setString(
      _key,
      jsonEncode([for (final c in claims) c.toJson()]),
    );
  }

  @override
  Future<void> save(PurchaseClaim claim) async {
    final claims = [
      for (final c in await load())
        if (c.purchaseToken != claim.purchaseToken) c,
      claim,
    ];
    await _write(claims);
  }

  @override
  Future<void> remove(String purchaseToken) async {
    await _write([
      for (final c in await load())
        if (c.purchaseToken != purchaseToken) c,
    ]);
  }
}
