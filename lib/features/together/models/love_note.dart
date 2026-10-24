import 'package:couple_app/core/backend/backend.dart';

enum NoteKind {
  /// A letter delivered now or on a chosen date.
  letter,

  /// An "Open when…" envelope, available straight away but kept sealed
  /// until the partner chooses to open it.
  openWhen,
}

/// "Open when…" envelopes from the product spec, plus a few more.
enum OpenWhen {
  missMe('miss', 'Open when you miss me', '🥺'),
  badDay('badDay', 'Open when you\'re having a bad day', '🌧️'),
  cantSleep('cantSleep', 'Open when you can\'t sleep', '🌙'),
  needSmile('smile', 'Open when you need a smile', '😊'),
  birthday('birthday', 'For your birthday', '🎂'),
  anniversary('anniversary', 'For our anniversary', '💍');

  const OpenWhen(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;

  static OpenWhen? fromId(String? id) {
    for (final o in values) {
      if (o.id == id) return o;
    }
    return null;
  }
}

/// The envelope of a love note: who, when and what kind. Both partners can
/// read this. The words themselves live in a separate document the
/// recipient can only read from [deliverAt] (enforced by the rules).
class LoveNote {
  final String id;
  final String senderId;
  final String recipientId;
  final NoteKind kind;
  final OpenWhen? openWhen;

  /// Shown on the envelope; the body stays sealed.
  final String title;

  final DateTime deliverAt;
  final DateTime? createdAt;
  final DateTime? openedAt;

  final bool hasVoice;
  final int? voiceDurationMs;

  const LoveNote({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.kind,
    required this.title,
    required this.deliverAt,
    this.openWhen,
    this.createdAt,
    this.openedAt,
    this.hasVoice = false,
    this.voiceDurationMs,
  });

  bool isDelivered(DateTime now) => !deliverAt.isAfter(now);
  bool get isOpened => openedAt != null;

  /// A scheduled note that has not arrived yet.
  bool isScheduled(DateTime now) => !isDelivered(now);

  String get envelopeTitle {
    final o = openWhen;
    if (kind == NoteKind.openWhen && o != null) return o.label;
    return title.isEmpty ? 'A love note' : title;
  }

  String get emoji => openWhen?.emoji ?? '💌';

  factory LoveNote.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return LoveNote(
      id: doc.id,
      senderId: (data['senderId'] as String?) ?? '',
      recipientId: (data['recipientId'] as String?) ?? '',
      kind: data['kind'] == 'openWhen' ? NoteKind.openWhen : NoteKind.letter,
      openWhen: OpenWhen.fromId(data['openWhen'] as String?),
      title: (data['title'] as String?) ?? '',
      deliverAt: (data['deliverAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      openedAt: (data['openedAt'] as Timestamp?)?.toDate(),
      hasVoice: (data['hasVoice'] as bool?) ?? false,
      voiceDurationMs: (data['voiceDurationMs'] as num?)?.toInt(),
    );
  }
}

/// The sealed part of a note.
class LoveNoteContent {
  final String body;
  final String? voiceUrl;

  const LoveNoteContent({required this.body, this.voiceUrl});
}
