import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:couple_app/features/vault/data/vault_crypto.dart'
    show WrappedKeys;
import 'package:couple_app/features/vault/models/vault_event.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';

/// Encrypted vault files: `couples/{cid}/vault/{fileId}`.
///
/// Behind an interface so tests can keep files in memory.
abstract class VaultBlobStore {
  /// Uploads already-encrypted [bytes]. [onProgress] gets 0.0 to 1.0.
  Future<void> put(
    String path,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  });

  /// Downloads into memory. Never touches the disk.
  Future<Uint8List> get(String path);

  /// Deletes; a file that is already gone counts as deleted.
  Future<void> delete(String path);
}

/// [VaultBlobStore] on Firebase Storage. Files are opaque
/// `application/octet-stream`.
class FirebaseVaultBlobStore implements VaultBlobStore {
  FirebaseVaultBlobStore([FirebaseStorage? storage])
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<void> put(
    String path,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    final task = _storage
        .ref(path)
        .putData(
          bytes,
          SettableMetadata(contentType: 'application/octet-stream'),
        );
    StreamSubscription<TaskSnapshot>? sub;
    if (onProgress != null) {
      sub = task.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0) {
          onProgress(snap.bytesTransferred / snap.totalBytes);
        }
      }, onError: (_) {});
    }
    try {
      await task;
    } finally {
      await sub?.cancel();
    }
  }

  @override
  Future<Uint8List> get(String path) async {
    final data = await _storage.ref(path).getData(VaultService.maxFileBytes);
    if (data == null) throw StateError('Missing vault file');
    return data;
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}

/// [VaultBlobStore] in memory, for tests and previews.
class MemoryVaultBlobStore implements VaultBlobStore {
  final files = <String, Uint8List>{};

  @override
  Future<void> put(
    String path,
    Uint8List bytes, {
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(.5);
    files[path] = Uint8List.fromList(bytes);
    onProgress?.call(1);
  }

  @override
  Future<Uint8List> get(String path) async {
    final bytes = files[path];
    if (bytes == null) throw StateError('Missing vault file');
    return bytes;
  }

  @override
  Future<void> delete(String path) async => files.remove(path);
}

/// Thrown by [VaultService.createVault] when the other partner set the
/// vault up a moment earlier.
class VaultExistsException implements Exception {
  const VaultExistsException();
  @override
  String toString() => 'The vault is already set up.';
}

/// Thrown when no more phones can be registered.
class VaultDeviceLimitException implements Exception {
  const VaultDeviceLimitException();
  @override
  String toString() =>
      'This vault already has ${VaultMeta.maxDevices} phones. '
      'Delete the vault to start again.';
}

/// Reads and writes the vault's encrypted data. It never sees a key or
/// anything readable: callers encrypt first (see `VaultSession`).
///
/// - `couples/{cid}/vault/meta`: phones, sealed keys and the verifier.
/// - `couples/{cid}/vaultItems/{id}`: photos and messages.
/// - `couples/{cid}/vaultEvents/{id}`: alerts for the other partner.
/// - Storage `couples/{cid}/vault/{fileId}`: encrypted photos.
class VaultService {
  VaultService({FirebaseFirestore? firestore, VaultBlobStore? blobs})
    : _db = firestore ?? FirebaseFirestore.instance,
      blobs = blobs ?? FirebaseVaultBlobStore();

  /// Files must be smaller than 15 MB.
  static const maxFileBytes = 15 * 1024 * 1024 - 1;

  /// Longest encrypted content string.
  static const maxCtLength = 20000;

  static const _maxNameLength = 60;
  static final _uuid = Uuid();

  final FirebaseFirestore _db;
  final VaultBlobStore blobs;

  DocumentReference<Map<String, dynamic>> _couple(String cid) =>
      _db.collection('couples').doc(cid);

  DocumentReference<Map<String, dynamic>> metaRef(String cid) =>
      _couple(cid).collection('vault').doc('meta');

  CollectionReference<Map<String, dynamic>> itemsRef(String cid) =>
      _couple(cid).collection('vaultItems');

  CollectionReference<Map<String, dynamic>> eventsRef(String cid) =>
      _couple(cid).collection('vaultEvents');

  static String clampName(String name) {
    final trimmed = name.trim().isEmpty ? 'Phone' : name.trim();
    return trimmed.length <= _maxNameLength
        ? trimmed
        : trimmed.substring(0, _maxNameLength);
  }

  // ---- Meta -----------------------------------------------------------------

  /// The vault's settings; null while it isn't set up.
  Stream<VaultMeta?> watchMeta(String cid) => metaRef(cid).snapshots().map(
    (doc) => doc.exists ? VaultMeta.fromMap(doc.data()!) : null,
  );

  Future<VaultMeta?> getMeta(String cid) async {
    final doc = await metaRef(cid).get();
    return doc.exists ? VaultMeta.fromMap(doc.data()!) : null;
  }

