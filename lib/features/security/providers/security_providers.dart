import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/security/data/account_reauth.dart';
import 'package:couple_app/features/security/data/device_identity_service.dart';
import 'package:couple_app/features/security/data/device_trust_service.dart';
import 'package:couple_app/features/security/device_trust_controller.dart';
import 'package:couple_app/features/security/models/device_check.dart';
import 'package:couple_app/features/security/models/known_device.dart';
import 'package:couple_app/features/security/models/security_event.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';

/// This phone's id and name, shared with the vault.
final deviceIdentityServiceProvider = Provider<DeviceIdentityService>(
  (ref) => DeviceIdentityService(
    keystore: ref.watch(deviceKeystoreProvider),
    crypto: ref.watch(vaultCryptoProvider),
    names: ref.watch(deviceNameSourceProvider),
  ),
);

/// Known phones, partner checks and security notices in Firestore.
final deviceTrustServiceProvider = Provider<DeviceTrustService>(
  (ref) => DeviceTrustService(),
);

/// Password / Google re-checks and adding a recovery email.
final accountReauthProvider = Provider<AccountReauth>(
  (ref) => FirebaseAccountReauth(),
);

/// The time, for the 180-day, 7-day and 30-day rules. Tests replace it.
final securityClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Whether this phone may open [uid]'s account; see
/// [DeviceTrustController]. Lives for as long as that user is signed in.
final deviceTrustProvider = AsyncNotifierProvider.autoDispose
    .family<DeviceTrustController, DeviceTrust, String>(
      DeviceTrustController.new,
    );

/// This phone's id for the signed-in user.
final currentDeviceIdProvider = FutureProvider.autoDispose<String>(
  (ref) => ref
      .watch(deviceIdentityServiceProvider)
      .deviceId(ref.watch(currentUidProvider)),
);

/// The signed-in user's known phones, most recently seen first.
final knownDevicesProvider = StreamProvider.autoDispose<List<KnownDevice>>(
  (ref) => ref
      .watch(deviceTrustServiceProvider)
      .watchDevices(ref.watch(currentUidProvider)),
);

/// The account's password / Google sign-ins. Invalidate after adding a
/// recovery email.
final reauthOptionsProvider = Provider.autoDispose<ReauthOptions>(
  (ref) => ref.watch(accountReauthProvider).options(),
);

/// Every security notice for the signed-in user, newest first.
final securityEventsProvider = StreamProvider.autoDispose<List<SecurityEvent>>(
  (ref) => ref
      .watch(deviceTrustServiceProvider)
      .watchEvents(ref.watch(currentUidProvider)),
);

/// Notices to show on this phone: everything except notices about this
/// phone itself (its own wait, its own approval).
final securityNoticesProvider = Provider.autoDispose<List<SecurityEvent>>((
  ref,
) {
  final events = ref.watch(securityEventsProvider).value ?? const [];
  final deviceId = ref.watch(currentDeviceIdProvider).value;
  if (deviceId == null) return const [];
  return [
    for (final e in events)
      if (!e.isAbout(deviceId)) e,
  ];
});

/// The partner's new phones waiting for this user to vouch for them.
final partnerDeviceChecksProvider =
    StreamProvider.autoDispose<List<DeviceCheck>>((ref) {
      final uid = ref.watch(currentUidProvider);
      final cid = ref.watch(currentCoupleIdProvider);
      final partnerId = ref.watch(
        coupleProvider.select((c) => c.value?.partnerIdFor(uid)),
      );
      if (partnerId == null) return Stream.value(const []);
      final now = ref.watch(securityClockProvider);
      return ref
          .watch(deviceTrustServiceProvider)
          .watchPendingChecks(cid, partnerId)
          .map(
            (checks) => [
              for (final c in checks)
                if (c.isFreshAt(now())) c,
            ],
          );
    });
