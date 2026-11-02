import 'package:couple_app/core/backend/backend.dart';

/// Dates without a time — birthdays, the day you started, the next
/// meetup, all-day events, the day of an expense or a place visit — stored
/// so they show the same day on every phone, whatever its time zone.
///
/// Stored as a timestamp at midnight UTC of that calendar day (so ordering
/// and queries still work). Older values were saved as midnight on the
/// writer's phone (for India, 18:30 UTC the day before); [read] gives the
/// right day for both: it takes the UTC date of the stored instant plus 12
/// hours, which is exact for new values and for old ones written anywhere
/// from UTC−11:59 to UTC+12:00.
abstract final class CalendarDate {
  /// The value to store for the calendar day of [day] (its time is ignored).
  static Timestamp write(DateTime day) =>
      Timestamp.fromDate(DateTime.utc(day.year, day.month, day.day));

  /// [write], or null.
  static Timestamp? writeOrNull(DateTime? day) =>
      day == null ? null : write(day);

  /// The stored day as local midnight of that day, or null when [value] is
  /// not a timestamp.
  static DateTime? read(Object? value) {
    final DateTime instant;
    if (value is Timestamp) {
      instant = value.toDate();
    } else if (value is DateTime) {
      instant = value;
    } else {
      return null;
    }
    final u = instant.toUtc().add(const Duration(hours: 12));
    return DateTime(u.year, u.month, u.day);
  }
}
