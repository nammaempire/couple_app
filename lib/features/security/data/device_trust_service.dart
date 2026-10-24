import 'dart:math';

import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/security/models/device_check.dart';
import 'package:couple_app/features/security/models/known_device.dart';
import 'package:couple_app/features/security/models/security_event.dart';

/// The partner who can vouch for a new phone.
class PartnerContact {
  const PartnerContact({
    required this.coupleId,
    required this.uid,
    required this.name,
  });

  final String coupleId;
  final String uid;

  /// What this user calls them (their nickname for them, else their name).
  final String name;
}

/// Firestore for sign-in protection: known phones, partner checks, security
/// notices and the "It wasn't me" block.
///
/// Writes (the rules match these exactly):
/// - `users/{uid}/devices/{deviceId}`: create `{name, addedAt, lastSeenAt,
///   via}` with server timestamps; update only `lastSeenAt`; delete.
/// - `couples/{cid}/deviceChecks/{id}`: create `{uid, deviceId, deviceName,
///   createdAt, status: 'pending', code}`; the other member updates
///   `{status, decidedBy, decidedAt}`; the creator deletes.
/// - `users/{uid}/securityEvents/{id}`: create `{type, deviceName, at}`;
///   the owner deletes.
/// - `users/{uid}.blockNewPhoneUntil`: set by the owner (merge).
class DeviceTrustService {
  DeviceTrustService({Db? db, Random? random})
    : _db = db ?? Db.instance,
      _random = random ?? Random.secure();

  final Db _db;
  final Random _random;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      _user(uid).collection('devices');

  CollectionReference<Map<String, dynamic>> _events(String uid) =>
      _user(uid).collection('securityEvents');

  CollectionReference<Map<String, dynamic>> _checks(String cid) =>
      _db.collection('couples').doc(cid).collection('deviceChecks');

  // ---- Known phones ---------------------------------------------------------

  /// Every known phone, straight from the server: a phone that went offline
  /// right after signing in must not find an empty cache and call itself
  /// the account's first phone.
  Future<List<KnownDevice>> loadDevices(String uid) async {
    final snap = await _devices(
      uid,
    ).get(const GetOptions(source: Source.server));
    return snap.docs.map(KnownDevice.fromDoc).toList();
  }

  /// Every known phone, most recently seen first.
  Stream<List<KnownDevice>> watchDevices(String uid) =>
      _devices(uid).snapshots().map((snap) {
        final list = snap.docs.map(KnownDevice.fromDoc).toList();
        list.sort((a, b) {
          final x = a.seenAt;
          final y = b.seenAt;
          if (x == null && y == null) return a.id.compareTo(b.id);
          if (x == null) return -1;
          if (y == null) return 1;
          return y.compareTo(x);
        });
        return list;
      });

  /// Records a phone that passed: `{name, addedAt, lastSeenAt, via}`.
  Future<void> addDevice({
    required String uid,
    required String deviceId,
    required String name,
    required DeviceVia via,
  }) => _devices(uid).doc(deviceId).set({
    'name': KnownDevice.clampName(name),
    'addedAt': FieldValue.serverTimestamp(),
    'lastSeenAt': FieldValue.serverTimestamp(),
    'via': via.name,
  });

  /// Marks the phone seen now (only `lastSeenAt` changes).
  Future<void> touchDevice({required String uid, required String deviceId}) =>
      _devices(
        uid,
      ).doc(deviceId).update({'lastSeenAt': FieldValue.serverTimestamp()});

  Future<void> removeDevice({required String uid, required String deviceId}) =>
      _devices(uid).doc(deviceId).delete();

  // ---- The partner ----------------------------------------------------------

  /// The partner who could vouch for [uid], or null when [uid] isn't paired
  /// (or is still waiting for their partner to join). Reads only the
  /// profile, the couple's member list and the partner's name.
  Future<PartnerContact?> loadPartner(String uid) async {
    final me = await _user(uid).get();
    final cid = me.data()?['coupleId'] as String?;
    if (cid == null) return null;
    final couple = await _db.collection('couples').doc(cid).get();
    final data = couple.data();
    if (data == null) return null;
    final members = List<String>.from(
      (data['memberIds'] as List<dynamic>?) ?? const [],
    );
    if (!members.contains(uid)) return null;
    final partnerId = members.where((m) => m != uid).firstOrNull;
    if (partnerId == null) return null;

    final nicknames = (data['nicknames'] as Map<String, dynamic>?) ?? const {};
    var name = (nicknames[uid] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      try {
        final partner = await _user(partnerId).get();
        name = (partner.data()?['displayName'] as String?)?.trim() ?? '';
      } catch (_) {
        // Their name is a nicety; "your partner" will do.
      }
    }
    return PartnerContact(
      coupleId: cid,
      uid: partnerId,
      name: name.isEmpty ? 'your partner' : name,
    );
  }

