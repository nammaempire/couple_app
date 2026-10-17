import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/services/voice_recorder.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/home/models/important_date.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:couple_app/features/together/widgets/note_paper.dart';
import 'package:couple_app/features/together/widgets/voice_note_recorder.dart';

enum _When { now, date }

/// Write a love note: a letter delivered now or on a date, or an
/// "Open when…" envelope.
class NoteComposerScreen extends ConsumerStatefulWidget {
  const NoteComposerScreen({super.key, this.template});

  /// Start as an "Open when…" note of this kind.
  final OpenWhen? template;

  @override
  ConsumerState<NoteComposerScreen> createState() => _NoteComposerScreenState();
}

class _NoteComposerScreenState extends ConsumerState<NoteComposerScreen> {
  // Read once when the composer opens, as the old constructor arguments were.
  late final String _coupleId;
  late final String _myUid;
  late final String? _partnerUid;
  late final DateTime? _partnerBirthday;

  /// The day you started, for anniversary delivery.
  late final DateTime? _anniversary;

  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  late NoteKind _kind = widget.template == null
      ? NoteKind.letter
      : NoteKind.openWhen;
  late OpenWhen _openWhen = widget.template ?? OpenWhen.missMe;
  _When _when = _When.now;
  DateTime? _deliverAt;
  RecordedVoice? _voice;
  bool _recording = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final couple = ref.read(coupleProvider).value;
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _partnerUid = couple?.partnerIdFor(_myUid);
    _partnerBirthday = ref.read(partnerProvider).value?.birthday;
    _anniversary = couple?.startDate;
    _applyTemplateDefaults();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Birthday and anniversary envelopes default to arriving on that day.
  void _applyTemplateDefaults() {
    if (_kind != NoteKind.openWhen) return;
    final day = _suggestedDay(_openWhen);
    if (day != null) {
      _when = _When.date;
      _deliverAt = DateTime(day.year, day.month, day.day, 8);
    } else {
      _when = _When.now;
      _deliverAt = null;
    }
  }

  DateTime? _suggestedDay(OpenWhen template) {
    final today = DateTime.now();
    return switch (template) {
      OpenWhen.birthday =>
        _partnerBirthday == null
            ? null
            : ImportantDate.nextAnnual(_partnerBirthday, today),
      OpenWhen.anniversary =>
        _anniversary == null
            ? null
            : ImportantDate.nextAnnual(
                DateTime(
                  _anniversary.year + 1,
                  _anniversary.month,
                  _anniversary.day,
                ),
                today,
              ),
      _ => null,
    };
  }

