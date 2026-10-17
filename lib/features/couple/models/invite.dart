import 'package:cloud_firestore/cloud_firestore.dart';

/// A single-use invitation to join a couple.
///
/// Stored at `invites/{code}` so a partner can look one up by its code
/// without being able to browse couples. Security rules allow `get` but not
/// `list`, so codes cannot be enumerated.
class Invite {
  final String code;
  final String coupleId;
  final String createdBy;

  /// Shown on the accept screen, since the joiner cannot read the inviter's
  /// profile until they are a member.
  final String inviterName;
  final String? inviterPhotoUrl;
  final String? coupleName;

  final bool used;
  final DateTime? createdAt;

  const Invite({
    required this.code,
    required this.coupleId,
    required this.createdBy,
    required this.inviterName,
    this.inviterPhotoUrl,
    this.coupleName,
    this.used = false,
    this.createdAt,
  });

  factory Invite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final coupleName = (data['coupleName'] as String?)?.trim();
    return Invite(
      code: doc.id,
      coupleId: (data['coupleId'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      inviterName: (data['inviterName'] as String?) ?? 'Your partner',
      inviterPhotoUrl: data['inviterPhotoUrl'] as String?,
      coupleName: (coupleName == null || coupleName.isEmpty)
          ? null
          : coupleName,
      used: (data['used'] as bool?) ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Helpers for invite codes typed by hand or scanned from a QR code.
class InviteCode {
  const InviteCode._();

  static const length = 6;

  /// No 0/O or 1/I, so codes read back unambiguously.
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// The scheme encoded in invite QR codes.
  static const qrPrefix = 'us-couple://join?code=';

  static String qrPayload(String code) => '$qrPrefix$code';

  /// Pulls a valid code out of [raw], which may be a bare code, a QR payload,
  /// or a shared message containing the code. Returns null if none is found.
  static String? extract(String? raw) {
    if (raw == null) return null;
    final text = raw.trim().toUpperCase();

    // "code=ABC123" (QR payload) or "code: ABC123" / "code ABC123" (message).
    final labelled = RegExp(
      r'CODE\s*[=:]?\s*([A-Z0-9]{6})(?![A-Z0-9])',
    ).firstMatch(text)?.group(1);
    final candidate = labelled ?? (text.length == length ? text : null);

    if (candidate == null || !isValid(candidate)) return null;
    return candidate;
  }

  static bool isValid(String code) {
    if (code.length != length) return false;
    for (final char in code.split('')) {
      if (!alphabet.contains(char)) return false;
    }
    return true;
  }
}
