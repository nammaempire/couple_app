import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/app_lock/providers/app_lock_providers.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/security/providers/security_providers.dart';
import 'package:couple_app/features/vault/data/device_keystore.dart';
import 'package:couple_app/features/vault/data/vault_crypto.dart';
import 'package:couple_app/features/vault/data/vault_photo_preparer.dart';
import 'package:couple_app/features/vault/data/vault_service.dart';
import 'package:couple_app/features/vault/models/vault_event.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';

/// The outcome of entering a code or using the fingerprint.
enum VaultUnlockResult {
  unlocked,
  wrong,

  /// Too many wrong codes; see [VaultSessionState.cooldownUntil].
  coolingDown,

  /// This phone hasn't been approved yet.
  notApproved,

  /// The fingerprint / face prompt was cancelled or failed.
  cancelled,

  /// Something else went wrong (offline, a key that no longer fits).
  failed,
}

/// The outcome of choosing a new code.
enum VaultCodeChange {
  changed,

  /// The new code is the other code; the UI says only "choose another".
  rejected,
}

/// What the vault screens show about this phone's session. Keys are never
/// part of it.
@immutable
class VaultSessionState {
  const VaultSessionState({
    this.ready = false,
    this.identity,
    this.unlocked = false,
    this.shelf,
    this.failedAttempts = 0,
    this.cooldownUntil,
    this.biometric = false,
    this.biometricAsked = false,
    this.busy = false,
    this.wrongCount = 0,
    this.lockCount = 0,
  });

  /// This phone's identity and local state have loaded.
  final bool ready;
  final DeviceIdentity? identity;
  final bool unlocked;

  /// The open shelf, `'a'` or `'b'`; null while locked.
  final String? shelf;

  final int failedAttempts;
  final DateTime? cooldownUntil;

  /// Fingerprint / face unlock is on for this phone.
  final bool biometric;
  final bool biometricAsked;

  /// A code is being checked.
  final bool busy;

  /// Goes up with every wrong code (the pad shakes).
  final int wrongCount;

  /// Goes up every time the vault locks (open screens close).
  final int lockCount;

  VaultSessionState copyWith({
    bool? ready,
    DeviceIdentity? identity,
    bool? unlocked,
    String? Function()? shelf,
    int? failedAttempts,
    DateTime? Function()? cooldownUntil,
    bool? biometric,
    bool? biometricAsked,
    bool? busy,
    int? wrongCount,
    int? lockCount,
  }) => VaultSessionState(
    ready: ready ?? this.ready,
    identity: identity ?? this.identity,
    unlocked: unlocked ?? this.unlocked,
    shelf: shelf == null ? this.shelf : shelf(),
    failedAttempts: failedAttempts ?? this.failedAttempts,
    cooldownUntil: cooldownUntil == null ? this.cooldownUntil : cooldownUntil(),
    biometric: biometric ?? this.biometric,
    biometricAsked: biometricAsked ?? this.biometricAsked,
    busy: busy ?? this.busy,
    wrongCount: wrongCount ?? this.wrongCount,
    lockCount: lockCount ?? this.lockCount,
  );
}

/// Decrypted bytes and text, in memory only, dropped when the vault locks.
class VaultMemoryCache {
  final _thumbs = <String, Uint8List>{};
  final _photos = <String, Uint8List>{};
  final _texts = <String, String>{};
  final _photoInfo = <String, VaultPhotoContent>{};
  final _images = <String, MemoryImage>{};

  /// Full photos kept at once; older ones are dropped.
  static const maxPhotos = 4;

  Uint8List? thumb(String id) => _thumbs[id];
  Uint8List? photo(String id) => _photos[id];
  String? text(String id) => _texts[id];
  VaultPhotoContent? photoInfo(String id) => _photoInfo[id];

  void putThumb(String id, Uint8List bytes) => _thumbs[id] = bytes;
  void putText(String id, String text) => _texts[id] = text;
  void putPhotoInfo(String id, VaultPhotoContent info) => _photoInfo[id] = info;

  void putPhoto(String id, Uint8List bytes) {
    _photos[id] = bytes;
    while (_photos.length > maxPhotos) {
      final oldest = _photos.keys.first;
      _drop(_photos.remove(oldest));
      _images.remove('p:$oldest')?.evict();
    }
  }

  /// The image for [bytes], remembered so it can be evicted from Flutter's
  /// image cache on lock.
  MemoryImage image(String key, Uint8List bytes) =>
      _images.putIfAbsent(key, () => MemoryImage(bytes));