  Future<void> _pickDeliveryTime() async {
    final now = DateTime.now();
    final initial = _deliverAt ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      helpText: 'Deliver on',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'At',
    );
    if (time == null) return;
    setState(() {
      _when = _When.date;
      _deliverAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (_body.text.trim().isEmpty && _voice == null) {
      context.showSnackMessage('Write something or record a voice letter.');
      return;
    }

    if (_recording) {
      context.showSnackMessage('Stop the recording first.');
      return;
    }

    final now = DateTime.now();
    var deliverAt = _when == _When.date && _deliverAt != null
        ? _deliverAt!
        : now;
    // "On the day" for today, after 8am: deliver right away.
    if (_when == _When.date &&
        deliverAt.isBefore(now) &&
        DateUtils.isSameDay(deliverAt, now)) {
      deliverAt = now;
    }
    if (_when == _When.date && deliverAt.isBefore(now)) {
      context.showSnackMessage('Pick a delivery time in the future.');
      return;
    }

    final partnerUid = _partnerUid;
    if (partnerUid == null) {
      context.showSnackMessage('Pair with your partner first.');
      return;
    }
    final partnerName = ref.read(partnerNameProvider);

    setState(() => _sending = true);
    try {
      await ref
          .read(loveNoteServiceProvider)
          .send(
            coupleId: _coupleId,
            senderId: _myUid,
            recipientId: partnerUid,
            kind: _kind,
            openWhen: _kind == NoteKind.openWhen ? _openWhen : null,
            title: _kind == NoteKind.openWhen ? _openWhen.label : _title.text,
            body: _body.text,
            deliverAt: deliverAt,
            voiceFile: _voice?.file,
            voiceDuration: _voice?.duration,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
      context.showSnackMessage(
        deliverAt.isAfter(now.add(const Duration(minutes: 1)))
            ? 'Sealed. $partnerName can open it on '
                  '${DateFormat.MMMd().add_jm().format(deliverAt)}.'
            : 'Sent to $partnerName 💌',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      context.showSnackMessage('Could not send. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partnerName = ref.watch(partnerNameProvider);
    final suggested = _kind == NoteKind.openWhen
        ? _suggestedDay(_openWhen)
        : null;

    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        appBar: AppBar(
          title: Text('To $partnerName'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _sending ? null : () => Navigator.pop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _sending || _recording ? null : _send,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_when == _When.date ? 'Seal' : 'Send'),
              ),
            ),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _sending,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                SegmentedButton<NoteKind>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: NoteKind.letter,
                      icon: Icon(Icons.mail_outline),
                      label: Text('Letter'),
                    ),
                    ButtonSegment(
                      value: NoteKind.openWhen,
                      icon: Icon(Icons.drafts_outlined),
                      label: Text('Open when…'),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() {
                    _kind = s.first;
                    _applyTemplateDefaults();
                  }),
                ),
                const SizedBox(height: 16),
                if (_kind == NoteKind.openWhen) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in OpenWhen.values)
                        ChoiceChip(
                          avatar: Text(t.emoji),
                          label: Text(t.label),
                          selected: _openWhen == t,
                          onSelected: (_) => setState(() {
                            _openWhen = t;
                            _applyTemplateDefaults();
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  TextFormField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: 'On the envelope (optional)',
                      hintText: 'e.g. For no reason at all',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                NotePaper(
                  child: TextFormField(
                    controller: _body,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 8,
                    maxLines: 20,
                    maxLength: 4000,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    decoration: InputDecoration(
                      hintText: 'Dear $partnerName,',
                      filled: false,
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                VoiceNoteRecorder(
                  onChanged: (v) => _voice = v,
                  onRecordingChanged: (r) => setState(() => _recording = r),
                ),
                const SizedBox(height: 20),
                Text('Deliver', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Now'),
                      selected: _when == _When.now,
                      onSelected: (_) => setState(() {
                        _when = _When.now;
                        _deliverAt = null;
                      }),
                    ),
                    if (suggested != null)
                      ChoiceChip(
                        label: Text(
                          'On the day · ${DateFormat.MMMd().format(suggested)}',
                        ),
                        selected:
                            _when == _When.date &&
                            _deliverAt != null &&
                            DateUtils.isSameDay(_deliverAt, suggested),
                        onSelected: (_) => setState(() {
                          _when = _When.date;
                          _deliverAt = DateTime(
                            suggested.year,
                            suggested.month,
                            suggested.day,
                            8,
                          );
                        }),
                      ),
                    ChoiceChip(
                      avatar: const Icon(Icons.schedule, size: 18),
                      label: Text(
                        _when == _When.date &&
                                _deliverAt != null &&
                                (suggested == null ||
                                    !DateUtils.isSameDay(_deliverAt, suggested))
                            ? DateFormat.MMMd().add_jm().format(_deliverAt!)
                            : 'Pick a date',
                      ),
                      selected:
                          _when == _When.date &&
                          _deliverAt != null &&
                          (suggested == null ||
                              !DateUtils.isSameDay(_deliverAt, suggested)),
                      onSelected: (_) => _pickDeliveryTime(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _when == _When.date && _deliverAt != null
                      ? '$partnerName will see a sealed envelope and '
                            'can open it from '
                            '${DateFormat.yMMMMd().add_jm().format(_deliverAt!)}.'
                      : _kind == NoteKind.openWhen
                      ? '$partnerName can keep it sealed and open '
                            'it when the moment comes.'
                      : '$partnerName can read it right away.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
