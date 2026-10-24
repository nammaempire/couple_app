import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';

/// Saves avatars on profiles (`users/{uid}.avatar`, `.avatarAsPhoto`).
class AvatarService {
  AvatarService({Db? db}) : _dbOverride = db;

  final Db? _dbOverride;
  Db get _db => _dbOverride ?? Db.instance;

  Future<void> save({
    required String uid,
    required AvatarConfig avatar,
    required bool asProfilePicture,
  }) {
    return _db.collection('users').doc(uid).set({
      'avatar': avatar.toMap(),
      'avatarAsPhoto': asProfilePicture,
    }, SetOptions(merge: true));
  }

  Future<void> setAsProfilePicture({required String uid, required bool value}) {
    return _db.collection('users').doc(uid).set({
      'avatarAsPhoto': value,
    }, SetOptions(merge: true));
  }
}
