import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/security/data/account_reauth.dart';
import 'package:couple_app/features/security/data/device_trust_service.dart';
import 'package:couple_app/features/security/models/device_check.dart';
import 'package:couple_app/features/security/models/known_device.dart';
import 'package:couple_app/features/security/models/security_event.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';

/// Why this phone is being asked.
enum NewPhoneReason {
  /// The account has phones, and this isn't one of them (including this
  /// phone after a reinstall, which gets a new id).
  newPhone,

  /// None of the account's phones has opened the app in 180 days.
  inactive,
}

/// Whether this phone may open the signed-in account.
@immutable
class DeviceTrust {
  const DeviceTrust({
    required this.trusted,
    required this.deviceId,
    required this.deviceName,
    this.known = false,
    this.reason,
    this.partner,
    this.reauth = ReauthOptions.none,
    this.existingCheck,
  });

  /// Passed (or never needed asking): the app may open.
  final bool trusted;
  final String deviceId;

  /// This phone's model, e.g. "Pixel 9".
  final String deviceName;

  /// This phone is already in `users/{uid}/devices` (asked again only
  /// because the account was inactive).
  final bool known;

  /// Set while not [trusted].
  final NewPhoneReason? reason;

  /// Who can vouch for this phone; null when unpaired.
  final PartnerContact? partner;

  /// The account's password / Google sign-ins, which can confirm it.
  final ReauthOptions reauth;

  /// A partner check this phone made earlier, to pick up again.
  final DeviceCheck? existingCheck;

  /// No partner and no email: the 7-day wait is the only way in.
  bool get onlyWait => partner == null && !reauth.any;

  DeviceTrust passed() => DeviceTrust(
    trusted: true,
    deviceId: deviceId,
    deviceName: deviceName,
    known: true,
  );
}

/// Decides, once per sign-in, whether this phone may open the account, and
/// records it in `users/{uid}/devices/{deviceId}` once it passes.
///
/// - No phones yet: this is the first; trusted (`via: 'first'`).
/// - A known phone, and some phone was seen within 180 days: trusted
///   (`lastSeenAt` refreshed at most once a day).
/// - Otherwise: "Confirm it's you" until the partner approves, the account
///   is confirmed, or the 7-day wait ends.
///
/// SERVER-SIDE CHECK NEEDED: this runs in the app. Someone with a modified
/// client signed in to the same Firebase account could skip it and read
/// what the rules let that account read. Closing that needs the server to
/// refuse couple data until the phone has passed, e.g. a blocking auth
/// function (`beforeSignIn`) or a custom claim set by a callable once a
/// `devices` doc exists, checked by the rules (Blaze plan). Until then this
/// keeps an ordinary new owner of a recycled number out, not an attacker.
class DeviceTrustController extends AsyncNotifier<DeviceTrust> {
  DeviceTrustController(this.uid);

  final String uid;

  /// Ask again when no phone has been seen for this long.
  static const inactiveAfter = Duration(days: 180);

  /// Refresh `lastSeenAt` at most this often.
  static const touchEvery = Duration(days: 1);

  /// The last-resort wait.
  static const waitFor = Duration(days: 7);

  /// "It wasn't me" pauses waiting phones for this long.
  static const blockFor = Duration(days: 30);

  late DeviceTrustService _service;

  @override
  Future<DeviceTrust> build() async {
    _service = ref.watch(deviceTrustServiceProvider);
    final identity = ref.watch(deviceIdentityServiceProvider);
    final now = ref.watch(securityClockProvider)();

    final deviceId = await identity.deviceId(uid);
    final deviceName = await identity.deviceName();
    final devices = await _service.loadDevices(uid);

    if (devices.isEmpty) {
      await _service.addDevice(
        uid: uid,
        deviceId: deviceId,
        name: deviceName,
        via: DeviceVia.first,
      );
      return DeviceTrust(
        trusted: true,
        deviceId: deviceId,
        deviceName: deviceName,
        known: true,
      );
    }

    final mine = devices.where((d) => d.id == deviceId).firstOrNull;
    // Pending server timestamps read as null: just written, so "now".
    final newest = devices
        .map((d) => d.seenAt ?? now)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final inactive = now.difference(newest) > inactiveAfter;

    if (mine != null && !inactive) {
      final seen = mine.seenAt;
      if (seen == null || now.difference(seen) >= touchEvery) {
        // Best effort: a missed refresh only matters after 180 days.
        unawaited(
          _service
              .touchDevice(uid: uid, deviceId: deviceId)
              .catchError((Object e) => debugPrint('device touch: $e')),
        );
      }
      return DeviceTrust(
        trusted: true,
        deviceId: deviceId,
        deviceName: deviceName,
        known: true,
      );
    }

    final partner = await _service.loadPartner(uid);
    final existing = partner == null
        ? null
        : await _service.findCheck(
            cid: partner.coupleId,
            uid: uid,
            deviceId: deviceId,
          );
    return DeviceTrust(
      trusted: false,
      deviceId: deviceId,
      deviceName: deviceName,
      known: mine != null,
      reason: mine == null ? NewPhoneReason.newPhone : NewPhoneReason.inactive,
      partner: partner,
      reauth: ref.read(accountReauthProvider).options(),
      existingCheck: existing,
    );
  }

  DeviceTrust get _trust => state.requireValue;

  /// The partner said yes to [check].
  Future<void> passWithPartner(DeviceCheck check) async {
    final partner = _trust.partner;
    if (check.status != DeviceCheckStatus.approved ||
        partner == null ||
        check.decidedBy != partner.uid) {
      throw StateError('That check was not approved by the partner');
    }
    await _pass(DeviceVia.partner);
    await _quietly(() => _service.deleteCheck(partner.coupleId, check.id));
  }

  /// The account's password or Google account confirmed it.
  Future<void> passWithAccount() => _pass(DeviceVia.email);

  /// The 7-day wait is over, and the owner didn't say "It wasn't me".
  Future<void> passAfterWait() async {
    await _pass(DeviceVia.wait);
    await _quietly(
      () => _service.deleteEvent(uid, SecurityEvent.waitId(_trust.deviceId)),
    );
  }

  Future<void> _pass(DeviceVia via) async {
    final trust = _trust;
    if (trust.known) {
      await _service.touchDevice(uid: uid, deviceId: trust.deviceId);
    } else {
      await _service.addDevice(
        uid: uid,
        deviceId: trust.deviceId,
        name: trust.deviceName,
        via: via,
      );
    }
    // Lets the owner's other phones know.
    await _quietly(
      () => _service.addEvent(
        uid: uid,
        id: SecurityEvent.approvedId(
          trust.deviceId,
          ref.read(securityClockProvider)(),
        ),
        type: SecurityEventType.newPhoneApproved,
        deviceName: trust.deviceName,
      ),
    );
    if (ref.mounted) state = AsyncData(trust.passed());
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('device trust cleanup: $e');
    }
  }
}
