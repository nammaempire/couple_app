import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/vault/data/device_keystore.dart';
import 'package:couple_app/features/vault/data/device_name.dart';
import 'package:couple_app/features/vault/data/vault_crypto.dart';
import 'package:couple_app/features/vault/data/vault_photo_preparer.dart';
import 'package:couple_app/features/vault/data/vault_service.dart';
import 'package:couple_app/features/vault/models/vault_age.dart';
import 'package:couple_app/features/vault/models/vault_event.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';
import 'package:couple_app/features/vault/vault_session.dart';

/// The vault's Firestore and Storage access.
final vaultServiceProvider = Provider<VaultService>((ref) => VaultService());

/// This phone's vault key and local state, in the Android keystore.
final deviceKeystoreProvider = Provider<DeviceKeystore>(
  (ref) => SecureDeviceKeystore(),
);

/// The vault's encryption. Tests use `VaultCrypto.forTests()`.
final vaultCryptoProvider = Provider<VaultCrypto>((ref) => VaultCrypto());

/// The camera / gallery and photo shrinking.
final vaultPhotoSourceProvider = Provider<VaultPhotoSource>(
  (ref) => VaultPhotoPreparer(),
);

/// This phone's model, for approving it.
final deviceNameSourceProvider = Provider<DeviceNameSource>(
  (ref) => const PlatformDeviceName(),
);

/// The time, for cooldowns and expiry. Tests replace it.
final vaultClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The vault's settings document; null while it isn't set up.
final vaultMetaProvider = StreamProvider.autoDispose<VaultMeta?>(
  (ref) => ref
      .watch(vaultServiceProvider)
      .watchMeta(ref.watch(currentCoupleIdProvider)),
);

/// Every vault alert, newest first.
final vaultEventsProvider = StreamProvider.autoDispose<List<VaultEvent>>(
  (ref) => ref
      .watch(vaultServiceProvider)
      .watchEvents(ref.watch(currentCoupleIdProvider)),
);

/// Alerts caused by the partner (or someone on their phone), for this user
/// to see and dismiss.
final vaultAlertsProvider = Provider.autoDispose<List<VaultEvent>>((ref) {
  final uid = ref.watch(currentUidProvider);
  final events = ref.watch(vaultEventsProvider).value ?? const [];
  return [
    for (final e in events)
      if (e.uid != uid) e,
  ];
});

/// Whether the vault may open, by both partners' ages.
final vaultAgeStatusProvider = Provider.autoDispose<VaultAgeStatus>((ref) {
  final me = ref.watch(currentUserProvider);
  final partner = ref.watch(partnerProvider).value;
  return vaultAgeStatus(
    me: me,
    partner: partner,
    now: ref.watch(vaultClockProvider)(),
  );
});

/// Where the vault stands on this phone.
enum VaultAccess {
  /// Still reading.
  loading,

  /// Nobody has set it up.
  notSetUp,

  /// Set up, but this phone isn't registered yet.
  unregistered,

  /// Registered, waiting for an approved phone to approve it.
  pending,

  /// Approved; the code (or fingerprint) opens it.
  locked,

  /// Open.
  unlocked,
}

final vaultAccessProvider = Provider.autoDispose<VaultAccess>((ref) {
  final meta = ref.watch(vaultMetaProvider);
  final session = ref.watch(vaultSessionProvider);
  if (!meta.hasValue || !session.ready) return VaultAccess.loading;
  final m = meta.value;
  if (m == null) return VaultAccess.notSetUp;
  final id = session.identity!.deviceId;
  if (!m.devices.containsKey(id)) return VaultAccess.unregistered;
  if (!m.keys.containsKey(id)) return VaultAccess.pending;
  return session.unlocked ? VaultAccess.unlocked : VaultAccess.locked;
});

/// Every item on both shelves, as stored.
final vaultAllItemsProvider = StreamProvider.autoDispose<List<VaultItem>>(
  (ref) => ref
      .watch(vaultServiceProvider)
      .watchItems(ref.watch(currentCoupleIdProvider)),
);

/// The open shelf's items, oldest first, without expired ones. Empty while
/// locked.
final vaultItemsProvider = Provider.autoDispose<List<VaultItem>>((ref) {
  final shelf = ref.watch(vaultSessionProvider.select((s) => s.shelf));
  if (shelf == null) return const [];
  final all = ref.watch(vaultAllItemsProvider).value ?? const [];
  final now = ref.watch(vaultClockProvider)();
  final items = [
    for (final item in all)
      if (item.shelf == shelf && !item.isExpired(now)) item,
  ];
  // Items still waiting for the server's timestamp are the newest.
  items.sort((a, b) {
    final x = a.createdAt;
    final y = b.createdAt;
    if (x == null && y == null) return a.id.compareTo(b.id);
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  });
  return items;
});

/// Phones waiting for approval, shown on an open vault that can approve.
final vaultPendingDevicesProvider = Provider.autoDispose<List<VaultDevice>>((
  ref,
) {
  ref.watch(vaultSessionProvider.select((s) => s.unlocked));
  final session = ref.watch(vaultSessionProvider.notifier);
  if (!session.canApprove) return const [];
  return ref.watch(vaultMetaProvider).value?.pending ?? const [];
});