  bool get isEmpty =>
      _thumbs.isEmpty && _photos.isEmpty && _texts.isEmpty && _images.isEmpty;

  void evict(String id) {
    _drop(_thumbs.remove(id));
    _drop(_photos.remove(id));
    _texts.remove(id);
    _photoInfo.remove(id);
    _images.remove('t:$id')?.evict();
    _images.remove('p:$id')?.evict();
  }

  void clear() {
    for (final image in _images.values) {
      image.evict();
    }
    _images.clear();
    _thumbs.values.forEach(_drop);
    _photos.values.forEach(_drop);
    _thumbs.clear();
    _photos.clear();
    _texts.clear();
    _photoInfo.clear();
  }

  static void _drop(Uint8List? bytes) {
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
  }
}

/// The vault on this phone: locked or open, which shelf is open, the keys
/// (in memory only while open), wrong-code attempts and the cooldown
/// (persisted in the keystore), and auto-lock.
///
/// Everything that needs a key goes through here, so the keys never leave
/// this object. Locking wipes them and every decrypted byte.
class VaultSession extends Notifier<VaultSessionState> {
  /// Locks after this long without a touch.
  static const idleTimeout = Duration(minutes: 2);

  /// Wrong codes allowed before the cooldowns start.
  static const freeAttempts = 5;

  /// After [freeAttempts], each further wrong code waits longer.
  static const cooldowns = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// The partner is told after this many wrong codes in a row.
  static const alertAfter = 3;

  /// A trip to the background that starts this soon after a picker or
  /// prompt closes doesn't lock.
  static const grace = Duration(seconds: 3);

  late VaultService _service;
  late DeviceKeystore _keystore;
  late VaultCrypto _crypto;
  late DateTime Function() _now;
  late String _uid;
  late String _cid;

  VaultKeys? _keys;
  bool _decoy = false;
  String? _deviceName;
  Timer? _idle;
  int _suspensions = 0;
  DateTime? _graceUntil;
  bool _registering = false;

  /// Decrypted bytes and text for the open shelf.
  final cache = VaultMemoryCache();

  @override
  VaultSessionState build() {
    _service = ref.watch(vaultServiceProvider);
    _keystore = ref.watch(deviceKeystoreProvider);
    _crypto = ref.watch(vaultCryptoProvider);
    _now = ref.watch(vaultClockProvider);
    _uid = ref.watch(currentUidProvider);
    _cid = ref.watch(currentCoupleIdProvider);
    ref.onDispose(_forget);
    unawaited(_load());
    return const VaultSessionState();
  }

  Future<void> _load() async {
    // The same id sign-in protection knows this phone by (made by whichever
    // asks first).
    final identity = await ref
        .read(deviceIdentityServiceProvider)
        .identity(_uid);
    if (!ref.mounted) return;
    final local = await _keystore.loadState(_uid);
    if (!ref.mounted) return;
    state = state.copyWith(
      ready: true,
      identity: identity,
      failedAttempts: local.failedAttempts,
      cooldownUntil: () => local.cooldownUntil,
      biometric: local.biometric,
      biometricAsked: local.biometricAsked,
    );
  }

  bool get isUnlocked => state.unlocked && _keys != null;

  /// Whether this session may approve phones. A decoy session can't: it
  /// would hand the real key to a phone the couple didn't choose.
  bool get canApprove => isUnlocked && !_decoy;

  DeviceIdentity get _identity {
    final identity = state.identity;
    if (identity == null) throw StateError('Vault session not loaded');
    return identity;
  }

  Uint8List get _shelfKey {
    final keys = _keys;
    if (keys == null || !state.unlocked) throw StateError('Vault is locked');
    return _decoy ? keys.dk : keys.vmk;
  }

  String get _shelf => state.shelf!;

  /// This phone's model, e.g. "Pixel 8".
  Future<String> deviceName() async => _deviceName ??= VaultService.clampName(
    await ref.read(deviceNameSourceProvider).deviceName(),
  );

  bool _coolingDown() {
    final until = state.cooldownUntil;
    return until != null && _now().isBefore(until);
  }

  // ---- Setting up and registering -------------------------------------------

