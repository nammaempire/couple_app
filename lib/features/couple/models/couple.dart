import 'package:cloud_firestore/cloud_firestore.dart';

/// A pair of users sharing one conversation.
class Couple {
  final String id;

  /// Short code the second partner enters to join.
  final String inviteCode;

  /// Exactly one or two uids. One means "waiting for partner to join".
  final List<String> memberIds;

  final DateTime? createdAt;

  /// The day the relationship started, used for the days-together counter.
  final DateTime? startDate;

  /// The next time the two of you will be in the same place.
  final DateTime? nextMeetup;

  /// Pet names, keyed by the uid of the person who *set* the name — so the
  /// value is what that person calls their partner. Each of you can pick your
  /// own, without having to agree on one.
  final Map<String, String> nicknames;

  /// Optional name for the two of you, e.g. "Navi & Priya" or "Team Us".
  final String? coupleName;

  /// Optional shared couple photo.
  final String? photoUrl;

  /// When the second partner accepted the invite.
  final DateTime? activatedAt;

  /// ISO 4217 code used for shared expenses.
  final String currency;

  /// When a partner last cleared the chat for both of you (server time).
  /// Messages sent at or before it are deleted, and hidden until they are.
  final DateTime? chatClearedAt;

  /// Uid of the partner who last cleared the chat for both.
  final String? chatClearedBy;

  /// Shared switch: while on, both phones block screenshots of the chat.
  final bool blockScreenshots;

  static const defaultCurrency = 'INR';

  const Couple({
    required this.id,
    required this.inviteCode,
    required this.memberIds,
    this.createdAt,
    this.startDate,
    this.nextMeetup,
    this.nicknames = const {},
    this.coupleName,
    this.photoUrl,
    this.activatedAt,
    this.currency = defaultCurrency,
    this.chatClearedAt,
    this.chatClearedBy,
    this.blockScreenshots = false,
  });

  /// What [uid] calls their partner, if they have set anything.
  String? nicknameChosenBy(String uid) {
    final name = nicknames[uid]?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  bool get isComplete => memberIds.length >= 2;

  String? partnerIdFor(String uid) {
    for (final id in memberIds) {
      if (id != uid) return id;
    }
    return null;
  }

  /// Whole days since [startDate], or null if no start date is set.
  int? get daysTogether {
    final start = startDate;
    if (start == null) return null;
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(start.year, start.month, start.day)).inDays;
  }

  /// Time together as calendar years, months and days, e.g. 2y 3m 5d.
  /// Null if no start date is set.
  ({int years, int months, int days})? togetherBreakdown([DateTime? today]) {
    final start = startDate;
    if (start == null) return null;
    return calendarDifference(start, today ?? DateTime.now());
  }

  /// Calendar-aware difference between two dates, ignoring time of day.
  /// Month lengths are respected: Jan 31 → Feb 28 is 28 days, not 1 month.
  static ({int years, int months, int days}) calendarDifference(
    DateTime from,
    DateTime to,
  ) {
    // UTC dates so a daylight-saving change never shifts the day count.
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    if (b.isBefore(a)) return (years: 0, months: 0, days: 0);

    // Whole months that fit, then the leftover days from that anchor. The
    // anchor is capped at month end, so Jan 31 + 1 month is Feb 28.
    var totalMonths = (b.year - a.year) * 12 + (b.month - a.month);
    DateTime anchorFor(int months) {
      final year = a.year + (a.month - 1 + months) ~/ 12;
      final month = (a.month - 1 + months) % 12 + 1;
      final lastDay = DateTime.utc(year, month + 1, 0).day;
      return DateTime.utc(year, month, a.day > lastDay ? lastDay : a.day);
    }

    var anchor = anchorFor(totalMonths);
    if (anchor.isAfter(b)) {
      totalMonths -= 1;
      anchor = anchorFor(totalMonths);
    }
    return (
      years: totalMonths ~/ 12,
      months: totalMonths % 12,
      days: b.difference(anchor).inDays,
    );
  }

  /// The next round-number day count worth celebrating, and how far off it is.
  ({int milestone, int daysAway})? get nextMilestone {
    final days = daysTogether;
    if (days == null) return null;

    final candidates = <int>[
      100,
      200,
      300,
      365,
      500,
      730,
      1000,
      1095,
      1460,
      1825,
      2000,
      2555,
      3000,
    ];
    for (final candidate in candidates) {
      if (candidate > days) {
        return (milestone: candidate, daysAway: candidate - days);
      }
    }
    // Past the table: celebrate each further 1000 days.
    final next = ((days ~/ 1000) + 1) * 1000;
    return (milestone: next, daysAway: next - days);
  }

  factory Couple.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Couple(
      id: doc.id,
      inviteCode: (data['inviteCode'] as String?) ?? '',
      memberIds: List<String>.from(
        (data['memberIds'] as List<dynamic>?) ?? const <dynamic>[],
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      nextMeetup: (data['nextMeetup'] as Timestamp?)?.toDate(),
      nicknames: Map<String, String>.from(
        (data['nicknames'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
      coupleName: _nonBlank(data['coupleName'] as String?),
      photoUrl: data['photoUrl'] as String?,
      activatedAt: (data['activatedAt'] as Timestamp?)?.toDate(),
      currency: _nonBlank(data['currency'] as String?) ?? defaultCurrency,
      chatClearedAt: (data['chatClearedAt'] as Timestamp?)?.toDate(),
      chatClearedBy: data['chatClearedBy'] as String?,
      blockScreenshots: (data['blockScreenshots'] as bool?) ?? false,
    );
  }

  static String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
