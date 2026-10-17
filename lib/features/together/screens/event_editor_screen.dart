import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/together/models/calendar_event.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:couple_app/features/together/widgets/event_picker_field.dart';

/// Add or edit a calendar event.
class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({
    super.key,
    this.event,
    this.initialDay,
    this.initialType,
  });

  final CalendarEvent? event;
  final DateTime? initialDay;
  final EventType? initialType;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  late final String _coupleId;
  late final String _myUid;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
  }

  final _formKey = GlobalKey<FormState>();

  late final CalendarEvent? _original = widget.event;
  late final _title = TextEditingController(text: _original?.title ?? '');
  late final _location = TextEditingController(text: _original?.location ?? '');
  late final _notes = TextEditingController(text: _original?.notes ?? '');
  late final _budget = TextEditingController(
    text: _original?.budget == null ? '' : '${_original!.budget}',
  );

  late EventType _type =
      _original?.type ?? widget.initialType ?? EventType.dateNight;
  late bool _allDay = _original?.allDay ?? _type != EventType.dateNight;
  late DateTime _date = _dateOnly(
    _original?.start ?? widget.initialDay ?? DateTime.now(),
  );
  late TimeOfDay _time = _original == null || _original.allDay
      ? const TimeOfDay(hour: 19, minute: 30)
      : TimeOfDay.fromDateTime(_original.start);
  late DateTime? _endDate = _original?.end == null
      ? null
      : _dateOnly(_original!.end!);
  late bool _repeatYearly =
      _original?.repeatYearly ??
      (_type == EventType.birthday || _type == EventType.anniversary);
  late bool _private = _original?.isPrivate ?? false;
  late ReminderOption _reminder = _original?.reminder ?? ReminderOption.day;

  bool _saving = false;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _setType(EventType type) {
    setState(() {
      _type = type;
      if (_original == null) {
        _allDay = type != EventType.dateNight;
        _repeatYearly =
            type == EventType.birthday || type == EventType.anniversary;
        if (type != EventType.trip) _endDate = null;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1970),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      final end = _endDate;
      if (end != null && end.isBefore(picked)) _endDate = picked;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _date,
      firstDate: _date,
      lastDate: DateTime(DateTime.now().year + 10),
      helpText: 'Last day',
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final start = _allDay
        ? _date
        : DateTime(
            _date.year,
            _date.month,
            _date.day,
            _time.hour,
            _time.minute,
          );
    final budgetText = _budget.text.replaceAll(',', '').trim();

    final event = CalendarEvent(
      id: _original?.id ?? '',
      title: _title.text,
      type: _type,
      start: start,
      end: _endDate,
      allDay: _allDay,
      location: _location.text,
      notes: _notes.text,
      budget: budgetText.isEmpty ? null : num.tryParse(budgetText),
      repeatYearly: _repeatYearly,
      isPrivate: _private,
      reminder: _reminder,
      // The creator never changes, even when the partner edits.
      createdBy: _original?.createdBy ?? _myUid,
    );

    try {
      await ref
          .read(eventServiceProvider)
          .save(coupleId: _coupleId, event: event);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Could not save. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = _original != null;
    // Only the creator can change who sees an event.
    final canChangePrivacy = _original == null || _original.createdBy == _myUid;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit event' : 'New event'),
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in EventType.values)
                  if (t != EventType.meetup)
                    ChoiceChip(
                      label: Text('${t.emoji} ${t.label}'),
                      selected: _type == t,
                      onSelected: (_) => _setType(t),
                    ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: switch (_type) {
                  EventType.dateNight => 'e.g. Dinner at Toit',
                  EventType.trip => 'e.g. Coorg weekend',
                  EventType.birthday => 'e.g. Amma\'s birthday',
                  EventType.anniversary => 'e.g. Engagement anniversary',
                  _ => 'What\'s happening?',
                },
                counterText: '',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Add a title' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('All day'),
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
            ),
            Row(
              children: [
                Expanded(
                  child: EventPickerField(
                    label: _type == EventType.trip ? 'From' : 'Date',
                    icon: Icons.event_outlined,
                    value: DateFormat.yMMMEd().format(_date),
                    onTap: _pickDate,
                  ),
                ),
                if (!_allDay) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 132,
                    child: EventPickerField(
                      label: 'Time',
                      icon: Icons.schedule,
                      value: _time.format(context),
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ],
            ),
            if (_type == EventType.trip) ...[
              const SizedBox(height: 12),
              EventPickerField(
                label: 'Until (optional)',
                icon: Icons.event_available_outlined,
                value: _endDate == null
                    ? 'Single day'
                    : DateFormat.yMMMEd().format(_endDate!),
                onTap: _pickEndDate,
                trailing: _endDate == null
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _endDate = null),
                      ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                prefixIcon: Icon(Icons.place_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _budget,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Budget (optional)',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              validator: (v) {
                final t = (v ?? '').replaceAll(',', '').trim();
                if (t.isEmpty) return null;
                return num.tryParse(t) == null ? 'Enter a number' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.notes),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReminderOption>(
              initialValue: _reminder,
              decoration: const InputDecoration(
                labelText: 'Reminder',
                prefixIcon: Icon(Icons.notifications_none),
              ),
              items: [
                for (final r in ReminderOption.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setState(() => _reminder = r ?? _reminder),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repeat every year'),
              subtitle: const Text('For birthdays and anniversaries'),
              value: _repeatYearly,
              onChanged: (v) => setState(() => _repeatYearly = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Private'),
              subtitle: Text(
                canChangePrivacy
                    ? 'Only you will see it. Good for surprises.'
                    : 'Only the person who created it can change this.',
              ),
              value: _private,
              onChanged: canChangePrivacy
                  ? (v) => setState(() => _private = v)
                  : null,
            ),
            if (_private)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your partner will not see this event or its '
                        'reminders.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