  /// Creates the vault with this phone approved, and opens it on the real
  /// shelf. Throws [VaultExistsException] if the partner just did.
  Future<void> setUp({
    required String realCode,
    required String decoyCode,
    bool biometric = false,
  }) async {
    if (!isValidVaultCode(realCode) || !isValidVaultCode(decoyCode)) {
      throw ArgumentError('Codes are six digits');
    }
    if (realCode == decoyCode) throw ArgumentError('Codes must differ');
    final identity = _identity;
    final keys = _crypto.newVaultKeys();
    final payload = await _crypto.buildVerifier(
      realCode: realCode,
      decoyCode: decoyCode,
      realShelf: _crypto.randomShelf(),
    );
    final name = await deviceName();
    await _service.createVault(
      cid: _cid,
      uid: _uid,
      device: VaultDevice(
        id: identity.deviceId,
        uid: _uid,
        publicKey: identity.publicKeyB64,
        name: name,
        approved: true,
      ),
      keys: await _crypto.wrapKeys(keys, identity.publicKeyB64),
      verifier: await _crypto.sealVerifier(keys.vmk, payload),
    );
    await _saveLocal(
      (s) => s.copyWith(biometric: biometric, biometricAsked: true),
    );
    if (!ref.mounted) return;
    _open(keys, shelf: payload.realShelf, decoy: false);
  }

  /// Adds this phone to an existing vault, waiting for approval.
  Future<void> register() async {
    if (_registering) return;
    _registering = true;
    try {
      final identity = _identity;
      await _service.registerDevice(
        cid: _cid,
        device: VaultDevice(
          id: identity.deviceId,
          uid: _uid,
          publicKey: identity.publicKeyB64,
          name: await deviceName(),
          approved: false,
        ),
      );
    } finally {
      _registering = false;
    }
  }

  // ---- Unlocking --------------------------------------------------------------

