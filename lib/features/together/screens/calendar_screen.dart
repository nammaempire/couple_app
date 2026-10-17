import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/together/data/event_service.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:couple_app/features/together/screens/event_editor_screen.dart';
import 'package:couple_app/features/together/widgets/calendar_day_section.dart';
import 'package:couple_app/features/together/widgets/calendar_event_tile.dart';
import 'package:couple_app/features/together/widgets/calendar_month_grid.dart';
import 'package:couple_app/features/together/widgets/calendar_month_header.dart';
import 'package:couple_app/features/together/widgets/calendar_section_title.dart';
import 'package:couple_app/features/together/widgets/event_details_sheet.dart';

/// The shared calendar: a month grid, the selected day's events and what is
/// coming up. Birthdays, the anniversary and the next meetup appear
/// automatically.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late final String _coupleId;
  late final String _myUid;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
  }

  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _today;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  List<CalendarEvent> _withAutomatic(List<CalendarEvent> stored) {
    final couple = ref.watch(coupleProvider).value;
    return [
      ...stored,
      ...ref.watch(datePlanCalendarEventsProvider),
      if (couple != null)
        ...EventService.automaticEvents(
          couple: couple,
          me: ref.watch(currentUserProvider),
          partner: ref.watch(partnerProvider).value,
          partnerName: ref.watch(partnerNameProvider),
        ),
    ];
  }

  void _openEditor({CalendarEvent? event, DateTime? day}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            EventEditorScreen(event: event, initialDay: day ?? _selected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final events = _withAutomatic(ref.watch(eventsProvider).value ?? const []);
    final dayEvents = _eventsOn(events, _selected);
    final upcoming = _upcoming(events);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-event',
        onPressed: _openEditor,
        icon: const Icon(Icons.add),
        label: const Text('Add event'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          CalendarMonthHeader(
            month: _month,
            onPrevious: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1),
            ),
            onNext: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1),
            ),
            onToday: () => setState(() {
              _month = DateTime(_today.year, _today.month);
              _selected = _today;
            }),
          ),
          CalendarMonthGrid(
            month: _month,
            selected: _selected,
            today: _today,
            events: events,
            onSelect: (day) => setState(() => _selected = day),
          ),
          const Divider(height: 24),
          CalendarDaySection(
            day: _selected,
            events: dayEvents,
            onOpen: (entry) => _showDetails(entry.$1, entry.$2),
            onAdd: () => _openEditor(day: _selected),
          ),
          if (upcoming.isNotEmpty) ...[
            const CalendarSectionTitle(label: 'Upcoming'),
            for (final (event, at) in upcoming)
              CalendarEventTile(
                event: event,
                when: at,
                showDate: true,
                onTap: () => _showDetails(event, at),
              ),
          ],
        ],
      ),
    );
  }

  List<(CalendarEvent, DateTime)> _eventsOn(
    List<CalendarEvent> events,
    DateTime day,
  ) {
    final list = <(CalendarEvent, DateTime)>[];
    for (final e in events) {
      for (final when in e.occurrencesBetween(day, day)) {
        list.add((e, when));
      }
    }
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list;
  }

  /// The next 60 days, soonest first, at most 8.
  List<(CalendarEvent, DateTime)> _upcoming(List<CalendarEvent> events) {
    final from = _today;
    final to = from.add(const Duration(days: 60));
    final list = <(CalendarEvent, DateTime)>[];
    for (final e in events) {
      for (final when in e.occurrencesBetween(from, to)) {
        if (!DateTime(when.year, when.month, when.day).isBefore(from)) {
          list.add((e, when));
        }
      }
    }
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list.take(8).toList();
  }

  Future<void> _showDetails(CalendarEvent event, DateTime at) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => EventDetailsSheet(
        event: event,
        when: at,
        canEdit:
            !event.isAutomatic &&
            (!event.isPrivate || event.createdBy == _myUid),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') _openEditor(event: event);
    if (action == 'delete') {
      try {
        await ref
            .read(eventServiceProvider)
            .delete(coupleId: _coupleId, eventId: event.id);
      } catch (_) {
        if (!mounted) return;
        context.showSnackMessage('Could not delete that event.');
      }
    }
  }
}
