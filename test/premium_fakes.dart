// Fakes for Premium, gifts and memory books, shared by their tests and the
// screenshot suite: the store, the server's verifyPurchase, the PDF file
// store and photo fetching.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/books/data/book_images.dart';
import 'package:couple_app/features/books/data/book_pdf_builder.dart';
import 'package:couple_app/features/books/data/book_service.dart';
import 'package:couple_app/features/books/providers/book_providers.dart';
import 'package:couple_app/features/books/screens/book_viewer_screen.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';
import 'package:couple_app/features/music/data/music_service.dart';
import 'package:couple_app/features/music/providers/music_providers.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/play/data/game_service.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/premium/data/billing_gateway.dart';
import 'package:couple_app/features/premium/data/gift_service.dart';
import 'package:couple_app/features/premium/data/pending_purchase_store.dart';
import 'package:couple_app/features/premium/data/purchase_verifier.dart';
import 'package:couple_app/features/premium/models/products.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';
import 'package:couple_app/features/together/data/love_note_service.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';

import 'pairing_fakes.dart';
import 'vault_fakes.dart' show gradientJpeg;

/// Google Play, by hand: prices, the buy sheet, and purchase updates.
class FakeBillingGateway implements BillingGateway {
  FakeBillingGateway({Map<String, String>? prices})
    : prices =
          prices ??
          {
            Products.premiumMonthly: '₹149.00',
            Products.premiumYearly: '₹999.00',
            Products.bookSingle: '₹199.00',
            Products.giftPremium1m: '₹149.00',
            Products.giftPremium3m: '₹399.00',
            Products.giftPremium12m: '₹999.00',
            Products.giftBook: '₹199.00',
          };

  final Map<String, String> prices;
  bool available = true;
  final _controller = StreamController<List<BillingPurchase>>.broadcast();

  final bought = <String>[];
  final completed = <String>[];
  final consumed = <String>[];
  int restores = 0;

  /// Purchases the next [restore] sends again.
  final owned = <BillingPurchase>[];

  /// Sends a purchase update, as the store would.
  void emit(BillingPurchase p) => _controller.add([p]);

  /// "The user paid" for [productId].
  BillingPurchase paid(String productId, {String? token}) {
    final p = BillingPurchase(
      productId: productId,
      status: BillingPurchaseStatus.purchased,
      purchaseId: 'GPA.${bought.length}',
      token: token ?? 'token-$productId-${bought.length}',
    );
    emit(p);
    return p;
  }

  @override
  Stream<List<BillingPurchase>> get purchases => _controller.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async => [
    for (final id in ids)
      if (prices[id] case final price?)
        StoreProduct(id: id, title: Products.label(id), price: price),
  ];

  @override
  Future<bool> buy(String productId) async {
    bought.add(productId);
    return available;
  }

  @override
  Future<void> restore() async {
    restores++;
    for (final p in owned) {
      emit(
        BillingPurchase(
          productId: p.productId,
          status: BillingPurchaseStatus.restored,
          token: p.token,
        ),
      );
    }
  }

  @override
  Future<void> complete(BillingPurchase purchase) async =>
      completed.add(purchase.productId);

  @override
  Future<void> consume(BillingPurchase purchase) async =>
      consumed.add(purchase.productId);
}

/// verifyPurchase, by hand.
class FakeVerifier implements PurchaseVerifier {
  VerifyException? error;
  VerifyResult result = const VerifyResult(status: 'granted');
  final claims = <PurchaseClaim>[];

  @override
  Future<VerifyResult> verify(PurchaseClaim claim) async {
    claims.add(claim);
    final e = error;
    if (e != null) throw e;
    return result;
  }
}

/// Storage for book PDFs, in memory; [failUploads] makes uploads fail.
class FakeBookFileStore implements BookFileStore {
  final files = <String, Uint8List>{};
  int failUploads = 0;

  @override
  Future<void> upload(String path, Uint8List bytes) async {
    if (failUploads > 0) {
      failUploads--;
      throw StateError('network');
    }
    files[path] = bytes;
  }

  @override
  Future<Uint8List> read(String path) async => files[path]!;

  @override
  Future<void> delete(String path) async => files.remove(path);
}

/// Every photo is a small gradient JPEG.
class FakeBookImageSource implements BookImageSource {
  final fetched = <String>[];

  @override
  Future<Uint8List?> fetch(String url, {int maxEdge = 1600}) async {
    fetched.add(url);
    final seed = url.hashCode;
    return gradientJpeg(
      width: 160,
      height: seed.isEven ? 120 : 200,
      from: 0xFFFFB3C7 + (seed % 7) * 0x000800,
      to: 0xFF6A4FC4,
    );
  }
}

/// Premium, gifts and books on top of [PairingRig]'s backend.
class PremiumRig {
  PremiumRig(this.pairing, {required this.fonts});

  final PairingRig pairing;
  final BookFonts fonts;
  final billing = FakeBillingGateway();
  final verifier = FakeVerifier();
  final pending = MemoryPendingPurchaseStore();
  final files = FakeBookFileStore();
  final images = FakeBookImageSource();

  BookService get books => BookService(db: pairing.db, files: files);

  List<Override> overrides(String uid) => [
    ...pairing.overrides(uid),
    billingGatewayProvider.overrideWithValue(billing),
    purchaseVerifierProvider.overrideWithValue(verifier),
    pendingPurchaseStoreProvider.overrideWithValue(pending),
    premiumClockProvider.overrideWithValue(pairing.clock),
    giftServiceProvider.overrideWithValue(GiftService(db: pairing.db)),
    bookServiceProvider.overrideWithValue(books),
    bookImageSourceProvider.overrideWithValue(images),
    bookFontsProvider.overrideWith((ref) => fonts),
    bookClockProvider.overrideWithValue(pairing.clock),
    avatarPngRendererProvider.overrideWithValue((AvatarConfig _) async => null),
    bookPdfViewProvider.overrideWithValue(
      (context, bytes, title) =>
          Center(child: Text('PDF $title · ${bytes.length} bytes')),
    ),
    memoryServiceProvider.overrideWithValue(MemoryService(db: pairing.db)),
    loveNoteServiceProvider.overrideWithValue(LoveNoteService(db: pairing.db)),
    datePlanServiceProvider.overrideWithValue(DatePlanService(db: pairing.db)),
    gameServiceProvider.overrideWithValue(GameService(db: pairing.db)),
    musicServiceProvider.overrideWithValue(MusicService(db: pairing.db)),
  ];
}
