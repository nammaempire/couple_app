import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'package:couple_app/core/services/storage_service.dart';
import 'package:couple_app/features/chat/models/message.dart';

/// Thrown when a message cannot be sent for a reason worth explaining.
class ChatException implements Exception {
  ChatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads and writes messages in `couples/{coupleId}/messages`.
class ChatService {
  ChatService({FirebaseFirestore? firestore, StorageService? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? StorageService();

  final FirebaseFirestore _db;
  final StorageService _storage;

  /// Matches the Storage rule for chat videos.
  static const maxVideoBytes = 100 * 1024 * 1024;

  CollectionReference<Map<String, dynamic>> _messages(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('messages');

  /// Newest messages first, capped at [limit]. Raise the limit to page back.
  ///
  /// Also says whether the result came only from the on-device cache. When the limit grows, Firestore first answers from
  /// cache with the messages it already has, which must not be mistaken for
  /// "there are no older messages".
  Stream<({List<Message> messages, bool fromCache})> watchMessagePage(
    String coupleId, {
    int limit = 100,
  }) {
    return _messages(coupleId)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snap) => (
            messages: snap.docs.map(Message.fromDoc).toList(),
            fromCache: snap.metadata.isFromCache,
          ),
        );
  }

  Future<void> _send(String coupleId, Message message) async {
    await _messages(coupleId).add(message.toMap());
    await _touchCouple(coupleId, preview: message.previewText);
  }

  Future<void> sendText({
    required String coupleId,
    required String senderId,
    required String text,
    ReplyPreview? replyTo,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _send(
      coupleId,
      Message(
        id: '',
        senderId: senderId,
        type: MessageType.text,
        text: trimmed,
        replyTo: replyTo,
      ),
    );
  }

  /// Longest quote a sticker may carry, typed or from the bank.
  static const maxStickerQuoteLength = 90;

  /// Trims [quote] and caps it at [maxStickerQuoteLength] user-perceived
  /// characters (grapheme clusters), so an emoji is never cut in half.
  static String clampStickerQuote(String quote) {
    final text = quote.trim();
    final chars = text.characters;
    if (chars.length <= maxStickerQuoteLength) return text;
    return chars.take(maxStickerQuoteLength).toString().trimRight();
  }

  /// Writes a couple-avatar sticker: scene [stickerId] from [category],
  /// with [quote] as the message text (trimmed and capped).
  Future<void> sendSticker({
    required String coupleId,
    required String senderId,
    required String stickerId,
    required String category,
    required String quote,
    ReplyPreview? replyTo,
  }) async {
    final text = clampStickerQuote(quote);

    await _send(
      coupleId,
      Message(
        id: '',
        senderId: senderId,
        type: MessageType.sticker,
        text: text,
        stickerId: stickerId,
        stickerCategory: category,
        replyTo: replyTo,
      ),
    );
  }

  /// Uploads [file] then writes the image message.
  Future<void> sendImage({
    required String coupleId,
    required String senderId,
    required File file,
    void Function(double progress)? onProgress,
    ReplyPreview? replyTo,
  }) async {
    final aspectRatio = await _aspectRatioOf(await file.readAsBytes());
    final url = await _storage.uploadChatPhoto(
      coupleId: coupleId,
      file: file,
      onProgress: onProgress,
    );

    await _send(
      coupleId,
      Message(
        id: '',
        senderId: senderId,
        type: MessageType.image,
        imageUrl: url,
        imageAspectRatio: aspectRatio,
        replyTo: replyTo,
      ),
    );
  }

  /// Uploads a video plus a thumbnail, then writes the video message.
  Future<void> sendVideo({
    required String coupleId,
    required String senderId,
    required File file,
    Duration? duration,
    void Function(double progress)? onProgress,
    ReplyPreview? replyTo,
  }) async {
    if (await file.length() > maxVideoBytes) {
      throw ChatException('That video is too large. The limit is 100 MB.');
    }

    // The thumbnail is best effort: a video without one still plays.
    String? thumbUrl;
    double? aspectRatio;
    try {
      final jpeg = await FcNativeVideoThumbnail().saveThumbnailToBytes(
        srcFile: file.path,
        width: 640,
        height: 640,
        format: 'jpeg',
        quality: 75,
      );
      if (jpeg != null) {
        aspectRatio = await _aspectRatioOf(jpeg);
        thumbUrl = await _storage.uploadThumbnail(
          coupleId: coupleId,
          jpeg: jpeg,
        );
      }
    } catch (_) {}

    final url = await _storage.uploadChatVideo(
      coupleId: coupleId,
      file: file,
      onProgress: onProgress,
    );

    await _send(
      coupleId,
      Message(
        id: '',
        senderId: senderId,
        type: MessageType.video,
        mediaUrl: url,
        imageUrl: thumbUrl,
        imageAspectRatio: aspectRatio,
        durationMs: duration?.inMilliseconds,
        replyTo: replyTo,
      ),
    );
  }

  Future<void> sendVoice({
    required String coupleId,
    required String senderId,
    required File file,
    required Duration duration,
    ReplyPreview? replyTo,
  }) async {
    final url = await _storage.uploadVoice(coupleId: coupleId, file: file);
    await _send(
      coupleId,
      Message(
        id: '',
        senderId: senderId,
        type: MessageType.voice,
        mediaUrl: url,
        durationMs: duration.inMilliseconds,
        replyTo: replyTo,
      ),
    );
  }

  /// Records how a call went as a message in the conversation. Written by
  /// the caller, since the rules require `senderId` to be the writer.
  Future<void> logCall({
    required String coupleId,
    required String callerId,
    required bool video,
    required CallOutcome outcome,
    Duration? talkTime,
  }) async {
    await _send(
      coupleId,
      Message(
        id: '',
        senderId: callerId,
        type: MessageType.call,
        isVideoCall: video,
        callOutcome: outcome,
        durationMs: outcome == CallOutcome.completed
            ? talkTime?.inMilliseconds
            : null,
        // A call record has nothing to "read"; mark it seen so it never
        // counts as unread.
        seen: true,
      ),
    );
  }

  /// Marks the partner's unread messages as seen. Two equality filters
  /// need no composite index.
  Future<void> markSeen({
    required String coupleId,
    required String partnerId,
  }) async {
    final unread = await _messages(coupleId)
        .where('senderId', isEqualTo: partnerId)
        .where('seen', isEqualTo: false)
        .limit(200)
        .get();
    if (unread.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'seen': true});
    }
    await batch.commit();
  }

