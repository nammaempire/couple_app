import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/date_plan_lists.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/plans/screens/date_plan_editor_screen.dart';
import 'package:couple_app/features/plans/widgets/date_plan_card.dart';
import 'package:couple_app/features/plans/widgets/date_plan_date_time_picker.dart';
import 'package:couple_app/features/plans/widgets/date_plan_details_sheet.dart';
import 'package:couple_app/features/plans/widgets/date_plan_done_sheet.dart';
import 'package:couple_app/features/plans/widgets/date_plan_surprise_card.dart';
import 'package:couple_app/features/plans/widgets/date_plan_surprise_dialog.dart';
import 'package:couple_app/features/plans/widgets/date_planner_empty_state.dart';
import 'package:couple_app/features/together/widgets/calendar_section_title.dart';

/// Date ideas, planned dates and the ones you've been on, with "Surprise
/// me" for when you can't decide.
class DatePlannerScreen extends ConsumerStatefulWidget {
  const DatePlannerScreen({super.key});

  @override
  ConsumerState<DatePlannerScreen> createState() => _DatePlannerScreenState();
}

class _DatePlannerScreenState extends ConsumerState<DatePlannerScreen> {
  late final String _coupleId;
  late final String _myUid;
  late final DatePlanService _service;
  final _random = Random();

  DatePlanStatus _segment = DatePlanStatus.idea;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(datePlanServiceProvider);
  }

  void _openEditor({DatePlan? plan, bool schedule = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => DatePlanEditorScreen(plan: plan, scheduleNew: schedule),
      ),
    );
  }

  /// Runs [action], showing [failure] if it throws. Returns whether it
  /// succeeded, so callers only celebrate real saves.
  Future<bool> _run(Future<void> Function() action, String failure) async {
    try {
      await action();
      return true;
    } catch (_) {
      if (mounted) context.showSnackMessage(failure);
      return false;
    }
  }

  Future<void> _plan(DatePlan plan) async {
    final at = await pickDatePlanDateTime(context, initial: plan.scheduledAt);
    if (at == null) return;
    final ok = await _run(
      () => _service.schedule(_coupleId, plan.id, at),
      'Could not save. Check your connection.',
    );
    if (!ok || !mounted) return;
    if (plan.isIdea) {
      setState(() => _segment = DatePlanStatus.planned);
      context.showSnackMessage('Planned! It\'s on your calendar now.');
    }
  }

  Future<void> _markDone(DatePlan plan) async {
    final recap = await showModalBottomSheet<DatePlanRecap>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DatePlanDoneSheet(plan: plan),
    );
    if (recap == null) return;
    await _run(
      () => _service.markDone(
        _coupleId,
        plan.id,
        rating: recap.rating,
        reflection: recap.reflection,
      ),
      'Could not save. Check your connection.',
    );
  }

  Future<void> _delete(DatePlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this date?'),
        content: const Text('This removes it for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => _service.delete(_coupleId, plan.id),
      'Could not delete. Check your connection.',
    );
  }

  Future<void> _showDetails(DatePlan plan, String currency) async {
    final partnerName = ref.read(partnerNameProvider);
    final action = await showModalBottomSheet<DatePlanAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DatePlanDetailsSheet(
        plan: plan,
        now: DateTime.now(),
        currency: currency,
        addedBy: plan.createdBy == _myUid ? 'you' : partnerName,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case DatePlanAction.plan:
      case DatePlanAction.reschedule:
        await _plan(plan);
      case DatePlanAction.markDone:
        await _markDone(plan);
      case DatePlanAction.moveToIdeas:
        await _run(
          () => _service.moveToIdeas(_coupleId, plan.id),
          'Could not save. Check your connection.',
        );
      case DatePlanAction.edit:
        _openEditor(plan: plan);
      case DatePlanAction.delete:
        await _delete(plan);
    }
  }

  Future<void> _surprise(List<DatePlan> ideas) async {
    String? previous;
    while (mounted) {
      final pick = DatePlanLists.surprise(ideas, _random, previousId: previous);
      if (pick == null) return;
      final choice = await showDialog<DatePlanSurpriseChoice>(
        context: context,
        builder: (_) =>
            DatePlanSurpriseDialog(plan: pick, canPickAgain: ideas.length > 1),
      );
      if (!mounted) return;
      if (choice == DatePlanSurpriseChoice.plan) {
        await _plan(pick);
        return;
      }
      if (choice != DatePlanSurpriseChoice.again) return;
      previous = pick.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(datePlansProvider);
    final currency = ref.watch(coupleProvider).value?.currency ?? 'INR';
    final partnerName = ref.watch(partnerNameProvider);
    final all = plans.value ?? const <DatePlan>[];
    final now = DateTime.now();

    final ideas = DatePlanLists.ideas(all);
    final upcoming = DatePlanLists.upcoming(all, now);
    final recap = DatePlanLists.needsRecap(all, now);
    final done = DatePlanLists.done(all);

    int count(DatePlanStatus s) => switch (s) {
      DatePlanStatus.idea => ideas.length,
      DatePlanStatus.planned => upcoming.length + recap.length,
      DatePlanStatus.done => done.length,
    };

    Widget card(DatePlan p) => DatePlanCard(
      key: ValueKey(p.id),
      plan: p,
      now: now,
      currency: currency,
      onTap: () => _showDetails(p, currency),
      onMarkDone: () => _markDone(p),
      onPlan: () => _plan(p),
    );

    Widget body;
    if (!plans.hasValue && !plans.hasError) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!plans.hasValue) {
      body = const EmptyState(
        icon: Icons.cloud_off,
        text: 'Could not load your date plans.',
      );
    } else if (count(_segment) == 0) {
      body = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: DatePlannerEmptyState(
              status: _segment,
              partnerName: partnerName,
              onAdd: () =>
                  _openEditor(schedule: _segment == DatePlanStatus.planned),
            ),
          ),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 96),
        children: switch (_segment) {
          DatePlanStatus.idea => [
            DatePlanSurpriseCard(
              ideaCount: ideas.length,
              onSurprise: () => _surprise(ideas),
            ),
            ...ideas.map(card),
          ],
          DatePlanStatus.planned => [
            if (upcoming.isNotEmpty) ...[
              const CalendarSectionTitle(label: 'Coming up'),
              ...upcoming.map(card),
            ],
            if (recap.isNotEmpty) ...[
              const CalendarSectionTitle(label: 'How did it go?'),
              ...recap.map(card),
            ],
          ],
          DatePlanStatus.done => [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                done.length == 1
                    ? 'Your first date story. Many more to come.'
                    : '${done.length} dates you and $partnerName have been on.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...done.map(card),
          ],
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Date planner')),
      floatingActionButton: _segment == DatePlanStatus.done
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add-date-plan',
              onPressed: () =>
                  _openEditor(schedule: _segment == DatePlanStatus.planned),
              icon: const Icon(Icons.add),
              label: Text(
                _segment == DatePlanStatus.planned ? 'Plan a date' : 'New idea',
              ),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<DatePlanStatus>(
                showSelectedIcon: false,
                segments: [
                  for (final s in DatePlanStatus.values)
                    ButtonSegment(
                      value: s,
                      icon: Icon(s.icon, size: 18),
                      label: Text(
                        plans.hasValue && count(s) > 0
                            ? '${s.label} ${count(s)}'
                            : s.label,
                      ),
                    ),
                ],
                selected: {_segment},
                onSelectionChanged: (s) => setState(() => _segment = s.first),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(key: ValueKey(_segment), child: body),
            ),
          ),
        ],
      ),
    );
  }
}
