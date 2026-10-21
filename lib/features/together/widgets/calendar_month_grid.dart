import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/widgets/calendar_event_look.dart';

/// A month of day cells, with coloured dots on days that have events.
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.events,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final firstWeekday = localizations.firstDayOfWeekIndex; // 0 = Sunday

    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // DateTime.weekday: Mon=1..Sun=7 → 0..6 with Sunday = 0.
    final leading = (first.weekday % 7 - firstWeekday + 7) % 7;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    // Which days in this month have events, for the dots.
    final lastDay = DateTime(month.year, month.month, daysInMonth);
    final marks = <int, List<EventType>>{};
    for (final e in events) {
      for (final occurrence in e.occurrencesBetween(first, lastDay)) {
        for (var i = 0; i < e.spanDays; i++) {
          final d = DateTime(
            occurrence.year,
            occurrence.month,
            occurrence.day + i,
          );
          if (d.month != month.month || d.year != month.year) continue;
          (marks[d.day] ??= []).add(e.type);
        }
      }
    }

    final weekdayNames = localizations.narrowWeekdays;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      weekdayNames[(i + firstWeekday) % 7],
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _dayCell(
                      context,
                      row * 7 + col - leading + 1,
                      daysInMonth,
                      marks,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(
    BuildContext context,
    int dayNumber,
    int daysInMonth,
    Map<int, List<EventType>> marks,
  ) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 48);
    }
    final theme = Theme.of(context);
    final day = DateTime(month.year, month.month, dayNumber);
    final isSelected = day == selected;
    final isToday = day == today;
    final types = marks[dayNumber] ?? const <EventType>[];

    final b = theme.brightness;
    final dark = b == Brightness.dark;
    final accent = GradientPreset.blush.accent(b);
    final selectedGradient = dark
        ? [const Color(0xFFFFB3C8), const Color(0xFFE5A6FF)]
        : [const Color(0xFFD81B60), const Color(0xFF8E3FD0)];
    final selectedText = dark ? const Color(0xFF3B1424) : Colors.white;

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${DateFormat.MMMMd().format(day)}'
          '${types.isEmpty ? '' : ', ${types.length} events'}',
      child: InkWell(
        onTap: () => onSelect(day),
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isSelected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: selectedGradient,
                        )
                      : null,
                  color: !isSelected && isToday
                      ? Colors.white.withValues(alpha: dark ? .12 : .6)
                      : null,
                  border: isToday && !isSelected
                      ? Border.all(color: accent, width: 1.6)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: selectedGradient.first.withValues(
                              alpha: dark ? .25 : .4,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  '$dayNumber',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isSelected ? selectedText : null,
                    fontWeight: isToday || isSelected ? FontWeight.w700 : null,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final t in types.take(3))
                      Container(
                        width: 9,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: LinearGradient(colors: t.dotColors(b)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
