// Value types shared by the app and the Us server: timestamps, write-time
// field operations, and the JSON encoding used on the wire.
//
// The names match the Firestore SDK the app used before (Timestamp,
// FieldValue, SetOptions …) so feature code reads the same.
//
// Pure Dart (no Flutter), so it also runs in command-line tools.

/// A point in time with microsecond precision, stored by the server as
/// `{"$ts": "<ISO-8601 UTC>"}` (millisecond precision on the wire).
class Timestamp implements Comparable<Timestamp> {
  Timestamp(this.seconds, this.nanoseconds)
    : assert(nanoseconds >= 0 && nanoseconds < 1000000000);

  factory Timestamp.fromDate(DateTime date) =>
      Timestamp.fromMicrosecondsSinceEpoch(date.microsecondsSinceEpoch);

  factory Timestamp.fromMillisecondsSinceEpoch(int ms) =>
      Timestamp.fromMicrosecondsSinceEpoch(ms * 1000);

  factory Timestamp.fromMicrosecondsSinceEpoch(int us) {
    final seconds = (us / 1000000).floor();
    final nanos = (us - seconds * 1000000) * 1000;
    return Timestamp(seconds, nanos);
  }

  factory Timestamp.now() => Timestamp.fromDate(DateTime.now());

  /// Parses the wire form ("2026-10-24T07:00:00.000Z").
  factory Timestamp.parse(String iso) => Timestamp.fromDate(DateTime.parse(iso));

  final int seconds;
  final int nanoseconds;

  int get microsecondsSinceEpoch => seconds * 1000000 + nanoseconds ~/ 1000;
  int get millisecondsSinceEpoch => microsecondsSinceEpoch ~/ 1000;

  /// Local time, like Firestore's Timestamp.toDate().
  DateTime toDate() =>
      DateTime.fromMicrosecondsSinceEpoch(microsecondsSinceEpoch);

  /// The wire form: always UTC with milliseconds, so values sort as text.
  String toIso() => DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();

  @override
  int compareTo(Timestamp other) => seconds != other.seconds
      ? seconds.compareTo(other.seconds)
      : nanoseconds.compareTo(other.nanoseconds);

  @override
  bool operator ==(Object other) =>
      other is Timestamp &&
      other.seconds == seconds &&
      other.nanoseconds == nanoseconds;

  @override
  int get hashCode => Object.hash(seconds, nanoseconds);

  @override
  String toString() => 'Timestamp(${toIso()})';
}

/// Field operations resolved by the server when a write commits.
class FieldValue {
  const FieldValue._(this._json);

  final Map<String, Object?> _json;

  /// The server's commit time.
  static FieldValue serverTimestamp() =>
      const FieldValue._({r'$sv': 'serverTimestamp'});

  /// Removes the field (in update() and set(merge: true)).
  static FieldValue delete() => const FieldValue._({r'$sv': 'delete'});

  static FieldValue increment(num by) =>
      FieldValue._({r'$sv': 'increment', 'by': by});

  static FieldValue arrayUnion(List<Object?> values) =>
      FieldValue._({r'$sv': 'arrayUnion', 'values': encodeValue(values)});

  static FieldValue arrayRemove(List<Object?> values) =>
      FieldValue._({r'$sv': 'arrayRemove', 'values': encodeValue(values)});

  Map<String, Object?> toJson() => _json;

  /// The operation name ("serverTimestamp", "delete", …).
  String get kind => _json[r'$sv']! as String;

  @override
  bool operator ==(Object other) =>
      other is FieldValue && _jsonEquals(other._json, _json);

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'FieldValue($_json)';
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_jsonEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// Options for set(): merge into the existing document instead of replacing it.
class SetOptions {
  const SetOptions({this.merge = false});
  final bool merge;
}

/// Accepted for source compatibility; the server is always the source.
enum Source { serverAndCache, server, cache }

class GetOptions {
  const GetOptions({this.source = Source.serverAndCache});
  final Source source;
}

/// An error from the Us server (or the connection to it).
///
/// [code] uses the same names Firestore did: permission-denied, not-found,
/// already-exists, aborted, failed-precondition, unavailable, unauthenticated,
/// invalid-argument, internal.
class DbException implements Exception {
  DbException(this.code, [this.message, this.details]);

  final String code;
  final String? message;
  final Object? details;

  @override
  String toString() => 'DbException($code): ${message ?? ''}';
}

/// Dart value → JSON for the wire. DateTime and Timestamp become `{"$ts"}`.
Object? encodeValue(Object? v) {
  if (v == null || v is bool || v is String) return v;
  if (v is num) {
    if (v is double && !v.isFinite) {
      throw ArgumentError('Numbers must be finite.');
    }
    return v;
  }
  if (v is Timestamp) return {r'$ts': v.toIso()};
  if (v is DateTime) return {r'$ts': Timestamp.fromDate(v).toIso()};
  if (v is FieldValue) return v.toJson();
  if (v is Iterable) return [for (final x in v) encodeValue(x)];
  if (v is Map) {
    return {for (final e in v.entries) e.key.toString(): encodeValue(e.value)};
  }
  throw ArgumentError('Unsupported value type: ${v.runtimeType}');
}

/// JSON from the server → Dart values. `{"$ts"}` becomes [Timestamp].
Object? decodeValue(Object? v) {
  if (v is Map) {
    if (v.length == 1 && v[r'$ts'] is String) {
      return Timestamp.parse(v[r'$ts'] as String);
    }
    return <String, dynamic>{
      for (final e in v.entries) e.key as String: decodeValue(e.value),
    };
  }
  if (v is List) return <dynamic>[for (final x in v) decodeValue(x)];
  return v;
}

Map<String, dynamic> decodeData(Object? v) {
  final d = decodeValue(v);
  return d is Map<String, dynamic> ? d : <String, dynamic>{};
}
