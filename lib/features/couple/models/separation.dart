import 'package:cloud_firestore/cloud_firestore.dart';

/// Where an ending pairing stands (`couples/{id}.separation.status`).
enum SeparationStatus {
  /// One partner asked; the other hasn't answered.
  requested,

  /// The other partner agreed, which can bring the date forward.
  agreed,

  /// The other partner said they don't want this. It still ends on the
  /// date, and they can still agree later.
  declined;

  static SeparationStatus parse(Object? raw) => switch (raw) {
    'agreed' => SeparationStatus.agreed,
    'declined' => SeparationStatus.declined,
    _ => SeparationStatus.requested,
  };
}

/// A pairing that is ending: `couples/{id}.separation`.
///
/// One partner asks; it takes effect [waitingPeriod] later, or
/// [agreedPeriod] after the other agrees if that is sooner. Only the one who
/// asked can call it off. Once [effectiveAt] has passed, the server deletes
/// everything the couple shared.
class Separation {
  const Separation({
    required this.requestedBy,
    required this.status,
    required this.effectiveAt,
    this.requestedAt,
    this.agreedAt,
    this.declinedAt,
  });

  /// From asking to the pairing ending, if the other partner doesn't agree.
  static const waitingPeriod = Duration(days: 14);

  /// From the other partner agreeing to the pairing ending, at most.
  static const agreedPeriod = Duration(days: 7);

  final String requestedBy;
  final SeparationStatus status;

  /// When the pairing ends and everything shared is deleted.
  final DateTime effectiveAt;

  /// Server time; null for a moment after asking, until the write lands.
  final DateTime? requestedAt;
  final DateTime? agreedAt;
  final DateTime? declinedAt;

  /// Reads the `separation` map, or null when there is none (or it is not
  /// a shape this app understands).
  static Separation? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final requestedBy = raw['requestedBy'];
    final effectiveAt = raw['effectiveAt'];
    if (requestedBy is! String || effectiveAt is! Timestamp) return null;
    return Separation(
      requestedBy: requestedBy,
      status: SeparationStatus.parse(raw['status']),
      effectiveAt: effectiveAt.toDate(),
      requestedAt: _date(raw['requestedAt']),
      agreedAt: _date(raw['agreedAt']),
      declinedAt: _date(raw['declinedAt']),
    );
  }

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : null;

  bool isRequestedBy(String uid) => requestedBy == uid;

  /// Whether [effectiveAt] has passed, so the server should finish it.
  bool isDue(DateTime now) => !now.isBefore(effectiveAt);

  /// Time left until [effectiveAt]; zero once it has passed.
  Duration remaining(DateTime now) {
    final left = effectiveAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// The end date once the other partner agrees at [now]: [agreedPeriod]
  /// from now, or the current date if that is sooner.
  DateTime effectiveAtIfAgreedAt(DateTime now) {
    final cap = now.add(agreedPeriod);
    return effectiveAt.isBefore(cap) ? effectiveAt : cap;
  }

  /// "13 days left", "1 day left", "5 hours left", "Less than an hour left".
  static String countdown(Duration left) {
    if (left <= Duration.zero) return 'Ending now';
    final hours = left.inMinutes / 60;
    if (hours >= 24) {
      final days = (hours / 24).ceil();
      return days == 1 ? '1 day left' : '$days days left';
    }
    final whole = hours.ceil();
    if (left < const Duration(hours: 1)) return 'Less than an hour left';
    return whole == 1 ? '1 hour left' : '$whole hours left';
  }
}

/// The server's marker while it deletes a couple: `couples/{id}.ending`.
class PairingEnding {
  const PairingEnding({this.how, this.startedAt});

  /// `agreed`, `oneSided` or `leftNow`.
  final String? how;
  final DateTime? startedAt;

  static PairingEnding? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final how = raw['how'];
    final startedAt = raw['startedAt'];
    return PairingEnding(
      how: how is String ? how : null,
      startedAt: startedAt is Timestamp ? startedAt.toDate() : null,
    );
  }
}
