import 'package:couple_app/core/backend/backend.dart';

/// What sits behind the messages.
enum ChatBackgroundKind {
  /// The plain chat colour.
  none('none'),

  /// One of the built-in patterns ([ChatBackground.patternId]).
  pattern('pattern'),

  /// A photo ([ChatBackground.photoUrl]).
  photo('photo');

  const ChatBackgroundKind(this.id);
  final String id;

  static ChatBackgroundKind fromId(String? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return ChatBackgroundKind.none;
  }
}

class ChatBackground {
  const ChatBackground({
    this.kind = ChatBackgroundKind.none,
    this.patternId,
    this.photoUrl,
    this.storagePath,
    this.dim = defaultDim,
    this.blur = 0,
  });

  final ChatBackgroundKind kind;

  /// A built-in pattern id, for [ChatBackgroundKind.pattern].
  final String? patternId;

  /// Download URL of the photo, for [ChatBackgroundKind.photo].
  final String? photoUrl;

  /// Where an uploaded background lives in Storage, so it can be removed
  /// when replaced. Null for photos reused from memories or chat.
  final String? storagePath;

  /// How much the photo is darkened (0 to [maxDim]) so bubbles stay readable.
  final double dim;

  /// Blur radius applied to the photo (0 to [maxBlur]).
  final double blur;

  static const defaultDim = 0.25;
  static const maxDim = 0.7;
  static const maxBlur = 12.0;

  static const none = ChatBackground();

  bool get isPhoto => kind == ChatBackgroundKind.photo && photoUrl != null;
  bool get isPattern => kind == ChatBackgroundKind.pattern && patternId != null;

  ChatBackground copyWith({
    ChatBackgroundKind? kind,
    String? patternId,
    String? photoUrl,
    String? storagePath,
    double? dim,
    double? blur,
  }) => ChatBackground(
    kind: kind ?? this.kind,
    patternId: patternId ?? this.patternId,
    photoUrl: photoUrl ?? this.photoUrl,
    storagePath: storagePath ?? this.storagePath,
    dim: dim ?? this.dim,
    blur: blur ?? this.blur,
  );

  Map<String, dynamic> toMap() => {
    'kind': kind.id,
    'patternId': kind == ChatBackgroundKind.pattern ? patternId : null,
    'photoUrl': kind == ChatBackgroundKind.photo ? photoUrl : null,
    'storagePath': kind == ChatBackgroundKind.photo ? storagePath : null,
    'dim': _clamp(dim, 0, maxDim),
    'blur': _clamp(blur, 0, maxBlur),
  };

  static ChatBackground fromMap(Object? raw) {
    if (raw is! Map) return none;
    final kind = ChatBackgroundKind.fromId(raw['kind'] as String?);
    final patternId = raw['patternId'];
    final photoUrl = raw['photoUrl'];
    final storagePath = raw['storagePath'];
    final bg = ChatBackground(
      kind: kind,
      patternId: patternId is String ? patternId : null,
      photoUrl: photoUrl is String && photoUrl.startsWith('http')
          ? photoUrl
          : null,
      storagePath: storagePath is String ? storagePath : null,
      dim: _clamp(_double(raw['dim']) ?? defaultDim, 0, maxDim),
      blur: _clamp(_double(raw['blur']) ?? 0, 0, maxBlur),
    );
    // A half-written background falls back to none rather than a blank.
    if (bg.kind == ChatBackgroundKind.photo && bg.photoUrl == null) return none;
    if (bg.kind == ChatBackgroundKind.pattern && bg.patternId == null) {
      return none;
    }
    return bg;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatBackground &&
      other.kind == kind &&
      other.patternId == patternId &&
      other.photoUrl == photoUrl &&
      other.storagePath == storagePath &&
      other.dim == dim &&
      other.blur == blur;

  @override
  int get hashCode =>
      Object.hash(kind, patternId, photoUrl, storagePath, dim, blur);
}

/// How the chat looks: the bubble colour and the background.
class ChatLook {
  const ChatLook({this.colorValue, this.background = ChatBackground.none});

  /// ARGB of the chosen chat colour; null means the app's default.
  final int? colorValue;
  final ChatBackground background;

  static const standard = ChatLook();

  bool get isStandard =>
      colorValue == null && background.kind == ChatBackgroundKind.none;

  ChatLook copyWith({
    int? colorValue,
    bool clearColor = false,
    ChatBackground? background,
  }) => ChatLook(
    colorValue: clearColor ? null : (colorValue ?? this.colorValue),
    background: background ?? this.background,
  );

  Map<String, dynamic> toMap() => {
    'color': colorValue,
    'background': background.toMap(),
  };

  static ChatLook fromMap(Object? raw) {
    if (raw is! Map) return standard;
    final color = raw['color'];
    return ChatLook(
      colorValue: color is int ? color : null,
      background: ChatBackground.fromMap(raw['background']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatLook &&
      other.colorValue == colorValue &&
      other.background == background;

  @override
  int get hashCode => Object.hash(colorValue, background);
}

/// The couple's shared chat look, plus who last changed it.
class SharedChatLook {
  const SharedChatLook({required this.look, this.updatedBy, this.updatedAt});

  final ChatLook look;
  final String? updatedBy;
  final DateTime? updatedAt;

  static SharedChatLook fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return const SharedChatLook(look: ChatLook.standard);
    final at = data['updatedAt'];
    return SharedChatLook(
      look: ChatLook.fromMap(data),
      updatedBy: data['updatedBy'] as String?,
      updatedAt: at is Timestamp ? at.toDate() : null,
    );
  }
}

/// Whether this person sees the couple's shared look or their own.
enum ChatLookMode {
  shared('shared'),
  personal('personal');

  const ChatLookMode(this.id);
  final String id;

  static ChatLookMode fromId(String? id) =>
      id == 'personal' ? ChatLookMode.personal : ChatLookMode.shared;
}

/// One person's chat-look settings, stored on their profile.
class PersonalChatLook {
  const PersonalChatLook({this.mode = ChatLookMode.shared, this.look});

  final ChatLookMode mode;

  /// Their own look; used only when [mode] is personal.
  final ChatLook? look;

  static PersonalChatLook fromProfile(Map<String, dynamic>? data) {
    if (data == null) return const PersonalChatLook();
    final raw = data['chatLook'];
    return PersonalChatLook(
      mode: ChatLookMode.fromId(data['chatLookMode'] as String?),
      look: raw is Map ? ChatLook.fromMap(raw) : null,
    );
  }

  /// What this person actually sees, given the couple's [shared] look.
  ChatLook effective(ChatLook shared) =>
      mode == ChatLookMode.personal ? (look ?? ChatLook.standard) : shared;
}

double? _double(Object? v) => v is num ? v.toDouble() : null;

double _clamp(double v, double min, double max) =>
    v.isNaN ? min : v.clamp(min, max).toDouble();
