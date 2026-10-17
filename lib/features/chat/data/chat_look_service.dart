import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:couple_app/features/chat/models/chat_look.dart';

/// Reads and saves how the chat looks.
///
/// The couple's shared look is `couples/{coupleId}/settings/chatLook`. Each
/// person's choice of shared or personal, and their personal look, live on
/// their profile (`users/{uid}.chatLookMode` and `.chatLook`). Uploaded
/// background photos go to `couples/{coupleId}/backgrounds/` (shared) or
/// `users/{uid}/backgrounds/` (personal, only they can read it).
class ChatLookService {
  ChatLookService({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestoreOverride = firestore,
      _storageOverride = storage;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseStorage? _storageOverride;

  FirebaseFirestore get _db => _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  static const _uuid = Uuid();

  DocumentReference<Map<String, dynamic>> _sharedDoc(String coupleId) => _db
      .collection('couples')
      .doc(coupleId)
      .collection('settings')
      .doc('chatLook');

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  Stream<SharedChatLook> watchShared(String coupleId) =>
      _sharedDoc(coupleId).snapshots().map(SharedChatLook.fromDoc);

  Stream<PersonalChatLook> watchPersonal(String uid) => _userDoc(
    uid,
  ).snapshots().map((doc) => PersonalChatLook.fromProfile(doc.data()));

  /// Sets the look both partners see (unless one chose their own).
  Future<void> saveShared({
    required String coupleId,
    required String uid,
    required ChatLook look,
  }) {
    return _sharedDoc(coupleId).set({
      ...look.toMap(),
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Switches this person to their own look ([look]) or back to the
  /// shared one. The personal look is kept when switching back, so it is
  /// there next time.
  Future<void> savePersonal({
    required String uid,
    required ChatLookMode mode,
    ChatLook? look,
  }) {
    return _userDoc(uid).set({
      'chatLookMode': mode.id,
      'chatLook': ?look?.toMap(),
    }, SetOptions(merge: true));
  }

  /// Uploads a background photo and returns its URL and Storage path.
  /// [personal] backgrounds are private to [uid]; shared ones are readable
  /// by both partners.
  Future<({String url, String path})> uploadBackground({
    required File file,
    required String coupleId,
    required String uid,
    required bool personal,
  }) async {
    final name = '${_uuid.v4()}.jpg';
    final path = personal
        ? 'users/$uid/backgrounds/$name'
        : 'couples/$coupleId/backgrounds/$name';
    final ref = _storage.ref(path);
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return (url: await ref.getDownloadURL(), path: path);
  }

  /// Removes an uploaded background that is no longer used. Failures are
  /// ignored: a leftover file only costs storage.
  Future<void> deleteUploaded(String? path) async {
    if (path == null) return;
    try {
      await _storage.ref(path).delete();
    } catch (_) {}
  }
}
