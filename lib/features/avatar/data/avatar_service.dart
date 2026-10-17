import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';

/// Saves avatars on profiles (`users/{uid}.avatar`, `.avatarAsPhoto`).
class AvatarService {
  AvatarService({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;
  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;

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
