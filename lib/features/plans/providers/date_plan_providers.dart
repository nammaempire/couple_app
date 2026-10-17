import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';

final datePlanServiceProvider = Provider<DatePlanService>(
  (ref) => DatePlanService(),
);

/// Every date plan of the couple (ideas, planned and done), unsorted.
/// Group and sort with `DatePlanLists`. After an error the last good list
/// is kept in `.value`.
final datePlansProvider = StreamProvider.autoDispose<List<DatePlan>>(
  (ref) => ref
      .watch(datePlanServiceProvider)
      .watchPlans(ref.watch(currentCoupleIdProvider)),
);

/// Planned and completed dates as calendar entries, so they show on the
/// calendar and get a reminder an hour before, without a second copy in
/// the events collection.
final datePlanCalendarEventsProvider =
    Provider.autoDispose<List<CalendarEvent>>((ref) {
      final plans = ref.watch(datePlansProvider).value ?? const [];
      return plans
          .map((plan) => plan.toCalendarEvent())
          .whereType<CalendarEvent>()
          .toList();
    });

/// Only dates still to come (status planned), for Home's "Coming up".
final plannedDateEventsProvider = Provider.autoDispose<List<CalendarEvent>>((
  ref,
) {
  final plans = ref.watch(datePlansProvider).value ?? const [];
  return plans
      .where((plan) => plan.status == DatePlanStatus.planned)
      .map((plan) => plan.toCalendarEvent())
      .whereType<CalendarEvent>()
      .toList();
});