  // ---- Partner checks -------------------------------------------------------

  /// A random number from 10 to 99, shown on the new phone.
  int newCode() => 10 + _random.nextInt(90);

  /// Asks the partner to vouch for this phone. Returns the check's id.
  Future<String> createCheck({
    required String cid,
    required String uid,
    required String deviceId,
    required String deviceName,
    required int code,
  }) async {
    final doc = _checks(cid).doc();
    await doc.set({
      'uid': uid,
      'deviceId': deviceId,
      'deviceName': KnownDevice.clampName(deviceName),
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
      'code': code,
    });
    return doc.id;
  }

  /// This phone's latest check, if it made one (to pick up where it left
  /// off after the app restarts).
  Future<DeviceCheck?> findCheck({
    required String cid,
    required String uid,
    required String deviceId,
  }) async {
    final snap = await _checks(
      cid,
    ).where('uid', isEqualTo: uid).where('deviceId', isEqualTo: deviceId).get();
    final checks = snap.docs.map(DeviceCheck.fromDoc).toList();
    if (checks.isEmpty) return null;
    checks.sort((a, b) {
      final x = a.createdAt;
      final y = b.createdAt;
      if (x == null) return -1;
      if (y == null) return 1;
      return y.compareTo(x);
    });
    return checks.first;
  }

  Stream<DeviceCheck?> watchCheck(String cid, String checkId) => _checks(cid)
      .doc(checkId)
      .snapshots()
      .map((d) => d.exists ? DeviceCheck.fromDoc(d) : null);

  /// [partnerId]'s checks still waiting for an answer.
  Stream<List<DeviceCheck>> watchPendingChecks(String cid, String partnerId) =>
      _checks(cid)
          .where('uid', isEqualTo: partnerId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snap) => snap.docs.map(DeviceCheck.fromDoc).toList());

  /// The partner's answer. Saying no also leaves a notice for the owner's
  /// other phones.
  Future<void> decideCheck({
    required String cid,
    required DeviceCheck check,
    required String decidedBy,
    required bool approved,
  }) async {
    final batch = _db.batch();
    batch.update(_checks(cid).doc(check.id), {
      'status': approved ? 'approved' : 'rejected',
      'decidedBy': decidedBy,
      'decidedAt': FieldValue.serverTimestamp(),
    });
    if (!approved) {
      batch.set(_events(check.uid).doc(), {
        'type': SecurityEventType.newPhoneRejected.name,
        'deviceName': KnownDevice.clampName(check.deviceName),
        'at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> deleteCheck(String cid, String checkId) =>
      _checks(cid).doc(checkId).delete();

  // ---- Security notices -----------------------------------------------------

  /// Every notice for [uid], newest first.
  Stream<List<SecurityEvent>> watchEvents(String uid) =>
      _events(uid).snapshots().map((snap) {
        final list = [for (final doc in snap.docs) ?SecurityEvent.fromDoc(doc)];
        list.sort((a, b) {
          final x = a.at;
          final y = b.at;
          if (x == null) return -1;
          if (y == null) return 1;
          return y.compareTo(x);
        });
        return list;
      });

  Future<void> addEvent({
    required String uid,
    required String id,
    required SecurityEventType type,
    required String deviceName,
  }) => _events(uid).doc(id).set({
    'type': type.name,
    'deviceName': KnownDevice.clampName(deviceName),
    'at': FieldValue.serverTimestamp(),
  });

  Future<void> deleteEvent(String uid, String id) =>
      _events(uid).doc(id).delete();

  /// When this phone's 7-day wait began (server time), live. Null until the
  /// waiting notice exists (or after the owner dismissed it).
  Stream<({bool exists, DateTime? at})> watchWaitStart(
    String uid,
    String deviceId,
  ) => _events(uid)
      .doc(SecurityEvent.waitId(deviceId))
      .snapshots()
      .map(
        (d) =>
            (exists: d.exists, at: (d.data()?['at'] as Timestamp?)?.toDate()),
      );

  // ---- "It wasn't me" -------------------------------------------------------

  /// `users/{uid}.blockNewPhoneUntil`, live.
  Stream<DateTime?> watchBlockUntil(String uid) => _user(uid).snapshots().map(
    (d) => (d.data()?['blockNewPhoneUntil'] as Timestamp?)?.toDate(),
  );

  /// Stops any waiting phone from getting in until [until].
  Future<void> blockNewPhones(String uid, DateTime until) => _user(uid).set({
    'blockNewPhoneUntil': Timestamp.fromDate(until),
  }, SetOptions(merge: true));
}
