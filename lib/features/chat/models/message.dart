import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:couple_app/core/utils/duration_format.dart';

enum MessageType {
  text,
  image,
  video,
  voice,

  /// A record of a voice or video call, written when the call ends.
  call,

  /// A couple avatar sticker. [Message.text] holds its quote, so older app
  /// versions (which show unknown types as text) still show the words.
  sticker,

  /// System line: the sender cleared the whole chat for both partners.
  chatCleared,

  /// System line: the sender took a screenshot of the chat, or of a photo
  /// or video opened from it ([Message.screenshotOf]).
  screenshot,

  /// System line: the sender turned screenshot blocking on or off
  /// ([Message.screenshotsBlocked]).
  screenshotBlock;

  /// Centred notices rather than bubbles. They carry a short [Message.text]
  /// (so older app versions, which show unknown types as text, still say
  /// something sensible) and no media, and they can't be replied to,
  /// reacted to or pinned.
  bool get isSystem =>
      this == chatCleared || this == screenshot || this == screenshotBlock;

  static MessageType fromId(String? id) {
    for (final type in values) {
      if (type.name == id) return type;
    }
    return MessageType.text;
  }
}

/// What was on screen when a screenshot was taken.
enum ScreenshotSubject {
  chat,
  photo,
  video;

  static ScreenshotSubject fromId(String? id) {
    for (final subject in values) {
      if (subject.name == id) return subject;
    }
    return ScreenshotSubject.chat;
  }
}

/// How a logged call ended.
enum CallOutcome {
  /// Connected; [Message.durationMs] holds the talk time.
  completed,

  /// Rang out, or the caller hung up before an answer.
  missed,

  /// The callee declined.
  declined;

  static CallOutcome fromId(String? id) {
    for (final outcome in values) {
      if (outcome.name == id) return outcome;
    }
    return CallOutcome.missed;
  }
}

/// The couple's reaction set, from the product spec.
enum CoupleReaction {
  love('❤️', 'Love'),
  missYou('🥺', 'Miss you'),
  hug('🤗', 'Hug'),
  kiss('😘', 'Kiss'),
  laugh('😂', 'Laugh');

  const CoupleReaction(this.emoji, this.label);
  final String emoji;
  final String label;
}

/// A snapshot of the message being replied to, stored on the reply so the
/// quote still shows if the original is later deleted.
class ReplyPreview {
  final String messageId;
  final String senderId;
  final MessageType type;
  final String text;

  /// For a quoted sticker: its scene and category, so the quote can show a
  /// small picture of it.
  final String? stickerId;
  final String? stickerCategory;

  const ReplyPreview({
    required this.messageId,
    required this.senderId,
    required this.type,
    required this.text,
    this.stickerId,
    this.stickerCategory,
  });

  factory ReplyPreview.of(Message message) => ReplyPreview(
    messageId: message.id,
    senderId: message.senderId,
    type: message.type,
    text: message.previewText,
    stickerId: message.stickerId,
    stickerCategory: message.stickerCategory,
  );

  static ReplyPreview? fromMap(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final sticker = Message._stickerFields(raw['sticker']);
    return ReplyPreview(
      messageId: (raw['messageId'] as String?) ?? '',
      senderId: (raw['senderId'] as String?) ?? '',
      type: MessageType.fromId(raw['type'] as String?),
      text: (raw['text'] as String?) ?? '',
      stickerId: sticker.id,
      stickerCategory: sticker.category,
    );
  }

  Map<String, dynamic> toMap() => {
    'messageId': messageId,
    'senderId': senderId,
    'type': type.name,
    'text': text,
    if (stickerId != null)
      'sticker': {'id': stickerId, 'category': stickerCategory},
  };
}

/// A single chat message inside a couple's conversation.
class Message {
  final String id;
  final String senderId;
  final MessageType type;

  /// Text body for [MessageType.text]; empty for media.
  final String text;

  /// Download URL of the photo, or of a video's thumbnail.
  final String? imageUrl;

  /// Aspect ratio (width / height) so bubbles can reserve space before load.
  final double? imageAspectRatio;

  /// Download URL of the video or voice recording.
  final String? mediaUrl;

  /// Length of a video, voice message or connected call.
  final int? durationMs;

  final DateTime? sentAt;
  final bool seen;

  /// Emoji reactions keyed by the uid that left them. One each.
  final Map<String, String> reactions;

  final ReplyPreview? replyTo;

  final bool pinned;
  final DateTime? pinnedAt;

  /// For [MessageType.call]: whether it was a video call, and how it ended.
  final bool isVideoCall;
  final CallOutcome? callOutcome;

  /// For [MessageType.sticker]: the scene id and category id, stored as
  /// `sticker: {id, category}`. The quote is in [text].
  final String? stickerId;
  final String? stickerCategory;

  /// For [MessageType.screenshot]: what was on screen.
  final ScreenshotSubject screenshotOf;

  /// For [MessageType.screenshotBlock]: whether blocking was turned on.
  final bool screenshotsBlocked;

  /// Longest text a system message may carry.
  static const maxSystemTextLength = 200;

  const Message({
    required this.id,
    required this.senderId,
    required this.type,
    this.text = '',
    this.imageUrl,
    this.imageAspectRatio,
    this.mediaUrl,
    this.durationMs,
    this.sentAt,
    this.seen = false,
    this.reactions = const {},
    this.replyTo,
    this.pinned = false,
    this.pinnedAt,
    this.isVideoCall = false,
    this.callOutcome,
    this.stickerId,
    this.stickerCategory,
    this.screenshotOf = ScreenshotSubject.chat,
    this.screenshotsBlocked = false,
  });

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  bool get isMedia => type == MessageType.image || type == MessageType.video;

