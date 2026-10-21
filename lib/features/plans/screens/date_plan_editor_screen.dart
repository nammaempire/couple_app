import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/plans/data/date_plan_service.dart';
import 'package:couple_app/features/plans/models/date_plan.dart';
import 'package:couple_app/features/plans/models/date_plan_lists.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/plans/widgets/date_plan_date_time_picker.dart';
import 'package:couple_app/features/plans/widgets/date_plan_hearts.dart';
import 'package:couple_app/features/together/widgets/event_picker_field.dart';
import 'package:couple_app/features/plans/widgets/soft_kit.dart';
import 'package:couple_app/features/plans/widgets/date_plan_card.dart';

/// Add or edit a date plan. New plans are ideas unless a date is picked.
class DatePlanEditorScreen extends ConsumerStatefulWidget {
  const DatePlanEditorScreen({super.key, this.plan, this.scheduleNew = false});

  final DatePlan? plan;

  /// For a new plan: start with "Pick a date" switched on.
  final bool scheduleNew;

  @override
  ConsumerState<DatePlanEditorScreen> createState() =>
      _DatePlanEditorScreenState();
}

class _DatePlanEditorScreenState extends ConsumerState<DatePlanEditorScreen> {
  late final String _coupleId;
  late final String _myUid;
  late final DatePlanService _service;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _service = ref.read(datePlanServiceProvider);
  }

  final _formKey = GlobalKey<FormState>();

  late final DatePlan? _original = widget.plan;
  late final bool _isDone = _original?.isDone ?? false;
  late final _title = TextEditingController(text: _original?.title ?? '');
  late final _location = TextEditingController(text: _original?.location ?? '');
  late final _notes = TextEditingController(text: _original?.notes ?? '');
  late final _reflection = TextEditingController(
    text: _original?.reflection ?? '',
  );
  late final _cost = TextEditingController(
    text: _original?.estimatedCostMinor == null
        ? ''
        : DatePlanCost.toInput(_original!.estimatedCostMinor!),
  );

  late DateVibe _vibe = _original?.vibe ?? DateVibe.cozy;
  late bool _scheduled = _original == null
      ? widget.scheduleNew
      : !_original.isIdea && _original.scheduledAt != null;
  late DateTime _when = _original?.scheduledAt ?? _defaultWhen();
  late int? _rating = _original?.rating;

  bool _saving = false;

  static DateTime _defaultWhen() {
    final now = DateTime.now();
    // The coming Saturday evening.
    final daysToSaturday = (DateTime.saturday - now.weekday) % 7;
    return DateTime(now.year, now.month, now.day + daysToSaturday, 19, 30);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _reflection.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (picked == null) return;
    setState(
      () => _when = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _when.hour,
        _when.minute,
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (picked == null) return;
    setState(
      () => _when = DateTime(
        _when.year,
        _when.month,
        _when.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  Future<void> _toggleSchedule(bool on) async {
    if (!on) {
      setState(() => _scheduled = false);
      return;
    }
    final picked = await pickDatePlanDateTime(context, initial: _when);
    if (picked != null) {
      setState(() {
        _when = picked;
        _scheduled = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final costText = _cost.text.trim();
    final status = _isDone
        ? DatePlanStatus.done
        : _scheduled
        ? DatePlanStatus.planned
        : DatePlanStatus.idea;

    final plan = DatePlan(
      id: _original?.id ?? '',
      title: _title.text,
      notes: _notes.text,
      status: status,
      scheduledAt: status == DatePlanStatus.idea
          ? null
          : (_scheduled ? _when : _original?.scheduledAt),
      location: _location.text,
      estimatedCostMinor: costText.isEmpty
          ? null
          : DatePlanCost.parseMinor(costText),
      vibe: _vibe,
      rating: _isDone ? _rating : null,
      reflection: _isDone ? _reflection.text : (_original?.reflection ?? ''),
      // The creator never changes, even when the partner edits.
      createdBy: _original?.createdBy ?? _myUid,
      completedAt: _isDone ? _original?.completedAt : null,
    );

    setState(() => _saving = true);
    try {
      await _service.save(_coupleId, plan);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not save. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(coupleProvider).value?.currency ?? 'INR';
    final partnerName = ref.watch(partnerNameProvider);
    final isEditing = _original != null;

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isEditing
                ? (_isDone ? 'Edit date' : 'Edit plan')
                : (_scheduled ? 'Plan a date' : 'New date idea'),
          ),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (!isEditing)
                EditorHeaderStrip(
                  emoji: _vibe.emoji,
                  preset: DatePlanLook.presetFor(_vibe),
                  text: 'Dream it up now, make it happen soon.',
                ),
              TextFormField(
                controller: _title,
                autofocus: !isEditing,
                textCapitalization: TextCapitalization.sentences,
                maxLength: DatePlan.maxTitle,
                decoration: const InputDecoration(
                  labelText: 'What\'s the plan?',
                  hintText: 'e.g. Sunset picnic at Cubbon Park',
                  counterText: '',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Add a title' : null,
              ),
              const SizedBox(height: 20),
              const SoftFieldLabel('Vibe'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in DateVibe.values)
                    ChoiceChip(
                      label: Text('${v.emoji} ${v.label}'),
                      selected: _vibe == v,
                      onSelected: (_) => setState(() => _vibe = v),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_isDone)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pick a date'),
                  subtitle: Text(
                    _scheduled
                        ? 'It goes on your calendar for you and $partnerName.'
                        : 'Leave off to keep it as an idea for later.',
                  ),
                  value: _scheduled,
                  onChanged: _toggleSchedule,
                ),
              if (_scheduled) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: EventPickerField(
                        label: 'Date',
                        icon: Icons.event_outlined,
                        value: DateFormat.yMMMEd().format(_when),
                        onTap: _pickDay,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 132,
                      child: EventPickerField(
                        label: 'Time',
                        icon: Icons.schedule,
                        value: DateFormat.jm().format(_when),
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                textCapitalization: TextCapitalization.words,
                maxLength: DatePlan.maxLocation,
                decoration: const InputDecoration(
                  labelText: 'Where (optional)',
                  prefixIcon: Icon(Icons.place_outlined),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Rough cost (optional)',
                  helperText: 'Enter 0 if it\'s free.',
                  prefixText: '${DatePlanCost.symbol(currency)} ',
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return null;
                  return DatePlanCost.parseMinor(t) == null
                      ? 'Enter an amount like 1,250 or 499.50'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 6,
                maxLength: DatePlan.maxNotes,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  hintText: 'Book ahead, bring a blanket, dress code…',
                  prefixIcon: Icon(Icons.notes),
                  counterText: '',
                ),
              ),
              if (_isDone) ...[
                const Divider(height: 32),
                const SoftFieldLabel('How it went'),
                DatePlanHearts(
                  rating: _rating,
                  size: 28,
                  onChanged: (r) => setState(() => _rating = r),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _reflection,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: DatePlan.maxReflection,
                  decoration: const InputDecoration(
                    hintText: 'A favourite moment, a funny bit…',
                    counterText: '',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
