import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import 'package:couple_app/features/together/models/love_note.dart';

/// Thrown when a sealed note cannot be opened yet.
class NoteSealedException implements Exception {
  NoteSealedException(this.deliverAt);
  final DateTime deliverAt;
}

/// Love notes at `couples/{coupleId}/notes/{noteId}` (the envelope), with
/// the words at `.../notes/{noteId}/sealed/content`.
///
/// Splitting them lets the partner see that a note is coming ("arrives in
/// 3 days") while the rules keep its contents unreadable until then. Voice
/// letters are stored at `couples/{coupleId}/notes/{noteId}.m4a`; the app
/// only reveals their link from inside the sealed content.
class LoveNoteService {
  LoveNoteService({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storageOverride = storage;

  final FirebaseFirestore _db;
  final FirebaseStorage? _storageOverride;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  static final _uuid = Uuid();

  CollectionReference<Map<String, dynamic>> _notes(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('notes');

  DocumentReference<Map<String, dynamic>> _content(
    String coupleId,
    String noteId,
  ) => _notes(coupleId).doc(noteId).collection('sealed').doc('content');

  /// Every envelope in the couple, newest delivery first. Sent and received
  /// are separated by the caller.
  Stream<List<LoveNote>> watchNotes(String coupleId) {
    return _notes(coupleId).snapshots().map((snap) {
      final list = snap.docs.map(LoveNote.fromDoc).toList()
        ..sort((a, b) => b.deliverAt.compareTo(a.deliverAt));
      return list;
    });
  }

  Future<void> send({
    required String coupleId,
    required String senderId,
    required String recipientId,
    required NoteKind kind,
    required String title,
    required String body,
    required DateTime deliverAt,
    OpenWhen? openWhen,
    File? voiceFile,
    Duration? voiceDuration,
  }) async {
    final noteRef = _notes(coupleId).doc();

    String? voiceUrl;
    if (voiceFile != null) {
      final ref = _storage.ref(
        'couples/$coupleId/notes/${noteRef.id}_${_uuid.v4()}.m4a',
      );
      // Storage rules let only the sender read this object directly; the
      // recipient plays it through the link inside the sealed content.
      await ref.putFile(
        voiceFile,
        SettableMetadata(
          contentType: 'audio/mp4',
          customMetadata: {'senderId': senderId},
        ),
      );
      voiceUrl = await ref.getDownloadURL();
    }

    final deliver = Timestamp.fromDate(deliverAt);
    final batch = _db.batch();
    batch.set(noteRef, {
      'senderId': senderId,
      'recipientId': recipientId,
      'kind': kind == NoteKind.openWhen ? 'openWhen' : 'letter',
      'openWhen': openWhen?.id,
      'title': title.trim(),
      'deliverAt': deliver,
      'createdAt': FieldValue.serverTimestamp(),
      'openedAt': null,
      'hasVoice': voiceUrl != null,
      'voiceDurationMs': voiceDuration?.inMilliseconds,
    });
    batch.set(_content(coupleId, noteRef.id), {
      'body': body.trim(),
      'voiceUrl': voiceUrl,
      // Copied here so the rules can check delivery without another read.
      'deliverAt': deliver,
      'senderId': senderId,
      'recipientId': recipientId,
    });
    await batch.commit();
  }

  /// Reads the sealed words. Throws [NoteSealedException] if the note has
  /// not been delivered yet.
  Future<LoveNoteContent> open({
    required String coupleId,
    required LoveNote note,
  }) async {
    try {
      final snap = await _content(coupleId, note.id).get();
      final data = snap.data() ?? <String, dynamic>{};
      return LoveNoteContent(
        body: (data['body'] as String?) ?? '',
        voiceUrl: data['voiceUrl'] as String?,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw NoteSealedException(note.deliverAt);
      }
      rethrow;
    }
  }

  /// The recipient marks a note opened the first time they read it.
  Future<void> markOpened({required String coupleId, required LoveNote note}) {
    if (note.isOpened) return Future.value();
    return _notes(
      coupleId,
    ).doc(note.id).update({'openedAt': FieldValue.serverTimestamp()});
  }

  /// The sender can take a note back (e.g. before it arrives).
  Future<void> unsend({
    required String coupleId,
    required LoveNote note,
  }) async {
    String? voiceUrl;
    try {
      voiceUrl =
          (await _content(coupleId, note.id).get()).data()?['voiceUrl']
              as String?;
    } catch (_) {}

    final batch = _db.batch()
      ..delete(_content(coupleId, note.id))
      ..delete(_notes(coupleId).doc(note.id));
    await batch.commit();

    if (voiceUrl != null) {
      try {
        await _storage.refFromURL(voiceUrl).delete();
      } catch (_) {}
    }
  }
}