  /// Adds [emoji] as this user's reaction, or removes it if it is already
  /// their reaction — so tapping the same emoji twice toggles it off.
  Future<void> toggleReaction({
    required String coupleId,
    required Message message,
    required String uid,
    required String emoji,
  }) {
    final alreadySet = message.reactions[uid] == emoji;
    return _messages(coupleId).doc(message.id).update({
      'reactions.$uid': alreadySet ? FieldValue.delete() : emoji,
    });
  }

  Future<void> setPinned({
    required String coupleId,
    required Message message,
    required bool pinned,
  }) {
    return _messages(coupleId).doc(message.id).update({
      'pinned': pinned,
      'pinnedAt': pinned ? FieldValue.serverTimestamp() : null,
    });
  }

  /// Pinned messages, most recently pinned first. Sorted here rather than in
  /// the query, so no composite index is needed.
  Stream<List<Message>> watchPinned(String coupleId) {
    return _messages(coupleId).where('pinned', isEqualTo: true).snapshots().map(
      (snap) {
        final list = snap.docs.map(Message.fromDoc).toList();
        list.sort(
          (a, b) =>
              (b.pinnedAt ?? DateTime(0)).compareTo(a.pinnedAt ?? DateTime(0)),
        );
        return list;
      },
    );
  }

  /// How far back search (and jumping to a result) reaches.
  static const searchWindow = 1000;

  /// Recent messages for searching. Firestore has no full-text search, so
  /// matching happens on the device over the latest [limit] messages.
  Future<List<Message>> fetchRecent(
    String coupleId, {
    int limit = searchWindow,
  }) async {
    final snap = await _messages(
      coupleId,
    ).orderBy('sentAt', descending: true).limit(limit).get();
    return snap.docs.map(Message.fromDoc).toList();
  }

  /// Every photo and video in the conversation, newest first.
  Future<List<Message>> fetchMedia(String coupleId) async {
    final snap = await _messages(
      coupleId,
    ).where('type', whereIn: ['image', 'video']).limit(1000).get();
    final list = snap.docs.map(Message.fromDoc).toList();
    list.sort(
      (a, b) => (b.sentAt ?? DateTime(0)).compareTo(a.sentAt ?? DateTime(0)),
    );
    return list;
  }

  Future<void> deleteMessage({
    required String coupleId,
    required Message message,
  }) async {
    await _messages(coupleId).doc(message.id).delete();
    for (final url in [message.imageUrl, message.mediaUrl]) {
      if (url == null) continue;
      try {
        await _storage.deleteByUrl(url);
      } catch (_) {
        // The document is gone; a leftover file is not worth failing over.
      }
    }
  }

  Future<void> _touchCouple(String coupleId, {required String preview}) {
    return _db.collection('couples').doc(coupleId).set({
      'lastMessagePreview': preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<double?> _aspectRatioOf(Uint8List bytes) async {
    try {
      final descriptor = await ui.ImageDescriptor.encoded(
        await ui.ImmutableBuffer.fromUint8List(bytes),
      );
      final ratio = descriptor.width / descriptor.height;
      descriptor.dispose();
      return ratio;
    } catch (_) {
      return null;
    }
  }
}