  bool get isSystem => type.isSystem;

  /// Whether "clear chat" has hidden this message: it was sent at or before
  /// [clearedAt]. Messages still waiting for their server time are newer
  /// than any clear, so they always show.
  bool isClearedBy(DateTime? clearedAt) {
    final sent = sentAt;
    return clearedAt != null && sent != null && !sent.isAfter(clearedAt);
  }

  /// Distinct emoji on this message, in a stable order.
  List<String> get reactionEmoji {
    final alreadyAdded = <String>{};
    final ordered = <String>[];
    for (final emoji in reactions.values) {
      if (alreadyAdded.add(emoji)) ordered.add(emoji);
    }
    return ordered;
  }

  /// One-line summary for reply quotes, pins, search and the chat preview.
  String get previewText {
    switch (type) {
      case MessageType.text:
        return text;
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.voice:
        final d = duration;
        return d == null
            ? '🎤 Voice message'
            : '🎤 Voice message (${formatDuration(d)})';
      case MessageType.call:
        final kind = isVideoCall ? 'video call' : 'voice call';
        return switch (callOutcome ?? CallOutcome.missed) {
          CallOutcome.completed => '📞 ${_capitalise(kind)}',
          CallOutcome.missed => '📞 Missed $kind',
          CallOutcome.declined => '📞 Declined $kind',
        };
      case MessageType.sticker:
        return text.trim().isEmpty ? 'Sticker' : '💞 ${text.trim()}';
      case MessageType.chatCleared:
        return text.isEmpty ? '🧹 Chat cleared' : text;
      case MessageType.screenshot:
        return text.isEmpty ? '📸 Screenshot taken' : text;
      case MessageType.screenshotBlock:
        return text.isEmpty
            ? '🔒 Screenshot blocking turned ${screenshotsBlocked ? 'on' : 'off'}'
            : text;
    }
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Message.fromMap(doc.id, doc.data() ?? <String, dynamic>{});

  /// Parses stored fields; [id] is the document id.
  factory Message.fromMap(String id, Map<String, dynamic> data) {
    final sticker = _stickerFields(data['sticker']);
    return Message(
      id: id,
      senderId: (data['senderId'] as String?) ?? '',
      type: MessageType.fromId(data['type'] as String?),
      text: (data['text'] as String?) ?? '',
      imageUrl: data['imageUrl'] as String?,
      imageAspectRatio: (data['imageAspectRatio'] as num?)?.toDouble(),
      mediaUrl: data['mediaUrl'] as String?,
      durationMs: (data['durationMs'] as num?)?.toInt(),
      sentAt: data['sentAt'] is Timestamp
          ? (data['sentAt'] as Timestamp).toDate()
          : null,
      seen: (data['seen'] as bool?) ?? false,
      reactions: Map<String, String>.from(
        (data['reactions'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
      replyTo: ReplyPreview.fromMap(data['replyTo']),
      pinned: (data['pinned'] as bool?) ?? false,
      pinnedAt: data['pinnedAt'] is Timestamp
          ? (data['pinnedAt'] as Timestamp).toDate()
          : null,
      isVideoCall: (data['callType'] as String?) == 'video',
      callOutcome: data['callOutcome'] == null
          ? null
          : CallOutcome.fromId(data['callOutcome'] as String?),
      stickerId: sticker.id,
      stickerCategory: sticker.category,
      screenshotOf: ScreenshotSubject.fromId(data['screenshotOf'] as String?),
      screenshotsBlocked: (data['blocked'] as bool?) ?? false,
    );
  }

  /// Reads a stored `sticker: {id, category}` map, tolerating junk.
  static ({String? id, String? category}) _stickerFields(Object? raw) {
    if (raw is! Map) return (id: null, category: null);
    final id = raw['id'];
    final category = raw['category'];
    return (
      id: id is String ? id : null,
      category: category is String ? category : null,
    );
  }

  Map<String, dynamic> toMap() => type.isSystem ? _systemMap() : _map();

  /// System messages: text and no media, so the stored shape stays small.
  Map<String, dynamic> _systemMap() => {
    'senderId': senderId,
    'type': type.name,
    'text': text,
    'sentAt': FieldValue.serverTimestamp(),
    'seen': seen,
    if (type == MessageType.screenshot &&
        screenshotOf != ScreenshotSubject.chat)
      'screenshotOf': screenshotOf.name,
    if (type == MessageType.screenshotBlock) 'blocked': screenshotsBlocked,
  };

  Map<String, dynamic> _map() => {
    'senderId': senderId,
    'type': type.name,
    'text': text,
    'imageUrl': imageUrl,
    'imageAspectRatio': imageAspectRatio,
    'sentAt': FieldValue.serverTimestamp(),
    'seen': seen,
    'reactions': reactions,
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (durationMs != null) 'durationMs': durationMs,
    if (replyTo != null) 'replyTo': replyTo!.toMap(),
    if (type == MessageType.call) ...{
      'callType': isVideoCall ? 'video' : 'voice',
      'callOutcome': (callOutcome ?? CallOutcome.missed).name,
    },
    if (type == MessageType.sticker)
      'sticker': {'id': stickerId, 'category': stickerCategory},
  };
}