  /// Creates the vault with [device] (this phone) approved and holding
  /// [keys]. Throws [VaultExistsException] if it already exists.
  Future<void> createVault({
    required String cid,
    required String uid,
    required VaultDevice device,
    required WrappedKeys keys,
    required String verifier,
  }) async {
    final ref = metaRef(cid);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) throw const VaultExistsException();
      tx.set(ref, {
        'version': 1,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'devices': {device.id: device.toNewMap()},
        'keys': {device.id: keys.toMap()},
        'verifier': verifier,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Adds this phone, unapproved, and tells the other partner.
  Future<void> registerDevice({
    required String cid,
    required VaultDevice device,
  }) async {
    final meta = await getMeta(cid);
    if (meta == null) throw StateError('No vault');
    if (meta.devices.containsKey(device.id)) return;
    if (meta.devices.length >= VaultMeta.maxDevices) {
      throw const VaultDeviceLimitException();
    }
    await metaRef(cid).update({
      'devices.${device.id}': device.toNewMap(),
      'updatedBy': device.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addEvent(
      cid: cid,
      type: VaultEventType.deviceAdded,
      uid: device.uid,
      deviceName: device.name,
    );
  }

  /// Gives [deviceId] the sealed keys and marks it approved.
  Future<void> approveDevice({
    required String cid,
    required String uid,
    required String deviceId,
    required WrappedKeys keys,
    required String approverDeviceName,
  }) async {
    await metaRef(cid).update({
      'keys.$deviceId': keys.toMap(),
      'devices.$deviceId.approved': true,
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addEvent(
      cid: cid,
      type: VaultEventType.deviceApproved,
      uid: uid,
      deviceName: approverDeviceName,
    );
  }

  /// Replaces the passcode verifier (a code was changed or reset).
  Future<void> setVerifier({
    required String cid,
    required String uid,
    required String verifier,
    required String deviceName,
  }) async {
    await metaRef(cid).update({
      'verifier': verifier,
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addEvent(
      cid: cid,
      type: VaultEventType.codeChanged,
      uid: uid,
      deviceName: deviceName,
    );
  }

  // ---- Items ----------------------------------------------------------------

  /// A fresh item id (nothing is written).
  String newItemId(String cid) => itemsRef(cid).doc().id;

  /// A fresh Storage path for an encrypted file.
  String newFilePath(String cid) => 'couples/$cid/vault/${_uuid.v4()}';

  /// Every item on both shelves. Each phone reads all of them, so the
  /// server can't tell which shelf was opened; callers keep their own.
  Stream<List<VaultItem>> watchItems(String cid) => itemsRef(
    cid,
  ).snapshots().map((snap) => snap.docs.map(VaultItem.fromDoc).toList());

  Future<List<VaultItem>> getItems(String cid) async {
    final snap = await itemsRef(cid).get();
    return snap.docs.map(VaultItem.fromDoc).toList();
  }

  Map<String, dynamic> _itemData({
    required String senderId,
    required VaultItemKind kind,
    required String shelf,
    required String ct,
    required VaultPolicy policy,
    required DateTime now,
    String? photoPath,
    String? thumbPath,
  }) {
    if (ct.length > maxCtLength) {
      throw ArgumentError('Encrypted content is too long');
    }
    return {
      'senderId': senderId,
      'kind': kind.name,
      'shelf': shelf,
      'ct': ct,
      'photoPath': photoPath,
      'thumbPath': thumbPath,
      'policy': policy.value,
      'expiresAt': policy == VaultPolicy.day
          ? Timestamp.fromDate(now.add(VaultPolicy.lifetime))
          : null,
      'viewedBy': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Adds an encrypted message.
  Future<void> addMessage({
    required String cid,
    required String itemId,
    required String senderId,
    required String shelf,
    required String ct,
    required VaultPolicy policy,
    DateTime? now,
  }) => itemsRef(cid)
      .doc(itemId)
      .set(
        _itemData(
          senderId: senderId,
          kind: VaultItemKind.message,
          shelf: shelf,
          ct: ct,
          policy: policy,
          now: now ?? DateTime.now(),
        ),
      );

  /// Uploads an encrypted photo and thumbnail, then adds the item. If the
  /// item can't be written the files are removed again.
  Future<void> addPhoto({
    required String cid,
    required String itemId,
    required String senderId,
    required String shelf,
    required String ct,
    required VaultPolicy policy,
    required String photoPath,
    required Uint8List photo,
    required String thumbPath,
    required Uint8List thumb,
    void Function(double progress)? onProgress,
    DateTime? now,
  }) async {
    if (photo.length > maxFileBytes || thumb.length > maxFileBytes) {
      throw ArgumentError('Photo is too large');
    }
    final total = photo.length + thumb.length;
    await blobs.put(
      thumbPath,
      thumb,
      onProgress: onProgress == null
          ? null
          : (p) => onProgress(p * thumb.length / total),
    );
    await blobs.put(
      photoPath,
      photo,
      onProgress: onProgress == null
          ? null
          : (p) => onProgress((thumb.length + p * photo.length) / total),
    );
    try {
      await itemsRef(cid)
          .doc(itemId)
          .set(
            _itemData(
              senderId: senderId,
              kind: VaultItemKind.photo,
              shelf: shelf,
              ct: ct,
              policy: policy,
              now: now ?? DateTime.now(),
              photoPath: photoPath,
              thumbPath: thumbPath,
            ),
          );
    } catch (_) {
      await _deleteFiles([photoPath, thumbPath]);
      rethrow;
    }
  }

  /// Records that [uid] has seen the item (only their own key changes).
  Future<void> markViewed({
    required String cid,
    required String itemId,
    required String uid,
  }) => itemsRef(
    cid,
  ).doc(itemId).update({'viewedBy.$uid': FieldValue.serverTimestamp()});

  /// Deletes the item and then its files.
  Future<void> deleteItem(String cid, VaultItem item) async {
    await itemsRef(cid).doc(item.id).delete();
    await _deleteFiles(item.files);
  }

  /// Deletes what should already be gone, on either shelf: items past their
  /// 24 hours, and view-once items [uid] received and has seen (the view
  /// was interrupted before the delete). Returns how many were deleted.
  Future<int> cleanUp({
    required String cid,
    required String uid,
    required DateTime now,
    List<VaultItem>? items,
  }) async {
    final all = items ?? await getItems(cid);
    var deleted = 0;
    for (final item in all) {
      final expired = item.isExpired(now);
      final seenOnce =
          item.policy == VaultPolicy.once &&
          item.senderId != uid &&
          item.viewedByUid(uid);
      if (!expired && !seenOnce) continue;
      try {
        await deleteItem(cid, item);
        deleted++;
      } catch (e) {
        debugPrint('vault: clean-up of ${item.id} failed: $e');
      }
    }
    return deleted;
  }

  /// An encrypted file, into memory.
  Future<Uint8List> download(String path) => blobs.get(path);

  Future<void> _deleteFiles(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await blobs.delete(path);
      } catch (e) {
        debugPrint('vault: delete of a file failed: $e');
      }
    }
  }

  // ---- Events ---------------------------------------------------------------

  /// Every alert, newest first.
  Stream<List<VaultEvent>> watchEvents(String cid) =>
      eventsRef(cid).snapshots().map((snap) {
        final events = [for (final doc in snap.docs) ?VaultEvent.fromDoc(doc)];
        events.sort((a, b) {
          final x = a.at;
          final y = b.at;
          if (x == null) return -1;
          if (y == null) return 1;
          return y.compareTo(x);
        });
        return events;
      });

  Future<void> addEvent({
    required String cid,
    required VaultEventType type,
    required String uid,
    required String deviceName,
  }) => eventsRef(cid).add({
    'type': type.name,
    'uid': uid,
    'deviceName': clampName(deviceName),
    'at': FieldValue.serverTimestamp(),
  });

  Future<void> dismissEvent(String cid, String eventId) =>
      eventsRef(cid).doc(eventId).delete();

  // ---- Deleting -------------------------------------------------------------

  /// Deletes the whole vault for both partners: every item and file, every
  /// alert and the settings. Then leaves one `wiped` alert for the other
  /// partner. Nothing can be recovered.
  Future<void> wipe({
    required String cid,
    required String uid,
    required String deviceName,
  }) async {
    final items = await getItems(cid);
    for (final item in items) {
      await _deleteFiles(item.files);
    }
    final events = await eventsRef(cid).get();
    await _deleteDocs([
      for (final item in items) itemsRef(cid).doc(item.id),
      for (final doc in events.docs) doc.reference,
      metaRef(cid),
    ]);
    await addEvent(
      cid: cid,
      type: VaultEventType.wiped,
      uid: uid,
      deviceName: deviceName,
    );
  }

  /// Deletes one shelf's items and files, and leaves a `wiped` alert.
  Future<void> wipeShelf({
    required String cid,
    required String shelf,
    required String uid,
    required String deviceName,
  }) async {
    final items = (await getItems(cid)).where((i) => i.shelf == shelf);
    for (final item in items) {
      await _deleteFiles(item.files);
    }
    await _deleteDocs([for (final item in items) itemsRef(cid).doc(item.id)]);
    await addEvent(
      cid: cid,
      type: VaultEventType.wiped,
      uid: uid,
      deviceName: deviceName,
    );
  }

  Future<void> _deleteDocs(
    List<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    for (var i = 0; i < refs.length; i += 400) {
      final batch = _db.batch();
      for (final ref in refs.skip(i).take(400)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }
}
