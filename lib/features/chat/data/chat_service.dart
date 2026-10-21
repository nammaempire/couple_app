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

  /// Deletes per batch when clearing the chat for both; under Firestore's
  /// 500-write batch limit.
  static const clearBatchSize = 400;

  /// The part of a newest-first page of messages that "clear chat" has not
  /// hidden, and whether the page reached the clear point. Once it has,
  /// everything older is hidden too, so there is nothing more to page in.
  ///
  /// This is done on the device rather than with a `sentAt >` query filter:
  /// Firestore leaves a message whose server time is still pending out of
  /// range filters, so my own just-sent (or offline) messages would vanish
  /// until the server confirmed them.
  static ({List<Message> visible, bool reachedClear}) visiblePart(
    List<Message> page,
    DateTime? clearedAt,
  ) {
    if (clearedAt == null) return (visible: page, reachedClear: false);
    final visible = page.where((m) => !m.isClearedBy(clearedAt)).toList();
    return (visible: visible, reachedClear: visible.length < page.length);
  }

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
  ///
  /// Messages hidden by "clear chat for me" ([clearedAt]) were never read,
  /// so they are left alone; filtering them here rather than in the query
  /// avoids a composite index.
  Future<void> markSeen({
    required String coupleId,
    required String partnerId,
    DateTime? clearedAt,
  }) async {
    final unread = await _messages(coupleId)
        .where('senderId', isEqualTo: partnerId)
        .where('seen', isEqualTo: false)
        .limit(200)
        .get();
    final docs = unread.docs
        .where((doc) => !Message.fromDoc(doc).isClearedBy(clearedAt))
        .toList();
    if (docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in docs) {
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
  ///
  /// Only messages sent after [clearedAt] are fetched. The range filter is
  /// on the field the query is ordered by, so it needs no extra index.
  Future<List<Message>> fetchRecent(
    String coupleId, {
    int limit = searchWindow,
    DateTime? clearedAt,
  }) async {
    Query<Map<String, dynamic>> query = _messages(coupleId);
    if (clearedAt != null) {
      query = query.where(
        'sentAt',
        isGreaterThan: Timestamp.fromDate(clearedAt),
      );
    }
    final snap = await query
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(Message.fromDoc).toList();
  }

  /// Every photo and video in the conversation sent after [clearedAt],
  /// newest first. The cut-off is applied here: with the `type` filter it
  /// would need a composite index.
  Future<List<Message>> fetchMedia(
    String coupleId, {
    DateTime? clearedAt,
  }) async {
    final snap = await _messages(
      coupleId,
    ).where('type', whereIn: ['image', 'video']).limit(1000).get();
    final list = snap.docs
        .map(Message.fromDoc)
        .where((m) => !m.isClearedBy(clearedAt))
        .toList();
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
    await _deleteMedia(message);
  }

  /// Deletes a message's files: the photo, or the video and its thumbnail,
  /// or the voice recording.
  Future<void> _deleteMedia(Message message) async {
    for (final url in [message.imageUrl, message.mediaUrl]) {
      if (url == null) continue;
      try {
        await _storage.deleteByUrl(url);
      } catch (_) {
        // Already gone, or a leftover file not worth failing over.
      }
    }
  }

  // ---- Clearing the chat ---------------------------------------------------

  /// "Clear chat for me": hides every message up to now on [uid]'s account
  /// only. The partner keeps their history, and the files stay in Storage
  /// because they can still see them.
  Future<void> clearForMe({required String uid}) {
    return _db.collection('users').doc(uid).update({
      'chatClearedAt': FieldValue.serverTimestamp(),
    });
  }

  /// "Clear chat for both": permanently deletes the conversation, with its
  /// photos, videos and voice messages, then posts a system line.
  ///
  /// 1. Stamps the couple with `chatClearedAt` (server time) and
  ///    `chatClearedBy`, and drops the last-message preview. The rules then
  ///    let either partner delete anything sent up to that moment, and both
  ///    apps hide it straight away.
  /// 2. Deletes those messages in batches of [clearBatchSize], each
  ///    message's files first, so a retry can still find what to delete.
  /// 3. Posts a [MessageType.chatCleared] line from [senderId].
  ///
  /// [onProgress] gets the running count of deleted messages. If anything
  /// fails, running it again finishes the job: it re-stamps the couple and
  /// deletes everything up to the new time.
  Future<void> clearForBoth({
    required String coupleId,
    required String senderId,
    required String senderName,
    void Function(int deleted)? onProgress,
  }) async {
    final coupleRef = _db.collection('couples').doc(coupleId);
    await coupleRef.update({
      'chatClearedAt': FieldValue.serverTimestamp(),
      'chatClearedBy': senderId,
      'lastMessagePreview': FieldValue.delete(),
      'lastMessageAt': FieldValue.delete(),
    });

    // Read the stamp back: the delete rule compares against the stored
    // server time, not this phone's clock.
    final stamped = (await coupleRef.get()).data()?['chatClearedAt'];
    if (stamped is! Timestamp) {
      throw ChatException('Could not clear the chat. Try again.');
    }

    var deleted = 0;
    onProgress?.call(deleted);
    while (true) {
      final page = await _messages(coupleId)
          .where('sentAt', isLessThanOrEqualTo: stamped)
          .limit(clearBatchSize)
          .get();
      if (page.docs.isEmpty) break;

      final messages = page.docs.map(Message.fromDoc).toList();
      // A few files at a time, rather than one by one or all at once.
      for (var i = 0; i < messages.length; i += 8) {
        await Future.wait(messages.skip(i).take(8).map(_deleteMedia));
      }

      final batch = _db.batch();
      for (final doc in page.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += page.docs.length;
      onProgress?.call(deleted);
    }

    await _sendSystem(
      coupleId,
      senderId: senderId,
      type: MessageType.chatCleared,
      text: '🧹 $senderName cleared the chat',
    );
  }

  // ---- Screenshots ---------------------------------------------------------

  /// Tells the partner that [senderId] took a screenshot of [subject].
  Future<void> sendScreenshotAlert({
    required String coupleId,
    required String senderId,
    required String senderName,
    ScreenshotSubject subject = ScreenshotSubject.chat,
  }) {
    return _sendSystem(
      coupleId,
      senderId: senderId,
      type: MessageType.screenshot,
      text: switch (subject) {
        ScreenshotSubject.chat => '📸 $senderName took a screenshot',
        ScreenshotSubject.photo =>
          '📸 $senderName took a screenshot of a photo',
        ScreenshotSubject.video =>
          '📸 $senderName took a screenshot of a video',
      },
      screenshotOf: subject,
    );
  }

  /// Turns the shared "block screenshots of our chat" switch on or off,
  /// and posts a line saying who did.
  Future<void> setScreenshotBlocking({
    required String coupleId,
    required String senderId,
    required String senderName,
    required bool blocked,
  }) async {
    await _db.collection('couples').doc(coupleId).update({
      'blockScreenshots': blocked,
    });
    await _sendSystem(
      coupleId,
      senderId: senderId,
      type: MessageType.screenshotBlock,
      text:
          '🔒 $senderName turned ${blocked ? 'on' : 'off'} screenshot '
          'blocking',
      screenshotsBlocked: blocked,
    );
  }

  /// Writes a system line. It is marked seen so it never counts as unread.
  Future<void> _sendSystem(
    String coupleId, {
    required String senderId,
    required MessageType type,
    required String text,
    ScreenshotSubject screenshotOf = ScreenshotSubject.chat,
    bool screenshotsBlocked = false,
  }) {
    final chars = text.characters;
    return _send(
      coupleId,
      Message(
        id: '',
        senderId: senderId,
        type: type,
        text: chars.length <= Message.maxSystemTextLength
            ? text
            : chars.take(Message.maxSystemTextLength).toString(),
        seen: true,
        screenshotOf: screenshotOf,
        screenshotsBlocked: screenshotsBlocked,
      ),
    );
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