  /// Checks [code]: the real code opens the real shelf, the decoy code the
  /// decoy shelf, and the result looks the same either way.
  Future<VaultUnlockResult> enterCode(String code) async {
    if (state.busy) return VaultUnlockResult.failed;
    if (_coolingDown()) return VaultUnlockResult.coolingDown;
    state = state.copyWith(busy: true);
    try {
      final opened = await _openKeys();
      if (opened == null) return VaultUnlockResult.notApproved;
      final (keys, payload) = opened;
      final match = await _crypto.checkCode(payload, code);
      if (!ref.mounted) return VaultUnlockResult.failed;
      if (match == CodeMatch.none) {
        keys.wipe();
        await _recordWrong();
        return _coolingDown()
            ? VaultUnlockResult.coolingDown
            : VaultUnlockResult.wrong;
      }
      final decoy = match == CodeMatch.decoy;
      await _resetAttempts();
      if (!ref.mounted) return VaultUnlockResult.failed;
      _open(
        keys,
        shelf: decoy ? payload.decoyShelf : payload.realShelf,
        decoy: decoy,
      );
      return VaultUnlockResult.unlocked;
    } on VaultCryptoException catch (e) {
      debugPrint('vault: unlock failed: $e');
      return VaultUnlockResult.failed;
    } catch (e) {
      debugPrint('vault: unlock failed: $e');
      return VaultUnlockResult.failed;
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// Opens the real shelf after the phone's fingerprint / face prompt.
  Future<VaultUnlockResult> unlockWithBiometrics() async {
    if (!state.biometric || state.busy) return VaultUnlockResult.failed;
    final auth = ref.read(biometricAuthProvider);
    final appLock = ref.read(appLockControllerProvider.notifier);
    final ok = await suspendWhile(
      appLock.suspendWhile(auth.authenticate('Open your private space')),
    );
    if (!ok) return VaultUnlockResult.cancelled;
    if (!ref.mounted) return VaultUnlockResult.failed;
    state = state.copyWith(busy: true);
    try {
      final opened = await _openKeys();
      if (opened == null) return VaultUnlockResult.notApproved;
      final (keys, payload) = opened;
      await _resetAttempts();
      if (!ref.mounted) return VaultUnlockResult.failed;
      _open(keys, shelf: payload.realShelf, decoy: false);
      return VaultUnlockResult.unlocked;
    } catch (e) {
      debugPrint('vault: biometric unlock failed: $e');
      return VaultUnlockResult.failed;
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// This phone's keys and the verifier, from the latest meta. Null if this
  /// phone has no keys yet.
  Future<(VaultKeys, VerifierPayload)?> _openKeys() async {
    final meta = await _service.getMeta(_cid);
    final wrapped = meta?.keys[_identity.deviceId];
    if (meta == null || wrapped == null) return null;
    final keys = await _crypto.unwrapKeys(wrapped, _identity.keyPair);
    try {
      final payload = await _crypto.openVerifier(meta.verifier, keys.vmk);
      return (keys, payload);
    } catch (_) {
      keys.wipe();
      rethrow;
    }
  }

  void _open(VaultKeys keys, {required String shelf, required bool decoy}) {
    _keys?.wipe();
    _keys = keys;
    _decoy = decoy;
    cache.clear();
    state = state.copyWith(unlocked: true, shelf: () => shelf);
    touch();
    unawaited(_cleanUp());
  }

  Future<void> _cleanUp() async {
    try {
      await _service.cleanUp(cid: _cid, uid: _uid, now: _now());
    } catch (e) {
      debugPrint('vault: clean-up failed: $e');
    }
  }

  Future<void> _recordWrong() async {
    final failed = state.failedAttempts + 1;
    DateTime? until;
    if (failed >= freeAttempts) {
      final step = math.min(failed - freeAttempts, cooldowns.length - 1);
      until = _now().add(cooldowns[step]);
    }
    state = state.copyWith(
      failedAttempts: failed,
      cooldownUntil: () => until,
      wrongCount: state.wrongCount + 1,
    );
    await _saveLocal(
      (s) => s.copyWith(failedAttempts: failed, cooldownUntil: () => until),
    );
    final type = until != null
        ? VaultEventType.cooldown
        : failed == alertAfter
        ? VaultEventType.wrongCode
        : null;
    if (type != null) {
      try {
        await _service.addEvent(
          cid: _cid,
          type: type,
          uid: _uid,
          deviceName: await deviceName(),
        );
      } catch (e) {
        debugPrint('vault: alert failed: $e');
      }
    }
  }

  Future<void> _resetAttempts() async {
    if (state.failedAttempts == 0 && state.cooldownUntil == null) return;
    state = state.copyWith(failedAttempts: 0, cooldownUntil: () => null);
    await _saveLocal(
      (s) => s.copyWith(failedAttempts: 0, cooldownUntil: () => null),
    );
  }

  Future<void> _saveLocal(
    VaultLocalState Function(VaultLocalState) change,
  ) async {
    final current = await _keystore.loadState(_uid);
    await _keystore.saveState(_uid, change(current));
  }

  // ---- Locking ------------------------------------------------------------------

  /// Locks: forgets the keys and every decrypted byte.
  void lock() {
    if (!ref.mounted) return _forget();
    _idle?.cancel();
    _idle = null;
    final wasOpen = state.unlocked || _keys != null;
    _keys?.wipe();
    _keys = null;
    _decoy = false;
    cache.clear();
    if (!wasOpen) return;
    state = state.copyWith(
      unlocked: false,
      shelf: () => null,
      lockCount: state.lockCount + 1,
    );
  }

  void _forget() {
    _idle?.cancel();
    _keys?.wipe();
    _keys = null;
    cache.clear();
  }

  /// Restarts the idle timer; called on every touch while open.
  void touch() {
    if (!state.unlocked) return;
    _idle?.cancel();
    _idle = Timer(idleTimeout, lock);
  }

  bool get _suspended {
    if (_suspensions > 0) return true;
    final until = _graceUntil;
    return until != null && !_now().isAfter(until);
  }

  /// Runs [future] (a photo picker, the fingerprint prompt) without the
  /// trip to the background it causes locking the vault.
  Future<T> suspendWhile<T>(Future<T> future) async {
    _suspensions++;
    try {
      return await future;
    } finally {
      _suspensions--;
      _graceUntil = _now().add(grace);
    }
  }

  /// Locks when the app goes to the background or the screen turns off.
  void handleLifecycle(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused) {
      if (!_suspended) lock();
    }
  }

  // ---- Fingerprint / face --------------------------------------------------------

  /// Turns fingerprint / face unlock on (after the prompt succeeds) or off
  /// for this phone. Returns whether it is now on.
  Future<bool> setBiometric(bool on) async {
    var enabled = false;
    if (on) {
      final auth = ref.read(biometricAuthProvider);
      final appLock = ref.read(appLockControllerProvider.notifier);
      enabled = await suspendWhile(
        appLock.suspendWhile(
          auth.authenticate('Use your fingerprint or face for Private'),
        ),
      );
    }
    await _saveLocal(
      (s) => s.copyWith(biometric: enabled, biometricAsked: true),
    );
    if (ref.mounted) {
      state = state.copyWith(biometric: enabled, biometricAsked: true);
    }
    return enabled;
  }

  // ---- Devices and codes ---------------------------------------------------------

  /// Gives [device] the vault keys.
  Future<void> approve(VaultDevice device) async {
    if (!canApprove) throw StateError('Cannot approve from here');
    final wrapped = await _crypto.wrapKeys(_keys!, device.publicKey);
    await _service.approveDevice(
      cid: _cid,
      uid: _uid,
      deviceId: device.id,
      keys: wrapped,
      approverDeviceName: await deviceName(),
    );
  }

  /// Changes the code that opened this session.
  Future<VaultCodeChange> changeCode(String code) =>
      _changeCode(code, decoyCode: false);

  /// Changes the decoy code.
  Future<VaultCodeChange> changeDecoyCode(String code) =>
      _changeCode(code, decoyCode: true);

  Future<VaultCodeChange> _changeCode(
    String code, {
    required bool decoyCode,
  }) async {
    if (!isValidVaultCode(code)) throw ArgumentError('Codes are six digits');
    final keys = _keys;
    if (keys == null) throw StateError('Vault is locked');
    // Start from the latest verifier: the partner may have changed a code.
    final meta = await _service.getMeta(_cid);
    if (meta == null) throw StateError('No vault');
    final payload = await _crypto.openVerifier(meta.verifier, keys.vmk);
    final match = await _crypto.checkCode(payload, code);
    final VerifierPayload next;
    if (!_decoy) {
      // Each code must stay distinct from the other.
      final clash = decoyCode ? CodeMatch.real : CodeMatch.decoy;
      if (match == clash) return VaultCodeChange.rejected;
      next = await _crypto.replaceCode(
        payload,
        realCode: decoyCode ? null : code,
        decoyCode: decoyCode ? code : null,
      );
    } else {
      // A decoy session must never learn or touch the real code. "Change
      // code" changes the decoy code (the one used to get here); "change
      // decoy code" rewrites the verifier unchanged, so the server sees the
      // same kind of write.
      if (match != CodeMatch.none) return VaultCodeChange.rejected;
      next = decoyCode
          ? payload
          : await _crypto.replaceCode(payload, decoyCode: code);
    }
    await _service.setVerifier(
      cid: _cid,
      uid: _uid,
      verifier: await _crypto.sealVerifier(keys.vmk, next),
      deviceName: await deviceName(),
    );
    return VaultCodeChange.changed;
  }

  // ---- Items ----------------------------------------------------------------------

  /// Encrypts and adds a message to the open shelf.
  Future<void> sendMessage(String text, VaultPolicy policy) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (clean.length > VaultMessageContent.maxLength) {
      throw ArgumentError('Message is too long');
    }
    final key = _shelfKey;
    final shelf = _shelf;
    final id = _service.newItemId(_cid);
    final ct = await _crypto.encryptContent(
      key,
      id,
      VaultMessageContent(clean).toJson(),
    );
    cache.putText(id, clean);
    await _service.addMessage(
      cid: _cid,
      itemId: id,
      senderId: _uid,
      shelf: shelf,
      ct: ct,
      policy: policy,
      now: _now(),
    );
  }

  /// Encrypts and uploads a prepared photo to the open shelf.
  Future<void> addPhoto(
    PreparedPhoto photo,
    VaultPolicy policy, {
    void Function(double progress)? onProgress,
  }) async {
    final key = _shelfKey;
    final shelf = _shelf;
    final id = _service.newItemId(_cid);
    final photoPath = _service.newFilePath(_cid);
    final thumbPath = _service.newFilePath(_cid);
    final content = VaultPhotoContent(
      width: photo.width,
      height: photo.height,
      photoPath: photoPath,
      thumbPath: thumbPath,
      bytes: photo.photo.length,
    );
    final ct = await _crypto.encryptContent(key, id, content.toJson());
    final sealedPhoto = await _crypto.encryptBlob(
      key,
      id,
      'photo',
      photo.photo,
    );
    final sealedThumb = await _crypto.encryptBlob(
      key,
      id,
      'thumb',
      photo.thumb,
    );
    cache
      ..putThumb(id, Uint8List.fromList(photo.thumb))
      ..putPhotoInfo(id, content);
    await _service.addPhoto(
      cid: _cid,
      itemId: id,
      senderId: _uid,
      shelf: shelf,
      ct: ct,
      policy: policy,
      photoPath: photoPath,
      photo: sealedPhoto,
      thumbPath: thumbPath,
      thumb: sealedThumb,
      onProgress: onProgress,
      now: _now(),
    );
  }

  void _checkShelf(VaultItem item) {
    if (item.shelf != state.shelf) throw StateError('Not on this shelf');
  }

  /// A message's text.
  Future<String> messageText(VaultItem item) async {
    _checkShelf(item);
    final cached = cache.text(item.id);
    if (cached != null) return cached;
    final json = await _crypto.decryptContent(_shelfKey, item.id, item.ct);
    final text = VaultMessageContent.fromJson(json).text;
    if (state.unlocked) cache.putText(item.id, text);
    return text;
  }

  /// A photo's details (size).
  Future<VaultPhotoContent> photoInfo(VaultItem item) async {
    _checkShelf(item);
    final cached = cache.photoInfo(item.id);
    if (cached != null) return cached;
    final json = await _crypto.decryptContent(_shelfKey, item.id, item.ct);
    final info = VaultPhotoContent.fromJson(json);
    if (state.unlocked) cache.putPhotoInfo(item.id, info);
    return info;
  }

  /// A photo's thumbnail, decrypted into memory.
  Future<MemoryImage> thumbnail(VaultItem item) async {
    _checkShelf(item);
    var bytes = cache.thumb(item.id);
    if (bytes == null) {
      final path = item.thumbPath;
      if (path == null) throw StateError('No thumbnail');
      final key = _shelfKey;
      final sealed = await _service.download(path);
      bytes = await _crypto.decryptBlob(key, item.id, 'thumb', sealed);
      if (!state.unlocked) throw StateError('Vault is locked');
      cache.putThumb(item.id, bytes);
    }
    return cache.image('t:${item.id}', bytes);
  }

  /// The full photo, decrypted into memory.
  Future<MemoryImage> photo(VaultItem item) async {
    _checkShelf(item);
    var bytes = cache.photo(item.id);
    if (bytes == null) {
      final path = item.photoPath;
      if (path == null) throw StateError('No photo');
      final key = _shelfKey;
      final sealed = await _service.download(path);
      bytes = await _crypto.decryptBlob(key, item.id, 'photo', sealed);
      if (!state.unlocked) throw StateError('Vault is locked');
      cache.putPhoto(item.id, bytes);
    }
    return cache.image('p:${item.id}', bytes);
  }

  /// Whether this user is about to see a view-once item for the only time.
  bool isViewOnceForMe(VaultItem item) =>
      item.policy == VaultPolicy.once && item.senderId != _uid;

  /// Records that this user is viewing [item].
  Future<void> markViewed(VaultItem item) async {
    try {
      await _service.markViewed(cid: _cid, itemId: item.id, uid: _uid);
    } catch (e) {
      debugPrint('vault: mark viewed failed: $e');
    }
  }

  /// After the only view of a view-once item closes: deletes it.
  Future<void> finishViewOnce(VaultItem item) async {
    cache.evict(item.id);
    try {
      await _service.deleteItem(_cid, item);
    } catch (e) {
      debugPrint('vault: view-once delete failed: $e');
    }
  }

  /// Deletes an item for both partners.
  Future<void> deleteItem(VaultItem item) async {
    cache.evict(item.id);
    await _service.deleteItem(_cid, item);
  }

  /// Dismisses an alert.
  Future<void> dismissEvent(VaultEvent event) =>
      _service.dismissEvent(_cid, event.id);

  /// "Delete vault for both": deletes everything and locks. Can't be undone.
  Future<void> wipe() async {
    if (!isUnlocked) throw StateError('Vault is locked');
    final name = await deviceName();
    if (_decoy) {
      // Only the decoy shelf goes; the real vault is never exposed or
      // destroyed from a decoy session.
      await _service.wipeShelf(
        cid: _cid,
        shelf: _shelf,
        uid: _uid,
        deviceName: name,
      );
    } else {
      await _service.wipe(cid: _cid, uid: _uid, deviceName: name);
    }
    if (ref.mounted) lock();
  }
}

/// The vault session for the signed-in user on this phone. It lives while a
/// vault screen is open; closing them all forgets the keys.
final vaultSessionProvider =
    NotifierProvider.autoDispose<VaultSession, VaultSessionState>(
      VaultSession.new,
    );
