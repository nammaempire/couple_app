import 'package:flutter/material.dart';

/// Asks for a date and then a time for a date plan. Returns null if either
/// picker is dismissed. New plans default to 7:30 PM.
Future<DateTime?> pickDatePlanDateTime(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final start = initial ?? DateTime(now.year, now.month, now.day);
  final first = DateTime(now.year - 5);
  final day = await showDatePicker(
    context: context,
    initialDate: start.isBefore(first) ? first : start,
    firstDate: first,
    lastDate: DateTime(now.year + 5, 12, 31),
    helpText: 'When is the date?',
  );
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: initial == null
        ? const TimeOfDay(hour: 19, minute: 30)
        : TimeOfDay.fromDateTime(initial),
    helpText: 'What time?',
  );
  if (time == null) return null;
  return DateTime(day.year, day.month, day.day, time.hour, time.minute);
}
