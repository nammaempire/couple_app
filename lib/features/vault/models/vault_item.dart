import 'package:couple_app/core/backend/backend.dart';
import 'package:flutter/foundation.dart';

/// What a vault item holds.
enum VaultItemKind {
  photo,
  message;

  static VaultItemKind fromName(Object? name) =>
      name == 'photo' ? VaultItemKind.photo : VaultItemKind.message;
}

/// How long an item lasts.
enum VaultPolicy {
  /// Until someone deletes it.
  keep('keep', 'Keep', null, 'Stays until one of you deletes it'),

  /// Deleted once the other person has seen it.
  once('once', 'View once', '👁', 'Gone after they see it'),

  /// Deleted 24 hours after it was added.
  day('day', '24 hours', '⏳', 'Gone after a day');

  const VaultPolicy(this.value, this.label, this.badge, this.description);

  final String value;
  final String label;

  /// A small emoji shown on the item, or null for [keep].
  final String? badge;
  final String description;

  static const lifetime = Duration(hours: 24);

  static VaultPolicy fromValue(Object? value) => VaultPolicy.values.firstWhere(
    (p) => p.value == value,
    orElse: () => VaultPolicy.keep,
  );
}

/// One photo or message in the vault: `couples/{cid}/vaultItems/{id}`.
///
/// Everything readable is in [ct], encrypted; the rest is what the server
/// needs to enforce the rules and clean up.
@immutable
class VaultItem {
  const VaultItem({
    required this.id,
    required this.senderId,
    required this.kind,
    required this.shelf,
    required this.ct,
    required this.policy,
    this.photoPath,
    this.thumbPath,
    this.expiresAt,
    this.viewedBy = const {},
    this.createdAt,
  });

  final String id;
  final String senderId;
  final VaultItemKind kind;

  /// `'a'` or `'b'`. Which one is the decoy is only known after unlocking.
  final String shelf;

  /// Base64 AES-GCM of the content JSON.
  final String ct;
  final String? photoPath;
  final String? thumbPath;
  final VaultPolicy policy;
  final DateTime? expiresAt;

  /// Who has viewed it, and when.
  final Map<String, DateTime?> viewedBy;

  /// Null until the server has stamped it.
  final DateTime? createdAt;

  bool isExpired(DateTime now) {
    final at = expiresAt;
    return at != null && !now.isBefore(at);
  }

  bool viewedByUid(String uid) => viewedBy.containsKey(uid);

  /// Storage paths of its files.
  List<String> get files => [?photoPath, ?thumbPath];

  factory VaultItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      VaultItem.fromMap(doc.id, doc.data() ?? const {});

  factory VaultItem.fromMap(String id, Map<String, dynamic> data) {
    final viewed = <String, DateTime?>{};
    final raw = data['viewedBy'];
    if (raw is Map) {
      raw.forEach((uid, at) {
        viewed[uid as String] = at is Timestamp ? at.toDate() : null;
      });
    }
    return VaultItem(
      id: id,
      senderId: (data['senderId'] as String?) ?? '',
      kind: VaultItemKind.fromName(data['kind']),
      shelf: (data['shelf'] as String?) ?? 'a',
      ct: (data['ct'] as String?) ?? '',
      photoPath: data['photoPath'] as String?,
      thumbPath: data['thumbPath'] as String?,
      policy: VaultPolicy.fromValue(data['policy']),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      viewedBy: viewed,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// A decrypted message.
@immutable
class VaultMessageContent {
  const VaultMessageContent(this.text);

  /// Longest message, in characters.
  static const maxLength = 2000;

  final String text;

  Map<String, dynamic> toJson() => {'type': 'message', 'text': text};

  factory VaultMessageContent.fromJson(Map<String, dynamic> json) =>
      VaultMessageContent((json['text'] as String?) ?? '');
}

/// A decrypted photo's details.
@immutable
class VaultPhotoContent {
  const VaultPhotoContent({
    required this.width,
    required this.height,
    required this.photoPath,
    required this.thumbPath,
    required this.bytes,
  });

  final int width;
  final int height;
  final String photoPath;
  final String thumbPath;

  /// Size of the clear JPEG.
  final int bytes;

  Map<String, dynamic> toJson() => {
    'type': 'photo',
    'w': width,
    'h': height,
    'photo': photoPath,
    'thumb': thumbPath,
    'bytes': bytes,
  };

  factory VaultPhotoContent.fromJson(Map<String, dynamic> json) =>
      VaultPhotoContent(
        width: (json['w'] as int?) ?? 0,
        height: (json['h'] as int?) ?? 0,
        photoPath: (json['photo'] as String?) ?? '',
        thumbPath: (json['thumb'] as String?) ?? '',
        bytes: (json['bytes'] as int?) ?? 0,
      );
}
